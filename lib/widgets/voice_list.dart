import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/user_profile_page.dart';
import '../services/voice_player.dart';
import 'animations.dart';
import 'comments_sheet.dart';
import 'report_sheet.dart';
import 'voice_card.dart';

/// A non-scrolling list of voice cards that handles like and repost state.
class VoiceList extends StatefulWidget {
  const VoiceList({super.key, required this.items});
  final List<Map<String, dynamic>> items;

  @override
  State<VoiceList> createState() => _VoiceListState();
}

class _VoiceListState extends State<VoiceList> {
  final _c = Supabase.instance.client;
  Set<String> _liked = {};
  Set<String> _reposted = {};
  final Set<String> _hidden = {};

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  @override
  void didUpdateWidget(VoiceList old) {
    super.didUpdateWidget(old);
    if (!identical(old.items, widget.items)) _loadMine();
  }

  Future<void> _loadMine() async {
    final ids = widget.items.map((e) => e['id'] as String).toList();
    if (ids.isEmpty) return;
    try {
      final uid = _c.auth.currentUser!.id;
      final l = await _c
          .from('likes')
          .select('voice_id')
          .eq('user_id', uid)
          .inFilter('voice_id', ids);
      final r = await _c
          .from('reposts')
          .select('voice_id')
          .eq('user_id', uid)
          .inFilter('voice_id', ids);
      if (!mounted) return;
      setState(() {
        _liked = {for (final x in l) x['voice_id'] as String};
        _reposted = {for (final x in r) x['voice_id'] as String};
      });
    } catch (_) {}
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

  Future<void> _delete(Map<String, dynamic> v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this voice?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final id = v['id'] as String;
    await VoicePlayer.instance.stop();
    try {
      await _c.from('voices').delete().eq('id', id);
      try {
        await _c.storage.from('voices').remove([v['audio_path'] as String]);
      } catch (_) {}
      if (mounted) setState(() => _hidden.add(id));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete that voice')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = _c.auth.currentUser?.id;
    final items =
        widget.items.where((e) => !_hidden.contains(e['id'])).toList();
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            key: ValueKey(items[i]['id']),
            padding: const EdgeInsets.only(bottom: 16),
            child: FadeSlideIn(
              delay: Duration(milliseconds: (i < 6 ? i : 6) * 70),
              child: VoiceCard(
                v: items[i],
                liked: _liked.contains(items[i]['id']),
                reposted: _reposted.contains(items[i]['id']),
                onLike: () =>
                    _toggle('likes', items[i]['id'] as String, _liked),
                onRepost: () =>
                    _toggle('reposts', items[i]['id'] as String, _reposted),
                onReply: () => showCommentsSheet(context,
                    voiceId: items[i]['id'] as String,
                    ownerId: items[i]['user_id'] as String),
                onReport: () => showReportSheet(context,
                    type: 'voice', id: items[i]['id'] as String),
                onDelete: items[i]['user_id'] == me
                    ? () => _delete(items[i])
                    : null,
                onOpenProfile: items[i]['user_id'] == me
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => UserProfilePage(
                              userId: items[i]['user_id'] as String),
                        )),
              ),
            ),
          ),
      ],
    );
  }
}
