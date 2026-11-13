import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/activity.dart';
import '../services/follows.dart';
import '../services/voice_player.dart';
import '../widgets/animations.dart';
import '../widgets/avatar.dart';
import '../widgets/glass.dart';
import '../widgets/report_sheet.dart';
import '../widgets/voice_list.dart';
import 'new_chat_page.dart';


class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key, required this.userId});
  final String userId;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final _c = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _voices = [];
  bool _following = false;
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
      _loading = _profile == null;
      _error = null;
    });
    try {
      final profile = await _c
          .from('profiles')
          .select()
          .eq('id', widget.userId)
          .single();
      var voices = <Map<String, dynamic>>[];
      var following = false;
      try {
        voices = await loadVoices((cols) => _c
            .from('voices')
            .select(cols)
            .eq('user_id', widget.userId)
            .eq('kind', 'post')
            .order('created_at', ascending: false)
            .limit(50));
      } catch (_) {}
      try {
        following = (await Follows.mine()).contains(widget.userId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _voices = voices;
        _following = following;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this profile.';
        _loading = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    final had = _following;
    HapticFeedback.selectionClick();
    setState(() => _following = !had);
    try {
      await Follows.set(widget.userId, !had);
    } catch (_) {
      if (mounted) setState(() => _following = had);
    }
  }

  Future<void> _block() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block this account?'),
        content: const Text(
            'You will not see their voices. You can unblock them in Settings.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Block')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _c.from('blocks').insert({
        'blocker_id': _c.auth.currentUser!.id,
        'blocked_id': widget.userId,
      });
      try {
        await Follows.set(widget.userId, false);
      } catch (_) {}
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Account blocked')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not block this account')));
    }
  }

  Widget _tag(String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: cs.onSurface.withAlpha(24),
      ),
      child: Text(text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    );
  }

  Widget _body() {
    final cs = Theme.of(context).colorScheme;
    final p = _profile;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (p == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? 'Something went wrong.'),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    final username = (p['username'] as String?) ?? '';
    final nick = (p['nickname'] as String?) ?? '';
    final age = p['age'];
    final country = (p['country'] as String?) ?? '';
    final hobbies = List<String>.from(p['hobbies'] ?? const []);
    final langs = List<String>.from(p['languages'] ?? const []);
    final hasBio = age != null ||
        country.isNotEmpty ||
        hobbies.isNotEmpty ||
        langs.isNotEmpty;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding:
            EdgeInsets.fromLTRB(20, 8, 20, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          FadeSlideIn(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.onSurface, width: 2.5),
                  ),
                  child: Avatar(
                    name: nick.isNotEmpty ? nick : username,
                    path: p['avatar_path'] as String?,
                    size: 96,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  nick.isNotEmpty ? nick : '@$username',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (nick.isNotEmpty)
                  Text('@$username',
                      style: TextStyle(color: cs.onSurface.withAlpha(160))),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                PressScale(
                  child: GestureDetector(
                    onTap: _toggleFollow,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        color: _following
                            ? cs.onSurface.withAlpha(24)
                            : cs.primary,
                      ),
                      child: Text(
                        _following ? 'Following' : 'Follow',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _following ? cs.onSurface : cs.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                    const SizedBox(width: 10),
                    PressScale(
                      child: GestureDetector(
                        onTap: () => openChatWith(context, {
                          'id': widget.userId,
                          'username': username,
                          'nickname': nick,
                          'avatar_path': p['avatar_path'],
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            color: cs.onSurface.withAlpha(24),
                          ),
                          child: const Text('Message',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (hasBio) ...[
            const SizedBox(height: 20),
            FadeSlideIn(
              delay: const Duration(milliseconds: 80),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (age != null) _tag('$age years'),
                  if (country.isNotEmpty) _tag(country),
                  for (final h in hobbies) _tag(h),
                  for (final l in langs) _tag(l),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text('Voices',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          if (_voices.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: Center(child: Text('No voices yet.')),
            )
          else
            VoiceList(items: _voices),
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
        actions: [
          if (_profile != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded),
              onSelected: (a) {
                if (a == 'report') {
                  showReportSheet(context,
                      type: 'profile', id: widget.userId);
                }
                if (a == 'block') _block();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'report', child: Text('Report')),
                PopupMenuItem(value: 'block', child: Text('Block')),
              ],
            ),
        ],
      ),
      body: _body(),
    );
  }
}
