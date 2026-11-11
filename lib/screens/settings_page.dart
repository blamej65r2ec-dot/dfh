import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/settings.dart';
import '../widgets/animations.dart';
import '../widgets/glass.dart';
import '../widgets/pill_chip.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _c = Supabase.instance.client;
  int _storyHours = 24;
  bool _saveArchive = true;
  bool _loaded = false;

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
        _storyHours = (p['story_hours'] as int?) ?? 24;
        _saveArchive = (p['save_archive'] as bool?) ?? true;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
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

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in any time.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await _c.auth.signOut();
  }

  Widget _section(String title, Widget child, {int delay = 0}) {
    return FadeSlideIn(
      delay: Duration(milliseconds: delay),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: GlassBox(
          radius: 28,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _soonRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(color: cs.onSurface.withAlpha(150))),
          ),
          Text(value, style: TextStyle(color: cs.onSurface.withAlpha(120))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        foregroundColor: cs.onSurface,
        title: const Text('Settings',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          _section(
            'Appearance',
            ValueListenableBuilder<ThemeMode>(
              valueListenable: AppSettings.themeMode,
              builder: (context, mode, _) => Row(
                children: [
                  PillChip(
                      label: 'System',
                      selected: mode == ThemeMode.system,
                      onTap: () => AppSettings.setTheme(ThemeMode.system)),
                  PillChip(
                      label: 'Light',
                      selected: mode == ThemeMode.light,
                      onTap: () => AppSettings.setTheme(ThemeMode.light)),
                  PillChip(
                      label: 'Dark',
                      selected: mode == ThemeMode.dark,
                      onTap: () => AppSettings.setTheme(ThemeMode.dark)),
                ],
              ),
            ),
          ),
          _section(
            'Voice stories',
            Opacity(
              opacity: _loaded ? 1 : 0.5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('A story disappears after'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final h in const [6, 12, 18, 24])
                        PillChip(
                          label: '${h}h',
                          selected: _storyHours == h,
                          onTap: () {
                            setState(() => _storyHours = h);
                            _update({'story_hours': h});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(
                          child: Text('Keep expired stories in my archive')),
                      Switch(
                        value: _saveArchive,
                        onChanged: (v) {
                          setState(() => _saveArchive = v);
                          _update({'save_archive': v});
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            delay: 60,
          ),
          _section(
            'Language and notifications',
            Column(
              children: [
                _soonRow('Language', 'English · more soon'),
                _soonRow('Notifications', 'Coming soon'),
              ],
            ),
            delay: 120,
          ),
          _section(
            'Account',
            SizedBox(
              width: double.infinity,
              child: PressScale(
                child: FilledButton(
                  onPressed: _signOut,
                  child: const Text('Sign out'),
                ),
              ),
            ),
            delay: 180,
          ),
        ],
      ),
    );
  }
}
