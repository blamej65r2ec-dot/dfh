import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const voiceCols =
    'id,user_id,audio_path,caption,mood,duration_ms,created_at,visibility,profiles(username,nickname,avatar_path)';
const voiceColsBasic =
    'id,user_id,audio_path,caption,mood,duration_ms,created_at,profiles(username,nickname,avatar_path)';

class Activity {
  static SupabaseClient get _c => Supabase.instance.client;
  static final _uuid = RegExp(r'^[0-9a-fA-F-]{36}$');

  /// Voice history. Only plain voice ids (not comments or messages).
  static Future<void> recordView(String voiceId) async {
    if (!_uuid.hasMatch(voiceId)) return;
    try {
      await _c.from('voice_views').upsert({
        'user_id': _c.auth.currentUser!.id,
        'voice_id': voiceId,
        'viewed_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Loads voices by id, in the same order as [ids]. Hidden ones are skipped.
  static Future<List<Map<String, dynamic>>> voicesByIds(
      List<String> ids) async {
    if (ids.isEmpty) return [];
    List<dynamic> rows;
    try {
      rows = await _c.from('voices').select(voiceCols).inFilter('id', ids);
    } catch (_) {
      rows = await _c.from('voices').select(voiceColsBasic).inFilter('id', ids);
    }
    final byId = {for (final r in rows) r['id'] as String: r};
    return [
      for (final id in ids)
        if (byId[id] != null) Map<String, dynamic>.from(byId[id] as Map),
    ];
  }
}

/// Voices already shown in your feed. They do not come back.
class SeenVoices {
  static Set<String>? _cache;

  static Future<Set<String>> load() async {
    if (_cache != null) return _cache!;
    try {
      final p = await SharedPreferences.getInstance();
      _cache = (p.getStringList('seen_voices') ?? const []).toSet();
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  static Future<void> add(String id) async {
    final s = await load();
    if (!s.add(id)) return;
    try {
      final p = await SharedPreferences.getInstance();
      final l = s.toList();
      await p.setStringList(
          'seen_voices', l.length > 2000 ? l.sublist(l.length - 2000) : l);
    } catch (_) {}
  }

  static Future<void> clear() async {
    _cache = {};
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('seen_voices');
    } catch (_) {}
  }
}
