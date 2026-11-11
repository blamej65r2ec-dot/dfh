import 'package:supabase_flutter/supabase_flutter.dart';

/// Who YOU follow. Follower lists and counts are never shown.
class Follows {
  static SupabaseClient get _c => Supabase.instance.client;

  static Future<Set<String>> mine() async {
    final uid = _c.auth.currentUser!.id;
    final rows =
        await _c.from('follows').select('following_id').eq('follower_id', uid);
    return {for (final r in rows) r['following_id'] as String};
  }

  static Future<void> set(String userId, bool follow) async {
    final uid = _c.auth.currentUser!.id;
    if (follow) {
      await _c
          .from('follows')
          .insert({'follower_id': uid, 'following_id': userId});
    } else {
      await _c
          .from('follows')
          .delete()
          .eq('follower_id', uid)
          .eq('following_id', userId);
    }
  }
}
