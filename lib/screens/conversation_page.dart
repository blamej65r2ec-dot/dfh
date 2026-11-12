import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/common.dart';
import '../services/voice_player.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import '../widgets/report_sheet.dart';
import '../services/stories.dart';
import '../widgets/waveform.dart';
import 'story_viewer_page.dart';
import 'user_profile_page.dart';

/// A voice message that is still being uploaded.
class _Pending {
  _Pending({
    required this.path,
    required this.ms,
    required this.storagePath,
  });
  final String path;
  final int ms;
  final String storagePath;
  bool failed = false;
}

class ConversationPage extends StatefulWidget {
  const ConversationPage({
    super.key,
    required this.conversationId,
    required this.other,
  });

  final String conversationId;
  final Map<String, dynamic> other;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final _c = Supabase.instance.client;
  final _rec = AudioRecorder();
  final _watch = Stopwatch();

  // Recording UI state lives in notifiers so only the button rebuilds.
  final ValueNotifier<bool> _recording = ValueNotifier(false);
  final ValueNotifier<bool> _willCancel = ValueNotifier(false);
  final ValueNotifier<int> _elapsed = ValueNotifier(0);
  final ValueNotifier<List<double>> _levels =
      ValueNotifier(List<double>.filled(22, 0.1));

  Timer? _poll;
  Timer? _tick;
  Timer? _beat;
  Timer? _otherTimer;
  StreamSubscription<Amplitude>? _ampSub;
  RealtimeChannel? _ch;
  RealtimeChannel? _inbox;

  List<Map<String, dynamic>> _messages = [];
  final List<_Pending> _pending = [];
  final Set<String> _known = {};
  final Set<String> _animate = {};
  String _sig = '';
  bool _loading = true;
  bool _fetching = false;
  bool _fetchAgain = false;
  bool _firstDone = false;
  bool _marking = false;
  bool _otherRecording = false;
  bool _myReceipts = true;
  bool _otherReceipts = true;
  int _polls = 0;

  // press handling
  int _pressId = 0;
  bool _pressActive = false;
  double _downX = 0;
  String? _path;

  String get _me => _c.auth.currentUser!.id;
  String get _otherId => widget.other['id'] as String;

  @override
  void initState() {
    super.initState();
    _fetch();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _fetch());
    _ch = _c.channel('chat:${widget.conversationId}');
    _ch!
        .onBroadcast(
          event: 'recording',
          callback: (p) {
            final data = (p['payload'] is Map) ? p['payload'] as Map : p;
            if (data['user'] == _me) return;
            final on = data['on'] == true;
            _otherTimer?.cancel();
            if (mounted && on != _otherRecording) {
              setState(() => _otherRecording = on);
            }
            if (on) {
              // Safety net only: while they hold, a signal arrives every 2 s.
              _otherTimer = Timer(const Duration(seconds: 5), () {
                if (mounted) setState(() => _otherRecording = false);
              });
            }
          },
        )
        .onBroadcast(
          event: 'msg',
          callback: (p) {
            final data = (p['payload'] is Map) ? p['payload'] as Map : p;
            if (data['user'] == _me) return;
            _fetch();
          },
        )
        .subscribe();
    _inbox = _c.channel('inbox:$_otherId')..subscribe();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _beat?.cancel();
    _otherTimer?.cancel();
    _ampSub?.cancel();
    if (_recording.value) _broadcast(false);
    final ch = _ch;
    if (ch != null) _c.removeChannel(ch);
    final ib = _inbox;
    if (ib != null) _c.removeChannel(ib);
    _rec.dispose();
    VoicePlayer.instance.stop();
    _recording.dispose();
    _willCancel.dispose();
    _elapsed.dispose();
    _levels.dispose();
    super.dispose();
  }

  // ---------- network ----------

  Future<void> _broadcast(bool on) async {
    try {
      await _ch?.sendBroadcastMessage(
        event: 'recording',
        payload: {'user': _me, 'on': on},
      );
    } catch (_) {}
  }

  Future<void> _notify() async {
    try {
      await _ch?.sendBroadcastMessage(event: 'msg', payload: {'user': _me});
    } catch (_) {}
    try {
      await _inbox?.sendBroadcastMessage(event: 'ping', payload: {'user': _me});
    } catch (_) {}
  }

  Future<void> _loadReceipts() async {
    try {
      final rows = await _c
          .from('profiles')
          .select('id,read_receipts')
          .inFilter('id', [_me, _otherId]).timeout(const Duration(seconds: 10));
      var mine = true;
      var theirs = true;
      for (final r in rows) {
        final v = (r['read_receipts'] as bool?) ?? true;
        if (r['id'] == _me) {
          mine = v;
        } else {
          theirs = v;
        }
      }
      if (mounted && (mine != _myReceipts || theirs != _otherReceipts)) {
        setState(() {
          _myReceipts = mine;
          _otherReceipts = theirs;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetch() async {
    // Never run two fetches at once. Ask for one more run instead.
    if (_fetching) {
      _fetchAgain = true;
      return;
    }
    _fetching = true;
    if (_polls++ % 3 == 0) _loadReceipts();
    try {
      List<dynamic> rows;
      try {
        rows = await _c
            .from('messages')
            .select(
                '*, story:voices!story_id(id,user_id,audio_path,caption,mood,duration_ms,created_at,expires_at)')
            .eq('conversation_id', widget.conversationId)
            .order('created_at', ascending: false)
            .limit(100)
            .timeout(const Duration(seconds: 12));
      } catch (_) {
        // update3.sql not run yet: load without story cards.
        rows = await _c
            .from('messages')
            .select()
            .eq('conversation_id', widget.conversationId)
            .order('created_at', ascending: false)
            .limit(100)
            .timeout(const Duration(seconds: 12));
      }
      final list = List<Map<String, dynamic>>.from(rows);
      final sig =
          list.map((m) => '${m['id']}${m['read_at']}${m['reaction']}').join();

      final hasUnread =
          list.any((m) => m['sender_id'] != _me && m['read_at'] == null);
      if (hasUnread && !_marking) {
        _marking = true;
        try {
          await _c
              .rpc('mark_read', params: {'conv': widget.conversationId})
              .timeout(const Duration(seconds: 10));
          _ch?.sendBroadcastMessage(event: 'msg', payload: {'user': _me});
        } catch (_) {}
        _marking = false;
      }

      if (!mounted) return;
      if (sig != _sig || _loading) {
        final ids = [for (final m in list) m['id'] as String];
        if (_firstDone) {
          for (final id in ids) {
            if (!_known.contains(id)) _animate.add(id);
          }
        }
        _known.addAll(ids);
        _firstDone = true;
        setState(() {
          _messages = list;
          _sig = sig;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && _loading) setState(() => _loading = false);
    }
    _fetching = false;
    if (_fetchAgain) {
      _fetchAgain = false;
      _fetch();
    }
  }

  // ---------- recording (starts the moment you touch the button) ----------

  void _onDown(PointerDownEvent e) {
    _downX = e.position.dx;
    _pressActive = true;
    _begin();
  }

  void _onMove(PointerMoveEvent e) {
    if (!_recording.value) return;
    final cancel = e.position.dx - _downX < -90;
    if (cancel != _willCancel.value) {
      _willCancel.value = cancel;
      if (cancel) HapticFeedback.selectionClick();
    }
  }

  void _onUp(PointerEvent e) {
    _pressActive = false;
    if (_recording.value) _finish();
  }

  Future<void> _begin() async {
    if (_recording.value) return;
    final id = ++_pressId;
    try {
      if (!await _rec.hasPermission()) {
        _pressActive = false;
        _snack('Microphone permission is needed to record.');
        return;
      }
      if (!_pressActive || id != _pressId || !mounted) return;
      await VoicePlayer.instance.stop();
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/chat_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: path,
      );
      if (!mounted) return;
      _path = path;
      HapticFeedback.mediumImpact();
      _watch
        ..reset()
        ..start();
      _elapsed.value = 0;
      _levels.value = List<double>.filled(22, 0.1);
      _willCancel.value = false;
      _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _elapsed.value = _watch.elapsedMilliseconds;
      });
      _ampSub = _rec
          .onAmplitudeChanged(const Duration(milliseconds: 90))
          .listen((a) {
        final v = ((a.current + 50) / 50).clamp(0.1, 1.0).toDouble();
        final next = List<double>.of(_levels.value)
          ..removeAt(0)
          ..add(v);
        _levels.value = next;
      });
      _recording.value = true;
      _broadcast(true);
      _beat = Timer.periodic(
          const Duration(seconds: 2), (_) => _broadcast(true));
      // Finger already lifted while we were starting.
      if (!_pressActive) _finish();
    } catch (_) {
      _recording.value = false;
    }
  }

  Future<void> _finish() async {
    if (!_recording.value) return;
    _recording.value = false;
    _tick?.cancel();
    _beat?.cancel();
    await _ampSub?.cancel();
    _broadcast(false);
    _watch.stop();
    final ms = _watch.elapsedMilliseconds;
    final cancel = _willCancel.value;
    _willCancel.value = false;
    String? p;
    try {
      p = await _rec.stop();
    } catch (_) {}
    p ??= _path;
    if (p == null) return;
    if (cancel || ms < 700) {
      try {
        await File(p).delete();
      } catch (_) {}
      if (!cancel) _snack('Hold to record');
      return;
    }
    HapticFeedback.lightImpact();
    _enqueue(p, ms);
  }

  // ---------- sending (with an animated pending bubble) ----------

  void _enqueue(String path, int ms) {
    final pend = _Pending(
      path: path,
      ms: ms,
      storagePath: '$_me/chat/${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    setState(() => _pending.add(pend));
    _upload(pend);
  }

  Future<void> _upload(_Pending p) async {
    if (mounted) setState(() => p.failed = false);
    try {
      await _c.storage
          .from('voices')
          .upload(
            p.storagePath,
            File(p.path),
            fileOptions:
                const FileOptions(contentType: 'audio/mp4', upsert: true),
          )
          .timeout(const Duration(seconds: 60));
      final row = await _c
          .from('messages')
          .insert({
            'conversation_id': widget.conversationId,
            'sender_id': _me,
            'audio_path': p.storagePath,
            'duration_ms': p.ms,
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 15));
      // Mark as known so the real bubble replaces the pending one in place.
      _known.add(row['id'] as String);
      try {
        await File(p.path).delete();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _pending.remove(p));
      _notify();
      _fetch();
    } catch (_) {
      if (mounted) setState(() => p.failed = true);
    }
  }

  // ---------- message actions ----------

  Future<void> _messageActions(Map<String, dynamic> m) async {
    final mine = m['sender_id'] == _me;
    final current = m['reaction'] as String?;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(12),
        child: GlassBox(
          radius: 32,
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final mood in moods)
                      GestureDetector(
                        onTap: () => Navigator.of(ctx)
                            .pop(current == mood.emoji ? 'react:' : 'react:${mood.emoji}'),
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: current == mood.emoji
                                ? Theme.of(ctx).colorScheme.primary.withAlpha(60)
                                : Colors.transparent,
                          ),
                          child: Text(mood.emoji,
                              style: const TextStyle(fontSize: 24)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(mine
                    ? Icons.delete_outline_rounded
                    : Icons.flag_outlined),
                title: Text(mine ? 'Delete message' : 'Report message'),
                onTap: () => Navigator.of(ctx).pop(mine ? 'delete' : 'report'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action.startsWith('react:')) {
      final emoji = action.substring(6);
      try {
        await _c.rpc('react_message',
            params: {'msg': m['id'], 'emoji': emoji}).timeout(
            const Duration(seconds: 10));
        _notify();
        _fetch();
      } catch (_) {
        _snack('Could not react. Run update2.sql in Supabase first.');
      }
    } else if (action == 'report') {
      showReportSheet(context, type: 'message', id: m['id'] as String);
    } else if (action == 'delete') {
      await VoicePlayer.instance.stop();
      try {
        await _c.from('messages').delete().eq('id', m['id'] as String);
        try {
          await _c.storage.from('voices').remove([m['audio_path'] as String]);
        } catch (_) {}
        _notify();
        _fetch();
      } catch (_) {
        _snack('Could not delete that message');
      }
    }
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t)));
  }

  // ---------- widgets ----------

  Widget _header() {
    final cs = Theme.of(context).colorScheme;
    final o = widget.other;
    final username = (o['username'] as String?) ?? '';
    final nick = (o['nickname'] as String?) ?? '';
    final name = nick.isNotEmpty ? nick : '@$username';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 16, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.chevron_left_rounded, size: 32),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => UserProfilePage(userId: _otherId),
            )),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: cs.primary, width: 2),
              ),
              child: Avatar(
                name: nick.isNotEmpty ? nick : username,
                path: o['avatar_path'] as String?,
                size: 40,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => UserProfilePage(userId: _otherId),
              )),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  if (nick.isNotEmpty)
                    Text('@$username',
                        style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withAlpha(150))),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _snack('Calls are coming soon'),
            child: GlassBox(
              radius: 23,
              child: const SizedBox(
                width: 46,
                height: 46,
                child: Icon(Icons.call_outlined, size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateChip(DateTime t) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: GlassBox(
          blur: false,
          radius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          child: Text(dayLabel(t),
              style: TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(150))),
        ),
      ),
    );
  }

  Widget _reactionBadge(String emoji) {
    return GlassBox(
      blur: false,
      radius: 15,
      child: SizedBox(
        width: 30,
        height: 30,
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 16))),
      ),
    );
  }

  Widget _bubbleShell({
    required bool mine,
    required Widget content,
    required String caption,
    String? reaction,
    VoidCallback? onTap,
    VoidCallback? onLong,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: onTap,
                  onLongPress: onLong,
                  child: SizedBox(
                    width: 250,
                    child: GlassBox(
                      blur: false,
                      radius: 26,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      child: content,
                    ),
                  ),
                ),
                if (reaction != null && reaction.isNotEmpty)
                  Positioned(
                    left: mine ? -6 : null,
                    right: mine ? null : -6,
                    top: -8,
                    child: _reactionBadge(reaction),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Text(caption,
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurface.withAlpha(150))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _storyCard(Map<String, dynamic> m) {
    final cs = Theme.of(context).colorScheme;
    final mine = m['sender_id'] == _me;
    final story = m['story'] as Map<String, dynamic>?;
    final o = widget.other;
    final nick = (o['nickname'] as String?) ?? '';
    final otherName = nick.isNotEmpty ? nick : '@${o['username'] ?? ''}';
    final label = mine
        ? 'You replied to $otherName\'s voice story'
        : '$otherName replied to your voice story';
    final exp = story == null
        ? null
        : DateTime.tryParse(story['expires_at'] as String? ?? '');
    final live = story != null && exp != null && exp.isAfter(DateTime.now());
    String sub;
    if (!live) {
      sub = 'Story ended';
    } else {
      final left = exp.difference(DateTime.now());
      sub = left.inHours >= 1
          ? 'Expires in ${left.inHours}h · tap to open'
          : 'Expires in ${max(1, left.inMinutes)}m · tap to open';
    }
    final emoji = story == null ? '🎙️' : moodOf(story['mood'] as String).emoji;
    final dur = story == null ? '' : ' · ${fmtDuration(story['duration_ms'] as int)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Text(label,
                style:
                    TextStyle(fontSize: 12, color: cs.onSurface.withAlpha(150))),
          ),
          GestureDetector(
            onTap: live ? () => _openStory(story) : null,
            child: SizedBox(
              width: 250,
              child: GlassBox(
                blur: false,
                radius: 22,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Opacity(
                  opacity: live ? 1 : 0.55,
                  child: Row(
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 26)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Voice story$dur',
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                            Text(sub,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface.withAlpha(150))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openStory(Map<String, dynamic>? story) {
    if (story == null) return;
    final o = widget.other;
    final ownerIsMe = story['user_id'] == _me;
    final nick = (o['nickname'] as String?) ?? '';
    final username = (o['username'] as String?) ?? '';
    final group = StoryGroup(
      userId: story['user_id'] as String,
      name: ownerIsMe ? 'You' : (nick.isNotEmpty ? nick : username),
      username: ownerIsMe ? '' : username,
      avatarPath: ownerIsMe ? null : o['avatar_path'] as String?,
      stories: [Map<String, dynamic>.from(story)],
      isMe: ownerIsMe,
      unseen: true,
    );
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StoryViewerPage(groups: [group]),
    ));
  }

  Widget _messageItem(Map<String, dynamic> m, {required bool showHeard}) {
    final id = m['id'] as String;
    final path = m['audio_path'] as String;
    final mine = m['sender_id'] == _me;
    final when = DateTime.tryParse(m['created_at'] as String? ?? '');
    final caption = [
      if (when != null) fmtClock(when),
      if (showHeard) 'Heard',
    ].join(' · ');

    final bubble = _bubbleShell(
      mine: mine,
      caption: caption,
      reaction: m['reaction'] as String?,
      onLong: () => _messageActions(m),
      content: RepaintBoundary(
        child: VoiceWave(id: 'm:$id', audioPath: path, small: true),
      ),
    );

    final hasStory = m['story_id'] != null;
    final body = hasStory
        ? Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [_storyCard(m), bubble],
          )
        : bubble;

    return KeyedSubtree(
      key: ValueKey(id),
      child: _animate.contains(id) ? _PopIn(child: body) : body,
    );
  }

  Widget _pendingItem(_Pending p) {
    final cs = Theme.of(context).colorScheme;
    final bars = barsFor(p.storagePath, n: 26);
    return KeyedSubtree(
      key: ValueKey(p.storagePath),
      child: _PopIn(
        child: _bubbleShell(
          mine: true,
          caption: p.failed ? 'Could not send · tap to retry' : 'Sending...',
          onTap: p.failed ? () => _upload(p) : null,
          content: Row(
            children: [
              Expanded(
                child: p.failed
                    ? SizedBox(
                        height: 38,
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: WaveformPainter(
                            bars: bars,
                            progress: 0,
                            color: cs.error,
                          ),
                        ),
                      )
                    : _SendingWave(bars: bars, color: cs.onSurface),
              ),
              const SizedBox(width: 12),
              Text(fmtDuration(p.ms),
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurface.withAlpha(150))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recordingPill() {
    final cs = Theme.of(context).colorScheme;
    final o = widget.other;
    final nick = (o['nickname'] as String?) ?? '';
    final name = nick.isNotEmpty ? nick : '@${o['username'] ?? ''}';
    return KeyedSubtree(
      key: const ValueKey('other-recording'),
      child: _PopIn(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: GlassBox(
              blur: false,
              radius: 22,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PulseBars(color: cs.onSurface),
                  const SizedBox(width: 10),
                  Text('$name is recording',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurface.withAlpha(150))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _holdButton() {
    final cs = Theme.of(context).colorScheme;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: ValueListenableBuilder<bool>(
        valueListenable: _recording,
        builder: (context, rec, _) => ValueListenableBuilder<bool>(
          valueListenable: _willCancel,
          builder: (context, cancel, _) {
            final bg = cancel ? cs.error : cs.primary;
            final fg = cancel ? cs.onError : cs.onPrimary;
            return Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                height: 58,
                width: rec ? double.infinity : 230,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(29),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, .35),
                      blurRadius: 22,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: rec
                      ? _recordingContent(cancel, fg)
                      : Row(
                          key: const ValueKey('idle'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.mic_none_rounded, color: fg, size: 24),
                            const SizedBox(width: 10),
                            Text('Hold to record',
                                style: TextStyle(
                                    color: fg,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _recordingContent(bool cancel, Color fg) {
    return Row(
      key: const ValueKey('rec'),
      children: [
        ValueListenableBuilder<int>(
          valueListenable: _elapsed,
          builder: (context, ms, _) => Text(
            fmtDuration(ms),
            style: TextStyle(
                color: fg, fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: cancel
              ? Text('Release to cancel',
                  style: TextStyle(color: fg, fontWeight: FontWeight.w700))
              : ValueListenableBuilder<List<double>>(
                  valueListenable: _levels,
                  builder: (context, lv, _) => SizedBox(
                    height: 30,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: WaveformPainter(
                          bars: lv, progress: 1, color: fg),
                    ),
                  ),
                ),
        ),
        if (!cancel) ...[
          const SizedBox(width: 12),
          Icon(Icons.chevron_left_rounded, color: fg.withAlpha(170), size: 20),
          Text('Cancel',
              style: TextStyle(color: fg.withAlpha(170), fontSize: 12)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String? lastMineId;
    for (final m in _messages) {
      if (m['sender_id'] == _me) {
        lastMineId = m['id'] as String;
        break;
      }
    }

    final items = <Widget>[];
    if (_otherRecording) items.add(_recordingPill());
    for (final p in _pending.reversed) {
      items.add(_pendingItem(p));
    }
    for (var i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final mine = m['sender_id'] == _me;
      items.add(_messageItem(
        m,
        showHeard: mine &&
            _myReceipts &&
            _otherReceipts &&
            m['id'] == lastMineId &&
            m['read_at'] != null,
      ));
      final t = DateTime.tryParse(m['created_at'] as String? ?? '');
      if (t != null) {
        final older = i + 1 < _messages.length
            ? DateTime.tryParse(_messages[i + 1]['created_at'] as String? ?? '')
            : null;
        final a = t.toLocal();
        final b = older?.toLocal();
        final sameDay =
            b != null && a.year == b.year && a.month == b.month && a.day == b.day;
        if (!sameDay) items.add(_dateChip(t));
      }
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? Center(
                          child: Text('Say hi. Hold the button to send a voice.',
                              style: TextStyle(
                                  color: cs.onSurface.withAlpha(170))))
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          itemCount: items.length,
                          itemBuilder: (context, i) => items[i],
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: _holdButton(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slide up + fade + scale, once, when an item first appears.
class _PopIn extends StatelessWidget {
  const _PopIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
      builder: (context, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 18),
          child: Transform.scale(scale: 0.94 + 0.06 * t, child: c),
        ),
      ),
      child: child,
    );
  }
}

/// While a voice is uploading: the wave fills again and again.
class _SendingWave extends StatefulWidget {
  const _SendingWave({required this.bars, required this.color});
  final List<double> bars;
  final Color color;

  @override
  State<_SendingWave> createState() => _SendingWaveState();
}

class _SendingWaveState extends State<_SendingWave>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _a,
        builder: (context, _) => SizedBox(
          height: 38,
          child: CustomPaint(
            size: Size.infinite,
            painter: WaveformPainter(
              bars: widget.bars,
              progress: Curves.easeInOut.transform(_a.value),
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Three bars that pulse, like in the design.
class _PulseBars extends StatefulWidget {
  const _PulseBars({required this.color});
  final Color color;

  @override
  State<_PulseBars> createState() => _PulseBarsState();
}

class _PulseBarsState extends State<_PulseBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: AnimatedBuilder(
        animation: _a,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 4,
                height: 20 *
                    (0.35 +
                        0.65 *
                            (0.5 +
                                0.5 *
                                    Curves.easeInOut.transform(
                                        ((_a.value + i * 0.2) % 1.0 < 0.5)
                                            ? ((_a.value + i * 0.2) % 1.0) * 2
                                            : 2 -
                                                ((_a.value + i * 0.2) % 1.0) *
                                                    2))),
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
