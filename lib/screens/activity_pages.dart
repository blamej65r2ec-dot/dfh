import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/activity.dart';
import '../services/common.dart';
import '../services/voice_player.dart';
import '../widgets/glass.dart';
import '../widgets/voice_list.dart';
import '../widgets/waveform.dart';

SupabaseClient get _c => Supabase.instance.client;

Future<List<Map<String, dynamic>>> _idsThenVoices(
    String table, String orderBy) async {
  final rows = await _c
      .from(table)
      .select('voice_id')
      .eq('user_id', _c.auth.currentUser!.id)
      .order(orderBy, ascending: false)
      .limit(100);
  return Activity.voicesByIds([for (final r in rows) r['voice_id'] as String]);
}

class _Header extends StatelessWidget {
  const _Header({required this.title, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
          Expanded(
            child: Text(title,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _VoicesPage extends StatefulWidget {
  const _VoicesPage({
    required this.title,
    required this.empty,
    required this.loader,
    this.onClear,
  });

  final String title;
  final String empty;
  final Future<List<Map<String, dynamic>>> Function() loader;
  final Future<void> Function()? onClear;

  @override
  State<_VoicesPage> createState() => _VoicesPageState();
}

class _VoicesPageState extends State<_VoicesPage> {
  List<Map<String, dynamic>>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    VoicePlayer.instance.stop();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await widget.loader();
      if (mounted) setState(() => _items = l);
    } catch (_) {
      if (mounted) setState(() => _items = _items ?? []);
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('This removes the list of voices you listened to.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.onClear?.call();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              title: widget.title,
              action: widget.onClear == null
                  ? null
                  : TextButton(onPressed: _clear, child: const Text('Clear')),
            ),
            Expanded(
              child: items == null
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? Center(child: Text(widget.empty))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                            children: [VoiceList(items: items)],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class LikedVoicesPage extends StatelessWidget {
  const LikedVoicesPage({super.key});
  @override
  Widget build(BuildContext context) => _VoicesPage(
        title: 'Liked voices',
        empty: 'Voices you like show up here.',
        loader: () => _idsThenVoices('likes', 'created_at'),
      );
}

class SavedVoicesPage extends StatelessWidget {
  const SavedVoicesPage({super.key});
  @override
  Widget build(BuildContext context) => _VoicesPage(
        title: 'Saved voices',
        empty: 'Tap the bookmark on a voice to save it.',
        loader: () => _idsThenVoices('saves', 'created_at'),
      );
}

class VoiceHistoryPage extends StatelessWidget {
  const VoiceHistoryPage({super.key});
  @override
  Widget build(BuildContext context) => _VoicesPage(
        title: 'Voice history',
        empty: 'Voices you listen to show up here.',
        loader: () => _idsThenVoices('voice_views', 'viewed_at'),
        onClear: () async {
          await _c
              .from('voice_views')
              .delete()
              .eq('user_id', _c.auth.currentUser!.id);
        },
      );
}

/// Voice replies you sent.
class MyRepliesPage extends StatefulWidget {
  const MyRepliesPage({super.key});

  @override
  State<MyRepliesPage> createState() => _MyRepliesPageState();
}

class _MyRepliesPageState extends State<MyRepliesPage> {
  List<Map<String, dynamic>>? _items;
  Map<String, String> _owners = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    VoicePlayer.instance.stop();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _c
          .from('comments')
          .select('id,voice_id,audio_path,duration_ms,created_at')
          .eq('user_id', _c.auth.currentUser!.id)
          .order('created_at', ascending: false)
          .limit(100);
      final list = List<Map<String, dynamic>>.from(rows);
      final vids = {for (final r in list) r['voice_id'] as String}.toList();
      final owners = <String, String>{};
      if (vids.isNotEmpty) {
        try {
          final vs = await _c
              .from('voices')
              .select('id,profiles(username,nickname)')
              .inFilter('id', vids);
          for (final v in vs) {
            final p = (v['profiles'] as Map?) ?? const {};
            final nick = (p['nickname'] as String?) ?? '';
            owners[v['id'] as String] =
                nick.isNotEmpty ? nick : '@${p['username'] ?? ''}';
          }
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _items = list;
          _owners = owners;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _items = _items ?? []);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await VoicePlayer.instance.stop();
      await _c.from('comments').delete().eq('id', id);
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _items;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _Header(title: 'Your voice replies'),
            Expanded(
              child: items == null
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? const Center(child: Text('Replies you send show up here.'))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                          children: [
                            for (final r in items)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: GlassBox(
                                  blur: false,
                                  radius: 28,
                                  padding:
                                      const EdgeInsets.fromLTRB(18, 14, 8, 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'Reply to ${_owners[r['voice_id']] ?? 'a voice'}'
                                              '${DateTime.tryParse(r['created_at'] as String? ?? '') != null ? '  ·  ${timeAgo(DateTime.parse(r['created_at'] as String))}' : ''}',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color: cs.onSurface
                                                      .withAlpha(160)),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                                Icons.delete_outline_rounded),
                                            onPressed: () =>
                                                _delete(r['id'] as String),
                                          ),
                                        ],
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            right: 10, bottom: 6),
                                        child: VoiceWave(
                                          id: 'c:${r['id']}',
                                          audioPath: r['audio_path'] as String,
                                          small: true,
                                        ),
                                      ),
                                    ],
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
