import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/common.dart';
import '../services/voice_player.dart';
import 'avatar.dart';
import 'glass.dart';
import 'hold_record_button.dart';
import 'waveform.dart';

/// Voice replies on a voice. Hidden until the person opens them.
Future<void> showCommentsSheet(
  BuildContext context, {
  required String voiceId,
  required String ownerId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CommentsSheet(voiceId: voiceId, ownerId: ownerId),
  ).whenComplete(() => VoicePlayer.instance.stop());
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.voiceId, required this.ownerId});
  final String voiceId;
  final String ownerId;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>>? _items;

  String get _me => _c.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _c
          .from('comments')
          .select(
              'id,user_id,audio_path,duration_ms,created_at,profiles(username,nickname,avatar_path)')
          .eq('voice_id', widget.voiceId)
          .order('created_at', ascending: true)
          .limit(100);
      if (mounted) setState(() => _items = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      if (mounted) setState(() => _items = _items ?? []);
    }
  }

  Future<void> _send(String path, int ms) async {
    try {
      final sp = '$_me/replies/${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _c.storage.from('voices').upload(sp, File(path),
          fileOptions: const FileOptions(contentType: 'audio/mp4'));
      await _c.from('comments').insert({
        'voice_id': widget.voiceId,
        'user_id': _me,
        'audio_path': sp,
        'duration_ms': ms,
      });
      try {
        await File(path).delete();
      } catch (_) {}
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send your reply')));
    }
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this reply?'),
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
      await VoicePlayer.instance.stop();
      await _c.from('comments').delete().eq('id', c['id'] as String);
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _items;
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: GlassBox(
        radius: 32,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.72),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Voice replies',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Flexible(
                child: items == null
                    ? const Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 30),
                            child: Center(
                              child: Text('No replies yet. Be the first.',
                                  style: TextStyle(
                                      color: cs.onSurface.withAlpha(160))),
                            ),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final c in items) _row(c),
                            ],
                          ),
              ),
              const SizedBox(height: 12),
              HoldRecordButton(
                label: 'Hold to reply with your voice',
                onRecorded: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> c) {
    final cs = Theme.of(context).colorScheme;
    final p = (c['profiles'] as Map?) ?? const {};
    final username = (p['username'] as String?) ?? '';
    final nick = (p['nickname'] as String?) ?? '';
    final when = DateTime.tryParse(c['created_at'] as String? ?? '');
    final canDelete = c['user_id'] == _me || widget.ownerId == _me;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: canDelete ? () => _delete(c) : null,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Avatar(
              name: nick.isNotEmpty ? nick : username,
              path: p['avatar_path'] as String?,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${nick.isNotEmpty ? nick : '@$username'}'
                    '${when != null ? '  ·  ${timeAgo(when)}' : ''}',
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurface.withAlpha(160)),
                  ),
                  VoiceWave(
                    id: 'c:${c['id']}',
                    audioPath: c['audio_path'] as String,
                    small: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
