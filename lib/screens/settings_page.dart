import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/settings.dart';
import '../widgets/animations.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import '../widgets/pill_chip.dart';
import 'activity_pages.dart';
import 'story_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _c = Supabase.instance.client;
  int _storyHours = 24;
  bool _saveArchive = true;
  bool _readReceipts = true;
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
          .select('story_hours,save_archive,read_receipts')
          .eq('id', _c.auth.currentUser!.id)
          .single();
      if (!mounted) return;
      setState(() {
        _storyHours = (p['story_hours'] as int?) ?? 24;
        _saveArchive = (p['save_archive'] as bool?) ?? true;
        _readReceipts = (p['read_receipts'] as bool?) ?? true;
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

  Widget _navRow(String label, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            const Icon(Icons.chevron_right_rounded),
          ],
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
            'Your activity',
            Column(
              children: [
                _navRow('Liked voices', () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const LikedVoicesPage()))),
                _navRow('Your voice replies', () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const MyRepliesPage()))),
                _navRow('Saved voices', () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const SavedVoicesPage()))),
                _navRow('Voice history', () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const VoiceHistoryPage()))),
              ],
            ),
          ),
          _section(
            'Voice stories',
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const StorySettingsPage()),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                        child: Text('Duration, archive and more')),
                    Icon(Icons.chevron_right_rounded),
                  ],
                ),
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
            'Privacy',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Show Heard in chats')),
                    Switch(
                      value: _readReceipts,
                      onChanged: (v) {
                        setState(() => _readReceipts = v);
                        _update({'read_receipts': v});
                      },
                    ),
                  ],
                ),
                Text(
                  'If you turn this off, nobody sees when you have heard their messages, and you will not see when they have heard yours.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withAlpha(150)),
                ),
                const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const BlockedPage()),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text('Blocked accounts')),
                    Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
              ],
            ),
            delay: 150,
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

class BlockedPage extends StatefulWidget {
  const BlockedPage({super.key});

  @override
  State<BlockedPage> createState() => _BlockedPageState();
}

class _BlockedPageState extends State<BlockedPage> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _c
          .from('blocks')
          .select('blocked_id')
          .eq('blocker_id', _c.auth.currentUser!.id);
      final ids = [for (final r in rows) r['blocked_id'] as String];
      var profiles = <Map<String, dynamic>>[];
      if (ids.isNotEmpty) {
        final ps = await _c
            .from('profiles')
            .select('id,username,nickname,avatar_path')
            .inFilter('id', ids);
        profiles = List<Map<String, dynamic>>.from(ps);
      }
      if (mounted) setState(() => _list = profiles);
    } catch (_) {
      if (mounted) setState(() => _list = []);
    }
  }

  Future<void> _unblock(String id) async {
    try {
      await _c
          .from('blocks')
          .delete()
          .eq('blocker_id', _c.auth.currentUser!.id)
          .eq('blocked_id', id);
      if (mounted) {
        setState(() => _list = _list?.where((p) => p['id'] != id).toList());
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not unblock')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = _list;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        foregroundColor: cs.onSurface,
        title: const Text('Blocked accounts',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? const Center(child: Text('You have not blocked anyone.'))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    for (final p in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassBox(
                          radius: 28,
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                          child: Row(
                            children: [
                              Avatar(
                                name: ((p['nickname'] as String?) ?? '')
                                        .isNotEmpty
                                    ? p['nickname'] as String
                                    : ((p['username'] as String?) ?? ''),
                                path: p['avatar_path'] as String?,
                                size: 44,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '@${p['username'] ?? ''}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _unblock(p['id'] as String),
                                child: const Text('Unblock'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
