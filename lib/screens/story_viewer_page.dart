import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/common.dart';
import '../services/stories.dart';
import '../services/voice_player.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import '../widgets/hold_record_button.dart';
import '../widgets/waveform.dart';

/// Voice stories viewer, as in the design.
class StoryViewerPage extends StatefulWidget {
  const StoryViewerPage({
    super.key,
    required this.groups,
    this.startGroup = 0,
  });

  final List<StoryGroup> groups;
  final int startGroup;

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage> {
  final _c = Supabase.instance.client;
  final _player = VoicePlayer.instance;
  late int _gi;
  int _si = 0;
  bool _paused = false;
  final Map<String, bool> _liked = {};
  late final List<StoryGroup> _groups;

  String get _me => _c.auth.currentUser!.id;
  StoryGroup get _group => _groups[_gi];
  Map<String, dynamic> get _story => _group.stories[_si];

  @override
  void initState() {
    super.initState();
    _groups = List<StoryGroup>.of(widget.groups);
    _gi = widget.startGroup.clamp(0, _groups.length - 1).toInt();
    _player.finished.addListener(_onFinished);
    _start();
  }

  @override
  void dispose() {
    _player.finished.removeListener(_onFinished);
    _player.stop();
    super.dispose();
  }

  void _onFinished() {
    if (mounted) _next();
  }

  Future<void> _start() async {
    final s = _story;
    final id = s['id'] as String;
    Stories.markSeen(id);
    setState(() => _paused = false);
    _player.play(id, s['audio_path'] as String);
    if (!_liked.containsKey(id)) {
      try {
        final r = await _c
            .from('likes')
            .select('voice_id')
            .eq('voice_id', id)
            .eq('user_id', _me);
        if (mounted) setState(() => _liked[id] = r.isNotEmpty);
      } catch (_) {}
    }
  }

  void _next() {
    if (_si < _group.stories.length - 1) {
      setState(() => _si++);
      _start();
    } else if (_gi < _groups.length - 1) {
      setState(() {
        _gi++;
        _si = 0;
      });
      _start();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _prev() {
    if (_player.position.value > const Duration(seconds: 2)) {
      _start();
    } else if (_si > 0) {
      setState(() => _si--);
      _start();
    } else if (_gi > 0) {
      setState(() {
        _gi--;
        _si = 0;
      });
      _start();
    } else {
      _start();
    }
  }

  void _togglePause() {
    HapticFeedback.selectionClick();
    if (_player.playing.value) {
      _player.pause();
      setState(() => _paused = true);
    } else {
      _player.resume();
      setState(() => _paused = false);
    }
  }

  Future<void> _toggleLike() async {
    final id = _story['id'] as String;
    final had = _liked[id] ?? false;
    HapticFeedback.selectionClick();
    setState(() => _liked[id] = !had);
    try {
      if (had) {
        await _c.from('likes').delete().eq('voice_id', id).eq('user_id', _me);
      } else {
        await _c.from('likes').insert({'voice_id': id, 'user_id': _me});
      }
    } catch (_) {
      if (mounted) setState(() => _liked[id] = had);
    }
  }

  Future<void> _sendReply(String path, int ms) async {
    final story = _story;
    final owner = story['user_id'] as String;
    try {
      final cid = await _c
          .rpc('get_or_create_conversation', params: {'other': owner}) as String;
      final sp = '$_me/chat/${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _c.storage.from('voices').upload(sp, File(path),
          fileOptions: const FileOptions(contentType: 'audio/mp4'));
      final row = {
        'conversation_id': cid,
        'sender_id': _me,
        'audio_path': sp,
        'duration_ms': ms,
      };
      try {
        await _c.from('messages').insert({...row, 'story_id': story['id']});
      } catch (_) {
        // update3.sql not run yet: still send the voice, without the story card.
        await _c.from('messages').insert(row);
      }
      try {
        await File(path).delete();
      } catch (_) {}
      // Let the other person's chat list know.
      try {
        final ch = _c.channel('inbox:$owner');
        ch.subscribe();
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await ch.sendBroadcastMessage(event: 'ping', payload: {'user': _me});
        _c.removeChannel(ch);
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Reply sent')));
      _start();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send your reply')));
    }
  }

  Future<void> _deleteStory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this story?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _player.stop();
      await _c.from('voices').delete().eq('id', _story['id'] as String);
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {}
  }

  // ---------- widgets ----------

  Widget _segments() {
    final cs = Theme.of(context).colorScheme;
    final n = _group.stories.length;
    return Row(
      children: [
        for (var i = 0; i < n; i++)
          Expanded(
            child: Container(
              height: 3,
              margin: EdgeInsets.only(right: i == n - 1 ? 0 : 4),
              decoration: BoxDecoration(
                color: cs.onSurface.withAlpha(60),
                borderRadius: BorderRadius.circular(2),
              ),
              child: i < _si
                  ? Container(
                      decoration: BoxDecoration(
                        color: cs.onSurface,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    )
                  : i == _si
                      ? ValueListenableBuilder<double>(
                          valueListenable: _player.progress,
                          builder: (context, p, _) => FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: p.clamp(0.0, 1.0).toDouble(),
                            child: Container(
                              decoration: BoxDecoration(
                                color: cs.onSurface,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        )
                      : null,
            ),
          ),
      ],
    );
  }

  Widget _header() {
    final cs = Theme.of(context).colorScheme;
    final when = DateTime.tryParse(_story['created_at'] as String? ?? '');
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: cs.onSurface, width: 2),
          ),
          child: Avatar(name: _group.name, path: _group.avatarPath, size: 36),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_group.isMe ? 'Your story' : _group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              Text(when != null ? timeAgo(when) : '',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurface.withAlpha(150))),
            ],
          ),
        ),
        Text(moodOf(_story['mood'] as String).emoji,
            style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 8),
        if (_group.isMe)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (a) {
              if (a == 'delete') _deleteStory();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete story')),
            ],
          ),
        GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: GlassBox(
            radius: 20,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.close_rounded, size: 22),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bigWave() {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final id = _story['id'] as String;
    final seed = (id.hashCode.abs() % 20 + 1).toDouble();
    const n = 28;
    return SizedBox(
      height: 150,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: Listenable.merge([_player.progress, _player.playing]),
        builder: (context, _) {
          final playing = _player.playing.value;
          final p = _player.progress.value;
          final hs = <double>[];
          for (var i = 0; i < n; i++) {
            final v = 0.45 * sin(i * 0.5 + seed).abs() +
                0.55 * sin(i * 1.3 + seed * 2.1).abs();
            final k = playing ? 0.85 + 0.15 * sin(p * 160 + i * 0.8) : 0.8;
            hs.add(((14 + 126 * v) * k).clamp(14.0, 140.0).toDouble());
          }
          return CustomPaint(
            size: Size.infinite,
            painter: FixedBarsPainter(
              heights: hs,
              progress: p,
              on: cs.onSurface,
              off: dark
                  ? const Color.fromRGBO(255, 255, 255, .3)
                  : const Color.fromRGBO(0, 0, 0, .2),
              barW: 5,
              gap: 5,
            ),
          );
        },
      ),
    );
  }

  Widget _scrubber() {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final id = _story['id'] as String;
    final bars = barsFor(id, n: 56);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      void seek(double dx) => _player.seekFraction((dx / w).clamp(0.0, 1.0).toDouble());
      return Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => seek(d.localPosition.dx),
            onHorizontalDragStart: (d) {
              _player.pause();
              seek(d.localPosition.dx);
            },
            onHorizontalDragUpdate: (d) => seek(d.localPosition.dx),
            onHorizontalDragEnd: (_) {
              if (!_paused) _player.resume();
            },
            child: SizedBox(
              height: 48,
              width: double.infinity,
              child: ValueListenableBuilder<double>(
                valueListenable: _player.progress,
                builder: (context, p, _) => CustomPaint(
                  size: Size.infinite,
                  painter: FixedBarsPainter(
                    heights: [for (final b in bars) 8 + 40 * b],
                    progress: p,
                    on: cs.onSurface,
                    off: dark
                        ? const Color.fromRGBO(255, 255, 255, .25)
                        : const Color.fromRGBO(0, 0, 0, .18),
                    barW: 3,
                    gap: (w - 56 * 3) / 55,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<Duration>(
            valueListenable: _player.position,
            builder: (context, pos, _) {
              final total = (_story['duration_ms'] as int?) ?? 0;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(fmtDuration(pos.inMilliseconds),
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurface.withAlpha(150))),
                  Text(fmtDuration(total),
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurface.withAlpha(150))),
                ],
              );
            },
          ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final caption = (_story['caption'] as String?) ?? '';
    final id = _story['id'] as String;
    final liked = _liked[id] ?? false;
    final expires = DateTime.tryParse(_story['expires_at'] as String? ?? '');
    final left = expires == null
        ? ''
        : '${max(0, expires.difference(DateTime.now()).inHours)}h left';

    return Scaffold(
      body: Stack(
        children: [
          // tap zones: left = back, middle = pause, right = next
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                      behavior: HitTestBehavior.opaque, onTap: _prev),
                ),
                Expanded(
                  flex: 4,
                  child: GestureDetector(
                      behavior: HitTestBehavior.opaque, onTap: _togglePause),
                ),
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                      behavior: HitTestBehavior.opaque, onTap: _next),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Column(
                children: [
                  _segments(),
                  const SizedBox(height: 14),
                  _header(),
                  Expanded(
                    child: IgnorePointer(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _bigWave(),
                            const SizedBox(height: 30),
                            if (caption.isNotEmpty)
                              Text(caption,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500,
                                      height: 1.4)),
                            const SizedBox(height: 18),
                            AnimatedOpacity(
                              opacity: _paused ? 1 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: GlassBox(
                                blur: false,
                                radius: 16,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                child: Text('Paused',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: cs.onSurface.withAlpha(170))),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _scrubber(),
                  const SizedBox(height: 16),
                  if (_group.isMe)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text('Your story · $left',
                          style: TextStyle(
                              color: cs.onSurface.withAlpha(150))),
                    )
                  else
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _toggleLike,
                          child: GlassBox(
                            radius: 28,
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                transitionBuilder: (c, a) =>
                                    ScaleTransition(scale: a, child: c),
                                child: Icon(
                                  liked
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  key: ValueKey(liked),
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: HoldRecordButton(
                            label: 'Hold to reply with your voice',
                            onRecorded: _sendReply,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
