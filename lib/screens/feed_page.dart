import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/common.dart';
import '../services/voice_player.dart';
import '../widgets/animations.dart';
import '../widgets/pill_chip.dart';
import '../widgets/voice_list.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>> _items = [];
  int _tab = 0; // 0 = For You, 1 = Following
  String? _mood;
  bool _loading = true;
  String? _error;

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = _c.auth.currentUser!.id;
      List<String>? ids;
      if (_tab == 1) {
        final f =
            await _c.from('follows').select('following_id').eq('follower_id', uid);
        ids = [for (final r in f) r['following_id'] as String];
        if (ids.isEmpty) {
          if (!mounted) return;
          setState(() {
            _items = [];
            _loading = false;
          });
          return;
        }
      }
      var q = _c
          .from('voices')
          .select(
              'id,user_id,audio_path,caption,mood,duration_ms,created_at,profiles(username,nickname,avatar_path)')
          .eq('kind', 'post');
      if (ids != null) q = q.inFilter('user_id', ids);
      if (_mood != null) q = q.eq('mood', _mood!);
      final data = await q.order('created_at', ascending: false).limit(40);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load voices.';
        _loading = false;
      });
    }
  }

  void _setTab(int t) {
    if (_tab == t) return;
    VoicePlayer.instance.stop();
    setState(() => _tab = t);
    _load();
  }

  void _pickMood(String? m) {
    if (_mood == m) return;
    VoicePlayer.instance.stop();
    setState(() => _mood = m);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, pageBottomPad(context)),
          children: [
            FadeSlideIn(
              child: Text(
                greeting(),
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                PillChip(
                    label: 'For You',
                    selected: _tab == 0,
                    onTap: () => _setTab(0)),
                PillChip(
                    label: 'Following',
                    selected: _tab == 1,
                    onTap: () => _setTab(1)),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  PillChip(
                      label: 'All',
                      selected: _mood == null,
                      onTap: () => _pickMood(null)),
                  for (final m in moods)
                    PillChip(
                        label: m.emoji,
                        selected: _mood == m.key,
                        onTap: () => _pickMood(m.key)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Column(
                  children: [
                    Text(_error!),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _load, child: const Text('Try again')),
                  ],
                ),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Center(
                  child: Text(
                    _tab == 1
                        ? 'Follow people from Search to hear them here.'
                        : 'No voices here yet. Be the first to speak.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              VoiceList(items: _items),
          ],
        ),
      ),
    );
  }
}
