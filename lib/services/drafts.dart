import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class Draft {
  Draft({
    required this.id,
    required this.path,
    required this.durationMs,
    this.mood,
    this.caption = '',
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String id;
  final String path;
  final int durationMs;
  final String? mood;
  final String caption;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'durationMs': durationMs,
        'mood': mood,
        'caption': caption,
        'at': at.toIso8601String(),
      };

  factory Draft.fromJson(Map<String, dynamic> j) => Draft(
        id: j['id'] as String,
        path: j['path'] as String,
        durationMs: j['durationMs'] as int,
        mood: j['mood'] as String?,
        caption: (j['caption'] as String?) ?? '',
        at: DateTime.tryParse((j['at'] as String?) ?? ''),
      );
}

/// Drafts live on the phone only, until they are posted.
class DraftStore {
  static Future<File> _file() async {
    final d = await getApplicationDocumentsDirectory();
    return File('${d.path}/drafts.json');
  }

  static Future<List<Draft>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final raw = jsonDecode(await f.readAsString()) as List;
      final list = raw
          .map((e) => Draft.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((d) => File(d.path).existsSync())
          .toList();
      list.sort((a, b) => b.at.compareTo(a.at));
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<Draft> list) async {
    final f = await _file();
    await f.writeAsString(jsonEncode(list.map((d) => d.toJson()).toList()));
  }

  static Future<void> add(Draft d) async {
    final list = await load();
    list.removeWhere((x) => x.id == d.id);
    list.add(d);
    await _save(list);
  }

  static Future<void> removeById(String id, {bool deleteAudio = false}) async {
    final list = await load();
    for (final d in list.where((x) => x.id == id)) {
      if (deleteAudio) {
        try {
          await File(d.path).delete();
        } catch (_) {}
      }
    }
    list.removeWhere((x) => x.id == id);
    await _save(list);
  }
}
