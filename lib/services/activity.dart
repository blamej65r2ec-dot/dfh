import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const voiceBase = 'id,user_id,audio_path,caption,mood,duration_ms,created_at';
const profileEmbed = 'profiles!user_id(username,nickname,avatar_path)';
const voiceCols = '$voiceBase,$profileEmbed';

/// Adds each voice's author (name, photo) without using a database join.
Future<List<Map<String, dynamic>>> attachProfiles(List<dynamic> rows) async {
  final list = [for (final r in rows) Map<String, dynamic>.from(r as Map)];
  final ids = {for (final r in list) r['user_id'] as String}.toList();
  if (ids.isEmpty) return list;
  final ps = await Supabase.instance.client
      .from('profiles')
      .select('id,username,nickname,avatar_path')
      .inFilter('id', ids);
  final byId = {for (final p in ps) p['id'] as String: p};
  for (final r in list) {
    final p = byId[r['user_id']];
    r['profiles'] = p == null
        ? <String, dynamic>{}
        : {
            'username': p['username'],
            'nickname': p['nickname'],
            'avatar_path': p['avatar_path'],
          };
  }
  return list;
}

/// Runs a voices query. If the database join fails, it runs again without
/// the join and adds the authors by itself, so voices always show up.
Future<List<Map<String, dynamic>>> loadVoices(
  Future<dynamic> Function(String cols) run, {
  String extra = '',
}) async {
  final base = extra.isEmpty ? voiceBase : '$voiceBase,$extra';
  try {
    final rows = await run('$base,$profileEmbed');
    return [for (final r in rows as List) Map<String, dynamic>.from(r as Map)];
  } catch (_) {
    final rows = await run(base);
    return attachProfiles(rows as List);
  }
}

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
    final rows = await loadVoices(
        (cols) => _c.from('voices').select(cols).inFilter('id', ids));
    final byId = {for (final r in rows) r['id'] as String: r};
    return [
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
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
