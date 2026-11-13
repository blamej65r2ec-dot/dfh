import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/activity.dart';
import '../services/app_events.dart';
import '../services/common.dart';
import '../services/stories.dart';
import '../services/voice_player.dart';
import '../widgets/animations.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import '../widgets/voice_list.dart';
import 'notifications_page.dart';
import 'story_viewer_page.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key, this.onAddStory});

  /// Opens the Record page in story mode.
  final VoidCallback? onAddStory;

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  static const _page = 20;
  final _c = Supabase.instance.client;
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _items = [];
  List<StoryGroup> _stories = [];
  String _myName = '';
  String? _cursor;
  bool _more = true;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    AppEvents.postsChanged.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    AppEvents.postsChanged.removeListener(_load);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.hasClients &&
        _scroll.position.pixels > _scroll.position.maxScrollExtent - 500) {
      _loadMore();
    }
  }

  /// The next voices, newest first. Voices never disappear from the feed.
  Future<List<Map<String, dynamic>>> _fetchPage() async {
    final rows = await loadVoices((cols) {
      var q = _c.from('voices').select(cols).eq('kind', 'post');
      if (_cursor != null) q = q.lt('created_at', _cursor!);
      return q.order('created_at', ascending: false).limit(_page);
    });
    if (rows.isNotEmpty) _cursor = rows.last['created_at'] as String;
    if (rows.length < _page) _more = false;
    return [
      for (final r in rows)
        if (!_items.any((e) => e['id'] == r['id'])) r
    ];
  }

  Future<void> _loadStories() async {
    try {
      final s = await Stories.load();
      if (mounted) setState(() => _stories = s);
    } catch (_) {}
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    _loadStories();
    try {
      _cursor = null;
      _more = true;
      try {
        final uid = _c.auth.currentUser!.id;
        final p = await _c
            .from('profiles')
            .select('username,nickname')
            .eq('id', uid)
            .single();
        final nick = (p['nickname'] as String?) ?? '';
        _myName = nick.isNotEmpty ? nick : (p['username'] as String? ?? '');
      } catch (_) {}
      _items = [];
      final first = await _fetchPage();
      if (!mounted) return;
      setState(() {
        _items = first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load voices.\n$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_more || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final more = await _fetchPage();
      if (!mounted) return;
      setState(() => _items = [..._items, ...more]);
    } catch (_) {}
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _openStories(int index) async {
    VoicePlayer.instance.stop();
    await Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) =>
          StoryViewerPage(groups: _stories, startGroup: index),
      transitionsBuilder: (_, a, __, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1)
                .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child),
      ),
    ));
    _loadStories();
  }

  Widget _ring(BuildContext context,
      {required bool unseen, required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: unseen ? kAccent : cs.onSurface.withAlpha(70),
          width: unseen ? 2.5 : 2,
        ),
      ),
      child: child,
    );
  }

  Widget _storiesRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tiles = <Widget>[
      // Add story
      GestureDetector(
        onTap: widget.onAddStory,
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              GlassBox(
                blur: false,
                radius: 32,
                child: const SizedBox(
                  width: 64,
                  height: 64,
                  child: Icon(Icons.add_rounded, size: 28),
                ),
              ),
              const SizedBox(height: 8),
              Text('Add',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurface.withAlpha(150))),
            ],
          ),
        ),
      ),
      for (var i = 0; i < _stories.length; i++)
        GestureDetector(
          onTap: () => _openStories(i),
          child: SizedBox(
            width: 72,
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _ring(
                      context,
                      unseen: _stories[i].unseen,
                      child: Avatar(
                        name: _stories[i].name,
                        path: _stories[i].avatarPath,
                        size: 58,
                      ),
                    ),
                    Positioned(
                      right: -6,
                      bottom: -4,
                      child: GlassBox(
                        blur: false,
                        radius: 13,
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: Center(
                            child: Text(moodOf(_stories[i].lastMood).emoji,
                                style: const TextStyle(fontSize: 14)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _stories[i].isMe ? 'You' : _stories[i].name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurface.withAlpha(150)),
                ),
              ],
            ),
          ),
        ),
    ];
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => tiles[i],
      ),
    );
  }

  Widget _footer(BuildContext context, {bool empty = false}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(top: empty ? 60 : 8, bottom: 10),
      child: Column(
        children: [
          Icon(Icons.graphic_eq_rounded,
              size: 30, color: cs.onSurface.withAlpha(110)),
          const SizedBox(height: 10),
          Text(
              empty
                  ? 'No voices yet. Be the first to speak.'
                  : "That's everything for now",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: cs.onSurface.withAlpha(150))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(0, 14, 0, pageBottomPad(context)),
          children: [
            FadeSlideIn(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(greeting(),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface.withAlpha(150))),
                          const SizedBox(height: 2),
                          Text(
                            _myName.isEmpty ? 'Hello' : 'Hello, $_myName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 26, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        VoicePlayer.instance.stop();
                        Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => const NotificationsPage()));
                      },
                      child: GlassBox(
                        radius: 23,
                        child: const SizedBox(
                          width: 46,
                          height: 46,
                          child: Icon(Icons.notifications_none_rounded,
                              size: 24),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            FadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: _storiesRow(context),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
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
                          TextButton(
                              onPressed: _load,
                              child: const Text('Try again')),
                        ],
                      ),
                    )
                  else if (_items.isEmpty)
                    _footer(context, empty: true)
                  else ...[
                    VoiceList(items: _items),
                    if (_loadingMore)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (!_more)
                      _footer(context),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
