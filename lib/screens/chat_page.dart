import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/common.dart';
import '../widgets/animations.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import 'conversation_page.dart';
import 'new_chat_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>> _convs = [];
  Map<String, Map<String, dynamic>> _people = {};
  Set<String> _unread = {};
  bool _loading = true;
  String? _error;
  Timer? _poll;
  RealtimeChannel? _inbox;

  String get _me => _c.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load());
    _inbox = _c.channel('inbox:$_me')
      ..onBroadcast(event: 'ping', callback: (_) => _load())
      ..subscribe();
  }

  @override
  void dispose() {
    _poll?.cancel();
    final ib = _inbox;
    if (ib != null) _c.removeChannel(ib);
    super.dispose();
  }

  String _otherId(Map<String, dynamic> c) =>
      (c['user_a'] == _me ? c['user_b'] : c['user_a']) as String;

  Future<void> _load() async {
    try {
      final rows = await _c
          .from('conversations')
          .select()
          .or('user_a.eq.$_me,user_b.eq.$_me')
          .order('last_message_at', ascending: false)
          .limit(100);
      final convs = List<Map<String, dynamic>>.from(rows);
      final others = {for (final c in convs) _otherId(c)}.toList();
      final convIds = [for (final c in convs) c['id'] as String];
      var people = <String, Map<String, dynamic>>{};
      var unread = <String>{};
      if (others.isNotEmpty) {
        final ps = await _c
            .from('profiles')
            .select('id,username,nickname,avatar_path')
            .inFilter('id', others);
        people = {
          for (final p in ps) p['id'] as String: Map<String, dynamic>.from(p)
        };
        try {
          final un = await _c
              .from('messages')
              .select('conversation_id')
              .inFilter('conversation_id', convIds)
              .neq('sender_id', _me)
              .isFilter('read_at', null);
          unread = {for (final r in un) r['conversation_id'] as String};
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _convs = convs;
        _people = people;
        _unread = unread;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your chats.';
      });
    }
  }

  Future<void> _open(Map<String, dynamic> conv) async {
    final other = _people[_otherId(conv)];
    if (other == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          ConversationPage(conversationId: conv['id'] as String, other: other),
    ));
    _load();
  }

  Widget _tile(Map<String, dynamic> conv, int i) {
    final cs = Theme.of(context).colorScheme;
    final p = _people[_otherId(conv)];
    if (p == null) return const SizedBox.shrink();
    final username = (p['username'] as String?) ?? '';
    final nick = (p['nickname'] as String?) ?? '';
    final name = nick.isNotEmpty ? nick : '@$username';
    final unread = _unread.contains(conv['id']);
    final lastMs = conv['last_duration_ms'] as int?;
    final mine = conv['last_sender_id'] == _me;
    final when = DateTime.tryParse(conv['last_message_at'] as String? ?? '');
    final preview = lastMs == null
        ? 'No messages yet'
        : '${mine ? 'You: ' : ''}🎙️ ${fmtDuration(lastMs)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FadeSlideIn(
        delay: Duration(milliseconds: (i < 8 ? i : 8) * 50),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _open(conv),
          child: GlassBox(
            radius: 28,
            padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
            child: Row(
              children: [
                Avatar(
                    name: nick.isNotEmpty ? nick : username,
                    path: p['avatar_path'] as String?,
                    size: 50),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  unread ? FontWeight.w800 : FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(preview,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w400,
                              color: cs.onSurface
                                  .withAlpha(unread ? 230 : 150))),
                    ],
                  ),
                ),
                if (when != null)
                  Text(timeAgo(when),
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurface.withAlpha(140))),
                if (unread)
                  Container(
                    margin: const EdgeInsets.only(left: 10),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, color: cs.primary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, pageBottomPad(context)),
          children: [
            FadeSlideIn(
              child: Row(
                children: [
                  Expanded(
                    child: Text('Chat',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: 'New chat',
                    icon: const Icon(Icons.add_comment_outlined, size: 26),
                    onPressed: () async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const NewChatPage()));
                      _load();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Center(
                  child: Column(
                    children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      const Text(
                        'If this is your first time, run chat.sql in Supabase.',
                        style: TextStyle(fontSize: 12),
                      ),
                      TextButton(onPressed: _load, child: const Text('Try again')),
                    ],
                  ),
                ),
              )
            else if (_convs.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(
                  child: Text('No chats yet. Tap + to start one.',
                      textAlign: TextAlign.center),
                ),
              )
            else
              for (var i = 0; i < _convs.length; i++) _tile(_convs[i], i),
          ],
        ),
      ),
    );
  }
}
