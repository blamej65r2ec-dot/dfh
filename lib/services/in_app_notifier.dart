import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/conversation_page.dart';
import '../screens/voice_detail_page.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';

/// Banners that drop from the top while the app is open: new voice messages,
/// likes, reposts and voice replies. They only show live, as they happen.
class InAppNotifier {
  static final navKey = GlobalKey<NavigatorState>();

  /// The chat that is open right now (no banner for it).
  static String? activeConversationId;

  static RealtimeChannel? _ch;
  static String? _forUser;
  static final Map<String, Map<String, dynamic>> _profiles = {};
  static OverlayEntry? _entry;
  static GlobalKey<_BannerState>? _bannerKey;
  static Timer? _timer;

  static SupabaseClient get _c => Supabase.instance.client;

  static void start() {
    final me = _c.auth.currentUser?.id;
    if (me == null) return;
    if (_ch != null && _forUser == me) return;
    stop();
    _forUser = me;
    _ch = _c
        .channel('notif:$me')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (p) => _onMessage(p.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'likes',
          callback: (p) => _onReaction(p.newRecord, 'like'),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'reposts',
          callback: (p) => _onReaction(p.newRecord, 'repost'),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'comments',
          callback: (p) => _onComment(p.newRecord),
        )
        .subscribe();
  }

  static void stop() {
    final ch = _ch;
    _ch = null;
    _forUser = null;
    if (ch != null) _c.removeChannel(ch);
    _dismissNow();
  }

  static Future<Map<String, dynamic>?> _profile(String id) async {
    final cached = _profiles[id];
    if (cached != null) return cached;
    try {
      final p = await _c
          .from('profiles')
          .select('id,username,nickname,avatar_path')
          .eq('id', id)
          .single();
      final m = Map<String, dynamic>.from(p);
      _profiles[id] = m;
      return m;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _onMessage(Map<String, dynamic> rec) async {
    try {
      final sender = rec['sender_id'] as String?;
      final conv = rec['conversation_id'] as String?;
      if (sender == null || conv == null || sender == _forUser) return;
      if (conv == activeConversationId) return;
      final p = await _profile(sender);
      if (p == null) return;
      final isStory = rec['story_id'] != null;
      _show(
        profile: p,
        text: isStory
            ? 'replied to your story with a voice'
            : 'sent you a voice',
        icon: Icons.mic_rounded,
        onTap: () => _open((_) => ConversationPage(
              conversationId: conv,
              other: p,
            )),
      );
    } catch (_) {}
  }

  static Future<void> _onReaction(Map<String, dynamic> rec, String kind) async {
    try {
      final who = rec['user_id'] as String?;
      final voice = rec['voice_id'] as String?;
      if (who == null || voice == null || who == _forUser) return;
      final p = await _profile(who);
      if (p == null) return;
      _show(
        profile: p,
        text: kind == 'like' ? 'liked your voice' : 'reposted your voice',
        icon: kind == 'like' ? Icons.favorite_rounded : Icons.repeat_rounded,
        onTap: () => _open((_) => VoiceDetailPage(voiceId: voice)),
      );
    } catch (_) {}
  }

  static Future<void> _onComment(Map<String, dynamic> rec) async {
    try {
      final who = rec['user_id'] as String?;
      final voice = rec['voice_id'] as String?;
      if (who == null || voice == null || who == _forUser) return;
      // Replies are readable by everyone: only tell the voice's owner.
      final v = await _c
          .from('voices')
          .select('user_id')
          .eq('id', voice)
          .maybeSingle();
      if (v == null || v['user_id'] != _forUser) return;
      final p = await _profile(who);
      if (p == null) return;
      _show(
        profile: p,
        text: 'replied to your voice',
        icon: Icons.mode_comment_rounded,
        onTap: () => _open(
            (_) => VoiceDetailPage(voiceId: voice, openComments: true)),
      );
    } catch (_) {}
  }

  static void _open(WidgetBuilder builder) {
    navKey.currentState?.push(MaterialPageRoute<void>(builder: builder));
  }

  static void _show({
    required Map<String, dynamic> profile,
    required String text,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final overlay = navKey.currentState?.overlay;
    if (overlay == null) return;
    _dismissNow();
    final key = GlobalKey<_BannerState>();
    _bannerKey = key;
    final entry = OverlayEntry(
      builder: (_) => _Banner(
        key: key,
        profile: profile,
        text: text,
        icon: icon,
        onTap: () {
          _dismiss();
          onTap();
        },
        onHidden: _removeEntry,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    HapticFeedback.lightImpact();
    _timer = Timer(const Duration(seconds: 4), _dismiss);
  }

  static void _dismiss() {
    _timer?.cancel();
    final s = _bannerKey?.currentState;
    if (s != null) {
      s.hide();
    } else {
      _removeEntry();
    }
  }

  static void _removeEntry() {
    _entry?.remove();
    _entry = null;
    _bannerKey = null;
  }

  static void _dismissNow() {
    _timer?.cancel();
    _removeEntry();
  }
}

class _Banner extends StatefulWidget {
  const _Banner({
    super.key,
    required this.profile,
    required this.text,
    required this.icon,
    required this.onTap,
    required this.onHidden,
  });

  final Map<String, dynamic> profile;
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onHidden;

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 300),
  );
  bool _hiding = false;

  @override
  void initState() {
    super.initState();
    _a.forward();
  }

  void hide() {
    if (_hiding) return;
    _hiding = true;
    _a.reverse().whenComplete(widget.onHidden);
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final top = MediaQuery.of(context).padding.top;
    final nick = (widget.profile['nickname'] as String?) ?? '';
    final username = (widget.profile['username'] as String?) ?? '';
    final name = nick.isNotEmpty ? nick : '@$username';
    final curve = CurvedAnimation(
      parent: _a,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -1.6), end: Offset.zero)
            .animate(curve),
        child: FadeTransition(
          opacity: _a,
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, top + 8, 14, 0),
            child: Material(
              type: MaterialType.transparency,
              child: GestureDetector(
                onTap: widget.onTap,
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) < -100) hide();
                },
                child: GlassBox(
                  radius: 26,
                  padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
                  child: Row(
                    children: [
                      Avatar(
                        name: nick.isNotEmpty ? nick : username,
                        path: widget.profile['avatar_path'] as String?,
                        size: 44,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            Text(widget.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: cs.onSurface.withAlpha(170))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(widget.icon, size: 22),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
