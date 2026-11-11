import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/common.dart';
import '../services/voice_player.dart';
import '../widgets/animations.dart';
import '../widgets/glass.dart';
import '../widgets/waveform.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>> _items = [];
  Set<String> _liked = {};
  Set<String> _reposted = {};
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
      var q = _c
          .from('voices')
          .select(
              'id,user_id,audio_path,caption,mood,duration_ms,created_at,profiles(username,nickname)')
          .eq('kind', 'post');
      if (_mood != null) q = q.eq('mood', _mood!);
      final data = await q.order('created_at', ascending: false).limit(40);
      final likes = await _c.from('likes').select('voice_id').eq('user_id', uid);
      final reps =
          await _c.from('reposts').select('voice_id').eq('user_id', uid);
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(data);
        _liked = {for (final r in likes) r['voice_id'] as String};
        _reposted = {for (final r in reps) r['voice_id'] as String};
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

  Future<void> _toggle(String table, String id, Set<String> set) async {
    final uid = _c.auth.currentUser!.id;
    final had = set.contains(id);
    HapticFeedback.selectionClick();
    setState(() => had ? set.remove(id) : set.add(id));
    try {
      if (had) {
        await _c.from(table).delete().eq('user_id', uid).eq('voice_id', id);
      } else {
        await _c.from(table).insert({'user_id': uid, 'voice_id': id});
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => had ? set.add(id) : set.remove(id));
    }
  }

  void _pickMood(String? m) {
    if (_mood == m) return;
    VoicePlayer.instance.stop();
    setState(() => _mood = m);
    _load();
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: selected ? cs.primary : cs.onSurface.withAlpha(24),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: selected ? cs.onPrimary : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 130 + bottom),
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
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _chip('All', _mood == null, () => _pickMood(null)),
                  for (final m in moods)
                    _chip(m.emoji, _mood == m.key, () => _pickMood(m.key)),
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
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(
                  child: Text('No voices here yet. Be the first to speak.'),
                ),
              )
            else
              for (var i = 0; i < _items.length; i++)
                Padding(
                  key: ValueKey(_items[i]['id']),
                  padding: const EdgeInsets.only(bottom: 16),
                  child: FadeSlideIn(
                    delay: Duration(milliseconds: (i < 6 ? i : 6) * 70),
                    child: _VoiceCard(
                      v: _items[i],
                      liked: _liked.contains(_items[i]['id']),
                      reposted: _reposted.contains(_items[i]['id']),
                      onLike: () =>
                          _toggle('likes', _items[i]['id'] as String, _liked),
                      onRepost: () => _toggle(
                          'reposts', _items[i]['id'] as String, _reposted),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({
    required this.v,
    required this.liked,
    required this.reposted,
    required this.onLike,
    required this.onRepost,
  });

  final Map<String, dynamic> v;
  final bool liked;
  final bool reposted;
  final VoidCallback onLike;
  final VoidCallback onRepost;

  Widget _action(IconData on, IconData off, bool active, VoidCallback tap) {
    return IconButton(
      onPressed: tap,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
        child: Icon(active ? on : off, key: ValueKey(active)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final profile = (v['profiles'] as Map?) ?? const {};
    final username = (profile['username'] as String?) ?? 'unknown';
    final nick = (profile['nickname'] as String?) ?? '';
    final caption = (v['caption'] as String?) ?? '';
    final id = v['id'] as String;
    final player = VoicePlayer.instance;
    final bars = barsFor(id);

    return GlassBox(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nick.isNotEmpty ? nick : '@$username',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      if (nick.isNotEmpty)
                        Text('@$username',
                            style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurface.withAlpha(150))),
                    ],
                  ),
                ),
                Text(moodOf(v['mood'] as String).emoji,
                    style: const TextStyle(fontSize: 30)),
              ],
            ),
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(caption, style: const TextStyle(fontSize: 15)),
          ],
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                player.toggle(id, v['audio_path'] as String);
              },
              child: ValueListenableBuilder<String?>(
                valueListenable: player.currentId,
                builder: (context, cur, _) {
                  final active = cur == id;
                  return ValueListenableBuilder<double>(
                    valueListenable: player.progress,
                    builder: (context, p, _) => SizedBox(
                      height: 56,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: WaveformPainter(
                          bars: bars,
                          progress: active ? p : 0,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Row(
            children: [
              ValueListenableBuilder<String?>(
                valueListenable: player.currentId,
                builder: (context, cur, _) => ValueListenableBuilder<bool>(
                  valueListenable: player.playing,
                  builder: (context, playing, _) => Icon(
                    cur == id && playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                fmtDuration(v['duration_ms'] as int),
                style: TextStyle(color: cs.onSurface.withAlpha(170)),
              ),
              const Spacer(),
              _action(Icons.favorite_rounded, Icons.favorite_border_rounded,
                  liked, onLike),
              _action(Icons.repeat_on_rounded, Icons.repeat_rounded, reposted,
                  onRepost),
            ],
          ),
        ],
      ),
    );
  }
}
