import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/follows.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import 'conversation_page.dart';

/// Starts a chat with someone you follow, or anyone you search for.
Future<void> openChatWith(BuildContext context, Map<String, dynamic> person,
    {bool replace = false}) async {
  final c = Supabase.instance.client;
  try {
    final cid = await c
        .rpc('get_or_create_conversation', params: {'other': person['id']});
    if (!context.mounted) return;
    final route = MaterialPageRoute<void>(
      builder: (_) => ConversationPage(
        conversationId: cid as String,
        other: person,
      ),
    );
    if (replace) {
      await Navigator.of(context).pushReplacement(route);
    } else {
      await Navigator.of(context).push(route);
    }
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot message this account.')));
  }
}

class NewChatPage extends StatefulWidget {
  const NewChatPage({super.key});

  @override
  State<NewChatPage> createState() => _NewChatPageState();
}

class _NewChatPageState extends State<NewChatPage> {
  final _c = Supabase.instance.client;
  final _text = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _following = [];
  List<Map<String, dynamic>> _results = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  String get _q => _text.text
      .replaceAll(RegExp(r'[,()%*\\]'), ' ')
      .replaceFirst(RegExp(r'^\s*@'), '')
      .trim();

  Future<void> _loadFollowing() async {
    try {
      final ids = (await Follows.mine()).toList();
      if (ids.isNotEmpty) {
        final ps = await _c
            .from('profiles')
            .select('id,username,nickname,avatar_path')
            .inFilter('id', ids);
        _following = List<Map<String, dynamic>>.from(ps);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final q = _q;
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    try {
      final rows = await _c
          .from('profiles')
          .select('id,username,nickname,avatar_path')
          .or('username.ilike.%$q%,nickname.ilike.%$q%')
          .neq('id', _c.auth.currentUser!.id)
          .limit(30);
      if (mounted) {
        setState(() => _results = List<Map<String, dynamic>>.from(rows));
      }
    } catch (_) {}
  }

  Widget _row(Map<String, dynamic> p) {
    final cs = Theme.of(context).colorScheme;
    final username = (p['username'] as String?) ?? '';
    final nick = (p['nickname'] as String?) ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openChatWith(context, p, replace: true),
        child: GlassBox(
          radius: 28,
          padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
          child: Row(
            children: [
              Avatar(
                  name: nick.isNotEmpty ? nick : username,
                  path: p['avatar_path'] as String?,
                  size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nick.isNotEmpty ? nick : '@$username',
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
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final searching = _q.isNotEmpty;
    final list = searching ? _results : _following;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        foregroundColor: cs.onSurface,
        title: const Text('New chat',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
        children: [
          TextField(
            controller: _text,
            onChanged: _changed,
            decoration: const InputDecoration(
              hintText: 'Search by username or nickname',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 18),
          if (!searching)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('People you follow',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Text(searching
                    ? 'No one found.'
                    : 'You are not following anyone yet. Search above.'),
              ),
            )
          else
            for (final p in list) _row(p),
        ],
      ),
    );
  }
}
