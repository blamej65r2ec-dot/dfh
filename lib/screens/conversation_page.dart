import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
import '../widgets/waveform.dart';
import 'user_profile_page.dart';

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
  Timer? _poll;
  Timer? _tick;
  List<Map<String, dynamic>> _messages = [];
  String _sig = '';
  bool _loading = true;
  bool _recording = false;
  bool _willCancel = false;
  bool _sending = false;
  String? _path;
  RealtimeChannel? _ch;
  RealtimeChannel? _inbox;
  Timer? _beat;
  Timer? _otherTimer;
  bool _otherRecording = false;
  bool _myReceipts = true;
  bool _otherReceipts = true;
  int _polls = 0;

  String get _me => _c.auth.currentUser!.id;

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
            if (mounted) setState(() => _otherRecording = on);
            if (on) {
              // Only a safety net if their connection drops: while they keep
              // holding, a signal arrives every 2 seconds.
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
    // Used to tell the other person's chat list that something changed.
    _inbox = _c.channel('inbox:${widget.other['id']}')..subscribe();
  }

  Future<void> _notify() async {
    try {
      await _ch?.sendBroadcastMessage(event: 'msg', payload: {'user': _me});
    } catch (_) {}
    try {
      await _inbox?.sendBroadcastMessage(event: 'ping', payload: {'user': _me});
    } catch (_) {}
  }

  Future<void> _broadcast(bool on) async {
    try {
      await _ch?.sendBroadcastMessage(
        event: 'recording',
        payload: {'user': _me, 'on': on},
      );
    } catch (_) {}
  }

  Future<void> _loadReceipts() async {
    try {
      final rows = await _c
          .from('profiles')
          .select('id,read_receipts')
          .inFilter('id', [_me, widget.other['id'] as String]);
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

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _beat?.cancel();
    _otherTimer?.cancel();
    if (_recording) _broadcast(false);
    final ch = _ch;
    if (ch != null) _c.removeChannel(ch);
    final ib = _inbox;
    if (ib != null) _c.removeChannel(ib);
    _rec.dispose();
    VoicePlayer.instance.stop();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (_polls++ % 3 == 0) _loadReceipts();
    try {
      final rows = await _c
          .from('messages')
          .select()
          .eq('conversation_id', widget.conversationId)
          .order('created_at', ascending: false)
          .limit(100);
      final list = List<Map<String, dynamic>>.from(rows);
      final sig = list.map((m) => '${m['id']}${m['read_at']}').join();
      final hasUnread =
          list.any((m) => m['sender_id'] != _me && m['read_at'] == null);
      if (hasUnread) {
        try {
          await _c.rpc('mark_read', params: {'conv': widget.conversationId});
          _ch?.sendBroadcastMessage(event: 'msg', payload: {'user': _me});
        } catch (_) {}
      }
      if (!mounted) return;
      if (sig != _sig || _loading) {
        setState(() {
          _messages = list;
          _sig = sig;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _startRecording() async {
    if (_sending || _recording) return;
    if (!await _rec.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Microphone permission is needed to record.')));
      return;
    }
    await VoicePlayer.instance.stop();
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/chat_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
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
    setState(() {
      _recording = true;
      _willCancel = false;
      _path = path;
    });
    _broadcast(true);
    _beat = Timer.periodic(const Duration(seconds: 2), (_) => _broadcast(true));
  }

  Future<void> _finishRecording() async {
    if (!_recording) return;
    _tick?.cancel();
    _beat?.cancel();
    _broadcast(false);
    _watch.stop();
    final ms = _watch.elapsedMilliseconds;
    final cancel = _willCancel;
    final stopped = await _rec.stop();
    final path = stopped ?? _path;
    setState(() {
      _recording = false;
      _willCancel = false;
    });
    if (path == null) return;
    if (cancel || ms < 700) {
      try {
        await File(path).delete();
      } catch (_) {}
      if (!cancel && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Hold to record')));
      }
      return;
    }
    HapticFeedback.lightImpact();
    await _send(path, ms);
  }

  Future<void> _send(String path, int ms) async {
    setState(() => _sending = true);
    try {
      final storagePath =
          '$_me/chat/${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _c.storage.from('voices').upload(
            storagePath,
            File(path),
            fileOptions: const FileOptions(contentType: 'audio/mp4'),
          );
      await _c.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _me,
        'audio_path': storagePath,
        'duration_ms': ms,
      });
      try {
        await File(path).delete();
      } catch (_) {}
      _notify();
      await _fetch();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not send. Try again.')));
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _messageActions(Map<String, dynamic> m) async {
    final mine = m['sender_id'] == _me;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(12),
        child: GlassBox(
          radius: 32,
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
    if (action == 'report') {
      showReportSheet(context, type: 'message', id: m['id'] as String);
    } else {
      await VoicePlayer.instance.stop();
      try {
        await _c.from('messages').delete().eq('id', m['id'] as String);
        try {
          await _c.storage.from('voices').remove([m['audio_path'] as String]);
        } catch (_) {}
        _notify();
        await _fetch();
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not delete that message')));
      }
    }
  }

  Widget _bubble(Map<String, dynamic> m, {required bool showSeen}) {
    final cs = Theme.of(context).colorScheme;
    final mine = m['sender_id'] == _me;
    final id = m['id'] as String;
    final player = VoicePlayer.instance;
    final bars = barsFor(id, n: 26);
    final fg = mine ? cs.onPrimary : cs.onSurface;
    final when = DateTime.tryParse(m['created_at'] as String? ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              player.toggle(id, m['audio_path'] as String);
            },
            onLongPress: () => _messageActions(m),
            child: Container(
              width: 250,
              padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                color: mine ? cs.primary : cs.onSurface.withAlpha(28),
              ),
              child: Row(
                children: [
                  ValueListenableBuilder<String?>(
                    valueListenable: player.currentId,
                    builder: (context, cur, _) =>
                        ValueListenableBuilder<bool>(
                      valueListenable: player.playing,
                      builder: (context, playing, _) => Icon(
                        cur == id && playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: fg,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ValueListenableBuilder<String?>(
                      valueListenable: player.currentId,
                      builder: (context, cur, _) =>
                          ValueListenableBuilder<double>(
                        valueListenable: player.progress,
                        builder: (context, p, _) => SizedBox(
                          height: 32,
                          child: CustomPaint(
                            painter: WaveformPainter(
                              bars: bars,
                              progress: cur == id ? p : 0,
                              color: fg,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(fmtDuration(m['duration_ms'] as int),
                      style: TextStyle(fontSize: 13, color: fg)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 6, right: 6),
            child: Text(
              [
                if (when != null) timeAgo(when),
                if (showSeen) 'Seen',
              ].join(' · '),
              style:
                  TextStyle(fontSize: 11, color: cs.onSurface.withAlpha(130)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    final cs = Theme.of(context).colorScheme;
    final secs = fmtDuration(_watch.elapsedMilliseconds);
    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressMoveUpdate: (d) {
        final cancel = d.offsetFromOrigin.dx < -90;
        if (cancel != _willCancel) setState(() => _willCancel = cancel);
      },
      onLongPressEnd: (_) => _finishRecording(),
      onTap: () => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Hold to record'))),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(22, 10, 10, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          color: _recording
              ? (_willCancel ? cs.error : cs.primary)
              : cs.onSurface.withAlpha(28),
        ),
        child: Row(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _recording
                    ? Text(
                        _willCancel
                            ? 'Release to cancel'
                            : '$secs   ·   slide left to cancel',
                        key: ValueKey(_willCancel),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _willCancel ? cs.onError : cs.onPrimary),
                      )
                    : Text(
                        _sending ? 'Sending...' : 'Hold to record',
                        key: const ValueKey('idle'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            AnimatedScale(
              scale: _recording ? 1.15 : 1,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _recording ? cs.onPrimary : cs.primary,
                ),
                child: Icon(
                  Icons.mic_rounded,
                  color: _recording ? cs.primary : cs.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final o = widget.other;
    final username = (o['username'] as String?) ?? '';
    final nick = (o['nickname'] as String?) ?? '';
    final name = nick.isNotEmpty ? nick : '@$username';
    String? lastMineId;
    for (final m in _messages) {
      if (m['sender_id'] == _me) {
        lastMineId = m['id'] as String;
        break;
      }
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        foregroundColor: cs.onSurface,
        titleSpacing: 0,
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => UserProfilePage(userId: o['id'] as String),
          )),
          child: Row(
            children: [
              Avatar(
                  name: nick.isNotEmpty ? nick : username,
                  path: o['avatar_path'] as String?,
                  size: 36),
              const SizedBox(width: 10),
              Flexible(
                child: Text(name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? const Center(
                          child: Text('Say hi. Hold the mic to send a voice.'))
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) {
                            final m = _messages[i];
                            final mine = m['sender_id'] == _me;
                            return Align(
                              alignment: mine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: _bubble(
                                m,
                                showSeen: mine &&
                                    _myReceipts &&
                                    _otherReceipts &&
                                    m['id'] == lastMineId &&
                                    m['read_at'] != null,
                              ),
                            );
                          },
                        ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _otherRecording
                  ? Padding(
                      key: const ValueKey('rec'),
                      padding: const EdgeInsets.only(left: 20, bottom: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            color: cs.onSurface.withAlpha(24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.mic_rounded, size: 16),
                              const SizedBox(width: 6),
                              const Text('Recording',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              _Dots(color: cs.onSurface),
                            ],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('none')),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
              child: _composer(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatefulWidget {
  const _Dots({required this.color});
  final Color color;

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Opacity(
              opacity: 0.3 +
                  0.7 * ((math.sin(_a.value * 2 * math.pi - i * 0.9) + 1) / 2),
              child: Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: widget.color),
              ),
            ),
        ],
      ),
    );
  }
}
