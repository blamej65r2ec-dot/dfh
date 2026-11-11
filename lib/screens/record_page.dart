import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/common.dart';
import '../services/drafts.dart';
import '../widgets/animations.dart';
import '../widgets/glass.dart';
import '../widgets/waveform.dart';

enum _Phase { idle, recording, review }

class RecordPage extends StatefulWidget {
  const RecordPage({super.key, required this.onPosted});
  final VoidCallback onPosted;

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final _rec = AudioRecorder();
  final _preview = AudioPlayer();
  final _caption = TextEditingController();
  final _watch = Stopwatch();
  Timer? _tick;
  StreamSubscription<Amplitude>? _ampSub;
  final List<double> _levels = List<double>.filled(32, 0.05, growable: true);

  _Phase _phase = _Phase.idle;
  String? _path;
  String? _draftId;
  int _durationMs = 0;
  String? _mood;
  bool _busy = false;
  bool _previewPlaying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _preview.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _preview.pause();
        _preview.seek(Duration.zero);
      }
      final pl = s.playing && s.processingState != ProcessingState.completed;
      if (mounted && pl != _previewPlaying) {
        setState(() => _previewPlaying = pl);
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _ampSub?.cancel();
    _rec.dispose();
    _preview.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    if (!await _rec.hasPermission()) {
      setState(() => _error = 'Microphone permission is needed to record.');
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/rec');
    await folder.create(recursive: true);
    final path = '${folder.path}/${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 96000,
        sampleRate: 44100,
      ),
      path: path,
    );
    HapticFeedback.mediumImpact();
    _watch
      ..reset()
      ..start();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
    _ampSub = _rec
        .onAmplitudeChanged(const Duration(milliseconds: 90))
        .listen((a) {
      final v = ((a.current + 50) / 50).clamp(0.05, 1.0).toDouble();
      if (!mounted) return;
      setState(() {
        _levels.removeAt(0);
        _levels.add(v);
      });
    });
    setState(() {
      _phase = _Phase.recording;
      _path = path;
      _draftId = null;
    });
  }

  Future<void> _stop() async {
    _tick?.cancel();
    await _ampSub?.cancel();
    _watch.stop();
    final p = await _rec.stop();
    HapticFeedback.lightImpact();
    _durationMs = _watch.elapsedMilliseconds;
    if (p == null || _durationMs < 800) {
      if (p != null) {
        try {
          await File(p).delete();
        } catch (_) {}
      }
      _reset();
      setState(() => _error = 'That was too short. Try again.');
      return;
    }
    try {
      await _preview.setFilePath(p);
    } catch (_) {}
    setState(() {
      _path = p;
      _phase = _Phase.review;
    });
  }

  void _reset() {
    _caption.clear();
    for (var i = 0; i < _levels.length; i++) {
      _levels[i] = 0.05;
    }
    setState(() {
      _phase = _Phase.idle;
      _path = null;
      _draftId = null;
      _mood = null;
      _durationMs = 0;
      _previewPlaying = false;
    });
  }

  void _togglePreview() {
    if (_preview.playing) {
      _preview.pause();
    } else {
      _preview.play();
    }
  }

  Future<void> _discard() async {
    await _preview.stop();
    final p = _path;
    if (_draftId != null) await DraftStore.removeById(_draftId!);
    if (p != null) {
      try {
        await File(p).delete();
      } catch (_) {}
    }
    _reset();
  }

  Future<void> _saveDraft() async {
    final p = _path;
    if (p == null) return;
    await _preview.stop();
    await DraftStore.add(Draft(
      id: _draftId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      path: p,
      durationMs: _durationMs,
      mood: _mood,
      caption: _caption.text.trim(),
    ));
    _reset();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved to drafts')));
  }

  Future<void> _openDrafts() async {
    final d = await showModalBottomSheet<Draft>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _DraftsSheet(),
    );
    if (d == null) return;
    try {
      await _preview.setFilePath(d.path);
    } catch (_) {}
    _caption.text = d.caption;
    setState(() {
      _path = d.path;
      _draftId = d.id;
      _durationMs = d.durationMs;
      _mood = d.mood;
      _phase = _Phase.review;
    });
  }

  Future<void> _post() async {
    final path = _path;
    final mood = _mood;
    if (path == null || mood == null) return;
    await _preview.stop();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = Supabase.instance.client;
      final uid = c.auth.currentUser!.id;
      final storagePath = '$uid/${DateTime.now().millisecondsSinceEpoch}.m4a';
      await c.storage.from('voices').upload(
            storagePath,
            File(path),
            fileOptions: const FileOptions(contentType: 'audio/mp4'),
          );
      final cap = _caption.text.trim();
      await c.from('voices').insert({
        'user_id': uid,
        'audio_path': storagePath,
        'caption': cap.isEmpty ? null : cap,
        'mood': mood,
        'duration_ms': _durationMs,
        'kind': 'post',
      });
      if (_draftId != null) await DraftStore.removeById(_draftId!);
      try {
        await File(path).delete();
      } catch (_) {}
      _reset();
      widget.onPosted();
    } on StorageException catch (e) {
      _error = e.message;
    } on PostgrestException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  // ---------- views ----------

  Widget _idle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('idle'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Speak',
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Tap to start. No time limit.',
            style: TextStyle(color: cs.onSurface.withAlpha(160))),
        const SizedBox(height: 40),
        PressScale(
          scale: 0.92,
          child: GestureDetector(
            onTap: _start,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary,
                boxShadow: const [
                  BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, .35),
                      blurRadius: 24,
                      offset: Offset(0, 8)),
                ],
              ),
              child: Icon(Icons.mic_rounded, size: 52, color: cs.onPrimary),
            ),
          ),
        ),
        const SizedBox(height: 32),
        TextButton.icon(
          onPressed: _openDrafts,
          icon: const Icon(Icons.folder_open_rounded),
          label: const Text('Drafts'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: cs.error)),
        ],
      ],
    );
  }

  Widget _recording(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('recording'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fmtDuration(_watch.elapsedMilliseconds),
          style: Theme.of(context)
              .textTheme
              .displayMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 90,
          width: double.infinity,
          child: CustomPaint(
            painter: WaveformPainter(
              bars: List<double>.from(_levels),
              progress: 1,
              color: cs.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 40),
        PressScale(
          scale: 0.92,
          child: GestureDetector(
            onTap: _stop,
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary),
              child: Icon(Icons.stop_rounded, size: 44, color: cs.onPrimary),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Tap to stop'),
      ],
    );
  }

  Widget _review(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassBox(
      key: const ValueKey('review'),
      radius: 32,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PressScale(
                child: GestureDetector(
                  onTap: _togglePreview,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: cs.primary),
                    child: Icon(
                      _previewPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: cs.onPrimary,
                      size: 30,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(fmtDuration(_durationMs),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700)),
              const Spacer(),
              const Text('Listen before posting'),
            ],
          ),
          const SizedBox(height: 22),
          const Text('Mood', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
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
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _mood == m.key
                            ? cs.primary
                            : cs.onSurface.withAlpha(24),
                      ),
                      child: Text(m.emoji, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                ),
            ],
          ),
          if (_mood == 'help')
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'If things feel heavy, reaching out to someone you trust can help.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          const SizedBox(height: 18),
          TextField(
            controller: _caption,
            maxLength: 60,
            maxLines: 1,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'[\n\r]'))],
            decoration: const InputDecoration(
              hintText: 'Say what this voice is about',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
          const SizedBox(height: 14),
          PressScale(
            child: FilledButton(
              onPressed: (_mood == null || _busy) ? null : _post,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text(_mood == null ? 'Pick a mood to post' : 'Post'),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _busy ? null : _saveDraft,
                  child: const Text('Save draft'),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: _busy ? null : _discard,
                  child: const Text('Discard'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final view = switch (_phase) {
      _Phase.idle => _idle(context),
      _Phase.recording => _recording(context),
      _Phase.review => _review(context),
    };
    return SafeArea(
      bottom: false,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 130 + bottom),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(anim),
                child: child,
              ),
            ),
            child: view,
          ),
        ),
      ),
    );
  }
}

class _DraftsSheet extends StatefulWidget {
  const _DraftsSheet();

  @override
  State<_DraftsSheet> createState() => _DraftsSheetState();
}

class _DraftsSheetState extends State<_DraftsSheet> {
  List<Draft>? _list;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final l = await DraftStore.load();
    if (mounted) setState(() => _list = l);
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GlassBox(
        radius: 32,
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Drafts',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              if (list == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No drafts yet')),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final d in list)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Text(
                            d.mood == null ? '🎙️' : moodOf(d.mood!).emoji,
                            style: const TextStyle(fontSize: 28),
                          ),
                          title: Text(
                            d.caption.isEmpty ? 'No caption' : d.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(fmtDuration(d.durationMs)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              await DraftStore.removeById(d.id,
                                  deleteAudio: true);
                              _refresh();
                            },
                          ),
                          onTap: () => Navigator.of(context).pop(d),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
