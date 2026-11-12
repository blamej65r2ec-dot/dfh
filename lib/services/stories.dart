import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'follows.dart';

const storyCols =
    'id,user_id,audio_path,caption,mood,duration_ms,created_at,expires_at,profiles(username,nickname,avatar_path)';

class StoryGroup {
  StoryGroup({
    required this.userId,
    required this.name,
    required this.username,
    required this.avatarPath,
    required this.stories,
    required this.isMe,
    required this.unseen,
  });

  final String userId;
  final String name;
  final String username;
  final String? avatarPath;
  final List<Map<String, dynamic>> stories;
  final bool isMe;
  final bool unseen;

  String get lastMood => stories.last['mood'] as String;
}

class Stories {
  static SupabaseClient get _c => Supabase.instance.client;

  static Future<Set<String>> seen() async {
    try {
      final p = await SharedPreferences.getInstance();
      return (p.getStringList('seen_stories') ?? const []).toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> markSeen(String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      final l = (p.getStringList('seen_stories') ?? <String>[]);
      if (!l.contains(id)) {
        l.add(id);
        // Keep the list small.
        final trimmed = l.length > 300 ? l.sublist(l.length - 300) : l;
        await p.setStringList('seen_stories', trimmed);
      }
    } catch (_) {}
  }

  /// Active stories from you and the people you follow.
  static Future<List<StoryGroup>> load() async {
    final me = _c.auth.currentUser!.id;
    final ids = <String>{me};
    try {
      ids.addAll(await Follows.mine());
    } catch (_) {}
    final rows = await _c
        .from('voices')
        .select(storyCols)
        .eq('kind', 'story')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .inFilter('user_id', ids.toList())
        .order('created_at', ascending: true)
        .limit(200);
    final seenIds = await seen();
    final byUser = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      byUser
          .putIfAbsent(r['user_id'] as String, () => [])
          .add(Map<String, dynamic>.from(r));
    }
    final groups = <StoryGroup>[];
    byUser.forEach((uid, list) {
      final p = (list.first['profiles'] as Map?) ?? const {};
      final nick = (p['nickname'] as String?) ?? '';
      final username = (p['username'] as String?) ?? '';
      groups.add(StoryGroup(
        userId: uid,
        name: nick.isNotEmpty ? nick : username,
        username: username,
        avatarPath: p['avatar_path'] as String?,
        stories: list,
        isMe: uid == me,
        unseen: list.any((s) => !seenIds.contains(s['id'])),
      ));
    });
    groups.sort((a, b) {
      if (a.isMe != b.isMe) return a.isMe ? -1 : 1;
      if (a.unseen != b.unseen) return a.unseen ? -1 : 1;
      return (b.stories.last['created_at'] as String)
          .compareTo(a.stories.last['created_at'] as String);
    });
    return groups;
  }
}
