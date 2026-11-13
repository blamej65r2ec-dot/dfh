import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/common.dart';
import '../services/drafts.dart';
import '../widgets/animations.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import '../widgets/segmented_pill.dart';
import '../widgets/waveform.dart';

/// Step 2 of posting: caption, mood and who can hear it. Shows a preview post.
/// Pops with 'posted' or 'draft' (or null if you go back).
class PostDetailsPage extends StatefulWidget {
  const PostDetailsPage({
    super.key,
    required this.audioPath,
    required this.durationMs,
    required this.bars,
    required this.storyMode,
    required this.storyHours,
    this.draftId,
    this.initialMood,
    this.initialCaption = '',
    this.initialVisibility = 'public',
  });

  final String audioPath;
  final int durationMs;
  final List<double> bars;
  final bool storyMode;
  final int storyHours;
  final String? draftId;
  final String? initialMood;
  final String initialCaption;
  final String initialVisibility;

  @override
  State<PostDetailsPage> createState() => _PostDetailsPageState();
}

const _visKeys = ['public', 'followers', 'private'];

class _PostDetailsPageState extends State<PostDetailsPage> {
  final _c = Supabase.instance.client;
  final _player = AudioPlayer();
  final _caption = TextEditingController();
  String? _mood;
  int _vis = 0;
  bool _busy = false;
  bool _playing = false;
  bool _loaded = false;
  double _progress = 0;
  String? _error;
  String _name = '';
  String? _avatar;

  @override
  void initState() {
    super.initState();
    _mood = widget.initialMood;
    _caption.text = widget.initialCaption;
    _vis = _visKeys.indexOf(widget.initialVisibility).clamp(0, 2);
    _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
        if (mounted) setState(() => _progress = 0);
      }
      final pl = s.playing && s.processingState != ProcessingState.completed;
      if (mounted && pl != _playing) setState(() => _playing = pl);
    });
    _player.positionStream.listen((pos) {
      final d = _player.duration;
      if (mounted && d != null && d.inMilliseconds > 0 && _playing) {
        setState(() => _progress =
            (pos.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0).toDouble());
      }
    });
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await _c
          .from('profiles')
          .select('username,nickname,avatar_path')
          .eq('id', _c.auth.currentUser!.id)
          .single();
      final nick = (p['nickname'] as String?) ?? '';
      if (mounted) {
        setState(() {
          _name = nick.isNotEmpty ? nick : '@${p['username']}';
          _avatar = p['avatar_path'] as String?;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _player.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    HapticFeedback.selectionClick();
    try {
      if (!_loaded) {
        await _player.setFilePath(widget.audioPath);
        _loaded = true;
      }
      if (_player.playing) {
        await _player.pause();
      } else {
        _player.play();
      }
    } catch (_) {}
  }

  List<double> _previewBars() {
    // Squeeze the recorded bars into 28 bars for the preview card.
    const n = 28;
    final src = widget.bars;
    if (src.isEmpty) return List.filled(n, 12.0);
    return [
      for (var i = 0; i < n; i++)
        (() {
          final a = (i * src.length / n).floor();
          final b = ((i + 1) * src.length / n).ceil().clamp(a + 1, src.length);
          var sum = 0.0;
          for (var k = a; k < b; k++) {
            sum += src[k];
          }
          final avg = sum / (b - a);
          return ((avg - 8) / 52 * 48 + 8).clamp(8.0, 56.0).toDouble();
        })(),
    ];
  }

  Future<void> _saveDraft() async {
    setState(() => _busy = true);
    await _player.stop();
    try {
      await DraftStore.add(Draft(
        id: widget.draftId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        path: widget.audioPath,
        durationMs: widget.durationMs,
        mood: _mood,
        caption: _caption.text.trim(),
        visibility: _visKeys[_vis],
      ));
      if (mounted) Navigator.of(context).pop('draft');
      return;
    } catch (_) {
      _error = 'Could not save the draft.';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _post() async {
    final mood = _mood;
    if (mood == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    await _player.stop();
    try {
      final uid = _c.auth.currentUser!.id;
      final isWav = widget.audioPath.toLowerCase().endsWith('.wav');
      final storagePath =
          '$uid/${DateTime.now().millisecondsSinceEpoch}.${isWav ? 'wav' : 'm4a'}';
      await _c.storage.from('voices').upload(
            storagePath,
            File(widget.audioPath),
            fileOptions:
                FileOptions(contentType: isWav ? 'audio/wav' : 'audio/mp4'),
          );
      final cap = _caption.text.trim();
      final row = {
        'user_id': uid,
        'audio_path': storagePath,
        'caption': cap.isEmpty ? null : cap,
        'mood': mood,
        'duration_ms': widget.durationMs,
        'kind': widget.storyMode ? 'story' : 'post',
        if (widget.storyMode)
          'expires_at': DateTime.now()
              .toUtc()
              .add(Duration(hours: widget.storyHours))
              .toIso8601String(),
      };
      try {
        await _c.from('voices').insert({...row, 'visibility': _visKeys[_vis]});
      } on PostgrestException catch (e) {
        // update4.sql not run yet: post without the privacy option.
        if (e.message.toLowerCase().contains('visibility')) {
          await _c.from('voices').insert(row);
        } else {
          rethrow;
        }
      }
      if (widget.draftId != null) await DraftStore.removeById(widget.draftId!);
      if (mounted) Navigator.of(context).pop('posted');
      return;
    } on StorageException catch (e) {
      _error = e.message;
    } on PostgrestException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _previewCard() {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final cap = _caption.text.trim();
    return GlassBox(
      blur: false,
      radius: 30,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.onSurface, width: 2),
                ),
                child: ClipOval(
                    child: Avatar(name: _name, path: _avatar, size: 40)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_name.isEmpty ? 'You' : _name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 16)),
                    Text('now',
                        style: TextStyle(
                            fontSize: 13, color: cs.onSurface.withAlpha(150))),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Text(
                  _mood == null ? '·' : moodOf(_mood!).emoji,
                  key: ValueKey(_mood),
                  style: const TextStyle(fontSize: 28),
                ),
              ),
            ],
          ),
          if (cap.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(cap, style: const TextStyle(fontSize: 15, height: 1.45)),
          ],
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlay,
            child: SizedBox(
              height: 64,
              width: double.infinity,
              child: CustomPaint(
                size: Size.infinite,
                painter: FixedBarsPainter(
                  heights: _previewBars(),
                  progress: _progress,
                  on: cs.onSurface,
                  off: dark
                      ? const Color.fromRGBO(255, 255, 255, .3)
                      : const Color.fromRGBO(0, 0, 0, .2),
                ),
              ),
            ),
          ),
          Row(
            children: [
              Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 20, color: cs.onSurface.withAlpha(170)),
              const SizedBox(width: 4),
              Text(fmtDuration(widget.durationMs),
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurface.withAlpha(170))),
              const Spacer(),
              Icon(
                  _vis == 0
                      ? Icons.public_rounded
                      : _vis == 1
                          ? Icons.group_outlined
                          : Icons.lock_outline_rounded,
                  size: 16,
                  color: cs.onSurface.withAlpha(150)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grey = cs.onSurface.withAlpha(150);
    final canPost = _mood != null && !_busy;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: _busy ? null : () => Navigator.of(context).maybePop(),
                  child: GlassBox(
                    radius: 23,
                    child: const SizedBox(
                      width: 46,
                      height: 46,
                      child: Icon(Icons.chevron_left_rounded, size: 28),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Text(widget.storyMode ? 'New story' : 'New voice',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 20),
            FadeSlideIn(child: _previewCard()),
            const SizedBox(height: 22),
            Row(
              children: [
                const Text('Caption',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${_caption.text.length}/60',
                    style: TextStyle(fontSize: 12, color: grey)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _caption,
              maxLength: 60,
              maxLines: 1,
              onChanged: (_) => setState(() {}),
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'[\n\r]'))
              ],
              decoration: const InputDecoration(
                hintText: 'Say what this voice is about',
                counterText: '',
              ),
            ),
            const SizedBox(height: 20),
            const Text('Mood', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final m in moods)
                  PressScale(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _mood = m.key);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _mood == m.key
                              ? cs.onSurface.withAlpha(60)
                              : cs.onSurface.withAlpha(20),
                          border: Border.all(
                            color: _mood == m.key
                                ? cs.onSurface
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child:
                            Text(m.emoji, style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                  ),
              ],
            ),
            if (_mood == 'help')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'If things feel heavy, reaching out to someone you trust can help.',
                  style: TextStyle(fontSize: 13, color: grey),
                ),
              ),
            const SizedBox(height: 22),
            const Text('Who can hear this',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SegmentedPill(
              labels: const ['Everyone', 'Followers', 'Only me'],
              selected: _vis,
              onChanged: (i) => setState(() => _vis = i),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: cs.error)),
              ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _busy ? null : _saveDraft,
                    child: Opacity(
                      opacity: _busy ? 0.45 : 1,
                      child: GlassBox(
                        blur: false,
                        radius: 27,
                        child: const SizedBox(
                          height: 54,
                          child: Center(
                            child: Text('Save draft',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PressScale(
                    child: GestureDetector(
                      onTap: canPost ? _post : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: cs.primary.withAlpha(canPost ? 255 : 100),
                          borderRadius: BorderRadius.circular(27),
                        ),
                        child: _busy
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: cs.onPrimary),
                              )
                            : Text(
                                _mood == null
                                    ? 'Pick a mood'
                                    : (widget.storyMode
                                        ? 'Share story'
                                        : 'Post'),
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onPrimary),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
