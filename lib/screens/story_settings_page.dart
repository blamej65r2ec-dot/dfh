import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/animations.dart';
import '../widgets/glass.dart';
import '../widgets/segmented_pill.dart';
import '../widgets/voice_list.dart';

const _hours = [6, 12, 18, 24];

class StorySettingsPage extends StatefulWidget {
  const StorySettingsPage({super.key});

  @override
  State<StorySettingsPage> createState() => _StorySettingsPageState();
}

class _StorySettingsPageState extends State<StorySettingsPage> {
  final _c = Supabase.instance.client;
  int _hoursValue = 24;
  bool _saveArchive = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _c
          .from('profiles')
          .select('story_hours,save_archive')
          .eq('id', _c.auth.currentUser!.id)
          .single();
      if (!mounted) return;
      setState(() {
        _hoursValue = (p['story_hours'] as int?) ?? 24;
        _saveArchive = (p['save_archive'] as bool?) ?? true;
      });
    } catch (_) {}
  }

  Future<void> _update(Map<String, dynamic> values) async {
    try {
      await _c
          .from('profiles')
          .update(values)
          .eq('id', _c.auth.currentUser!.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not save that')));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grey = cs.onSurface.withAlpha(150);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            Row(
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
                const Text('Voice stories',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 24),
            FadeSlideIn(
              child: GlassBox(
                blur: false,
                radius: 28,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Stories disappear after',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 14),
                    SegmentedPill(
                      labels: [for (final h in _hours) '${h}h'],
                      selected: _hours.indexOf(_hoursValue).clamp(0, 3).toInt(),
                      onChanged: (i) {
                        setState(() => _hoursValue = _hours[i]);
                        _update({'story_hours': _hours[i]});
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'New stories stay visible for this long. After that they leave your followers\' view.',
                      style: TextStyle(fontSize: 13, color: grey, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: GlassBox(
                blur: false,
                radius: 28,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Column(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const ArchivePage()),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text('Archive',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ),
                            Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    ),
                    Divider(height: 1, color: cs.onSurface.withAlpha(28)),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Save to archive',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text('Keep expired stories, only you see them',
                                    style: TextStyle(
                                        fontSize: 13, color: grey)),
                              ],
                            ),
                          ),
                          Switch(
                            value: _saveArchive,
                            onChanged: (v) {
                              setState(() => _saveArchive = v);
                              _update({'save_archive': v});
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Your expired stories. Only you can see them.
class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _c
          .from('voices')
          .select(
              'id,user_id,audio_path,caption,mood,duration_ms,created_at,profiles(username,nickname,avatar_path)')
          .eq('user_id', _c.auth.currentUser!.id)
          .eq('kind', 'story')
          .lt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(60);
      if (mounted) setState(() => _items = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      if (mounted) setState(() => _items = _items ?? []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
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
                  const Text('Archive',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: items == null
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? const Center(child: Text('Your archive is empty.'))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                          children: [VoiceList(items: items)],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
