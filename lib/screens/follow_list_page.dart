import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import 'user_profile_page.dart';

/// Your followers, or the people you follow. Only you can open this.
class FollowListPage extends StatefulWidget {
  const FollowListPage({super.key, required this.followers});
  final bool followers;

  @override
  State<FollowListPage> createState() => _FollowListPageState();
}

class _FollowListPageState extends State<FollowListPage> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>>? _people;
  final Set<String> _removed = {};

  String get _me => _c.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = widget.followers
          ? await _c
              .from('follows')
              .select('follower_id')
              .eq('following_id', _me)
              .order('created_at', ascending: false)
              .limit(500)
          : await _c
              .from('follows')
              .select('following_id')
              .eq('follower_id', _me)
              .order('created_at', ascending: false)
              .limit(500);
      final key = widget.followers ? 'follower_id' : 'following_id';
      final ids = [for (final r in rows) r[key] as String];
      var people = <Map<String, dynamic>>[];
      if (ids.isNotEmpty) {
        final ps = await _c
            .from('profiles')
            .select('id,username,nickname,avatar_path')
            .inFilter('id', ids);
        final byId = {for (final p in ps) p['id'] as String: p};
        people = [
          for (final id in ids)
            if (byId[id] != null) Map<String, dynamic>.from(byId[id] as Map)
        ];
      }
      if (mounted) setState(() => _people = people);
    } catch (_) {
      if (mounted) setState(() => _people = _people ?? []);
    }
  }

  Future<void> _unfollow(String id) async {
    setState(() => _removed.add(id));
    try {
      await _c
          .from('follows')
          .delete()
          .eq('follower_id', _me)
          .eq('following_id', id);
    } catch (_) {
      if (mounted) setState(() => _removed.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final people = _people;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
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
                  Text(widget.followers ? 'Followers' : 'Following',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: people == null
                  ? const Center(child: CircularProgressIndicator())
                  : people.isEmpty
                      ? Center(
                          child: Text(widget.followers
                              ? 'Nobody follows you yet.'
                              : 'You are not following anyone yet.'))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                          children: [
                            for (final p in people)
                              if (!_removed.contains(p['id']))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => UserProfilePage(
                                            userId: p['id'] as String),
                                      ),
                                    ),
                                    child: GlassBox(
                                      blur: false,
                                      radius: 28,
                                      padding: const EdgeInsets.fromLTRB(
                                          14, 12, 14, 12),
                                      child: Row(
                                        children: [
                                          Avatar(
                                            name: ((p['nickname'] as String?) ??
                                                        '')
                                                    .isNotEmpty
                                                ? p['nickname'] as String
                                                : ((p['username'] as String?) ??
                                                    ''),
                                            path: p['avatar_path'] as String?,
                                            size: 46,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  ((p['nickname'] as String?) ??
                                                              '')
                                                          .isNotEmpty
                                                      ? p['nickname'] as String
                                                      : '@${p['username']}',
                                                  style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700),
                                                ),
                                                if (((p['nickname']
                                                                as String?) ??
                                                            '')
                                                        .isNotEmpty)
                                                  Text('@${p['username']}',
                                                      style: TextStyle(
                                                          fontSize: 13,
                                                          color: cs.onSurface
                                                              .withAlpha(150))),
                                              ],
                                            ),
                                          ),
                                          if (!widget.followers)
                                            TextButton(
                                              onPressed: () =>
                                                  _unfollow(p['id'] as String),
                                              child: const Text('Unfollow'),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
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
