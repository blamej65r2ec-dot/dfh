import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/common.dart';
import '../widgets/animations.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import 'user_profile_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = _c.auth.currentUser!.id;
      final mine = await _c
          .from('voices')
          .select('id,caption,mood')
          .eq('user_id', uid)
          .eq('kind', 'post')
          .order('created_at', ascending: false)
          .limit(200);
      final byId = {for (final v in mine) v['id'] as String: v};
      final out = <Map<String, dynamic>>[];
      if (byId.isNotEmpty) {
        final ids = byId.keys.toList();
        const cols =
            'created_at,user_id,voice_id,profiles(username,nickname,avatar_path)';
        final likes = await _c
            .from('likes')
            .select(cols)
            .inFilter('voice_id', ids)
            .neq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(40);
        final reps = await _c
            .from('reposts')
            .select(cols)
            .inFilter('voice_id', ids)
            .neq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(40);
        for (final l in likes) {
          out.add({...Map<String, dynamic>.from(l), 'kind': 'like'});
        }
        for (final r in reps) {
          out.add({...Map<String, dynamic>.from(r), 'kind': 'repost'});
        }
        out.sort((a, b) =>
            (b['created_at'] as String).compareTo(a['created_at'] as String));
        for (final n in out) {
          n['voice'] = byId[n['voice_id']];
        }
      }
      if (!mounted) return;
      setState(() {
        _items = out.take(60).toList();
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = _items ?? [];
        _error = 'Could not load notifications.';
      });
    }
  }

  Widget _row(Map<String, dynamic> n, int i) {
    final cs = Theme.of(context).colorScheme;
    final p = (n['profiles'] as Map?) ?? const {};
    final username = (p['username'] as String?) ?? '';
    final nick = (p['nickname'] as String?) ?? '';
    final name = nick.isNotEmpty ? nick : '@$username';
    final voice = n['voice'] as Map?;
    final caption = (voice?['caption'] as String?) ?? '';
    final emoji = voice == null ? '' : moodOf(voice['mood'] as String).emoji;
    final action = n['kind'] == 'like' ? 'liked your voice' : 'reposted your voice';
    final when = DateTime.tryParse(n['created_at'] as String? ?? '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FadeSlideIn(
        delay: Duration(milliseconds: (i < 8 ? i : 8) * 50),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => UserProfilePage(userId: n['user_id'] as String),
          )),
          child: GlassBox(
            radius: 28,
            padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
            child: Row(
              children: [
                Avatar(
                  name: nick.isNotEmpty ? nick : username,
                  path: p['avatar_path'] as String?,
                  size: 46,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(TextSpan(children: [
                        TextSpan(
                            text: name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: ' $action'),
                      ])),
                      if (caption.isNotEmpty)
                        Text(caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurface.withAlpha(150))),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (emoji.isNotEmpty)
                  Text(emoji, style: const TextStyle(fontSize: 22)),
                if (when != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(timeAgo(when),
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurface.withAlpha(140))),
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
    final cs = Theme.of(context).colorScheme;
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        foregroundColor: cs.onSurface,
        title: const Text('Notifications',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    20, 8, 20, 24 + MediaQuery.of(context).padding.bottom),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(child: Text(_error!)),
                    )
                  else if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(
                        child: Text('Nothing yet. Likes and reposts on your\nvoices will show up here.',
                            textAlign: TextAlign.center),
                      ),
                    )
                  else
                    for (var i = 0; i < items.length; i++) _row(items[i], i),
                ],
              ),
            ),
    );
  }
}
