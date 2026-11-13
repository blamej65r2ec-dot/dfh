import 'package:flutter/material.dart';

import '../services/common.dart';
import 'avatar.dart';
import 'glass.dart';
import 'waveform.dart';

/// A voice post, as in the design.
class VoiceCard extends StatelessWidget {
  const VoiceCard({
    super.key,
    required this.v,
    required this.liked,
    required this.reposted,
    required this.onLike,
    required this.onRepost,
    required this.onReply,
    required this.onReport,
    required this.saved,
    required this.onSave,
    this.counts,
    this.onDelete,
    this.onOpenProfile,
  });

  final Map<String, dynamic> v;
  final bool liked;
  final bool reposted;
  final VoidCallback onLike;
  final VoidCallback onRepost;
  final VoidCallback onReply;
  final VoidCallback onReport;
  final bool saved;
  final VoidCallback onSave;

  /// likes, replies, reposts. Only given for your own voices.
  final List<int>? counts;
  final VoidCallback? onDelete;
  final VoidCallback? onOpenProfile;

  Future<void> _actions(BuildContext context) async {
    final mine = onDelete != null;
    final a = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(12),
        child: GlassBox(
          radius: 32,
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
                mine ? Icons.delete_outline_rounded : Icons.flag_outlined),
            title: Text(mine ? 'Delete this voice' : 'Report this voice'),
            onTap: () => Navigator.of(ctx).pop(mine ? 'delete' : 'report'),
          ),
        ),
      ),
    );
    if (a == 'delete') onDelete?.call();
    if (a == 'report') onReport();
  }

  Widget _action(BuildContext context, IconData off, IconData on, bool active,
      VoidCallback tap,
      {int? count}) {
    final cs = Theme.of(context).colorScheme;
    final color = active ? cs.onSurface : cs.onSurface.withAlpha(150);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: tap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Icon(active ? on : off,
                  key: ValueKey(active), size: 24, color: color),
            ),
            if (count != null) ...[
              const SizedBox(width: 5),
              Text('$count',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withAlpha(170))),
            ],
          ],
        ),
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
    final when = DateTime.tryParse(v['created_at'] as String? ?? '');
    final name = nick.isNotEmpty ? nick : '@$username';

    return GlassBox(
      blur: false,
      radius: 30,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpenProfile,
            onLongPress: () => _actions(context),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.onSurface, width: 2),
                  ),
                  child: ClipOval(
                    child: Avatar(
                      name: name,
                      path: profile['avatar_path'] as String?,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 16)),
                      Text(
                        '@$username${when != null ? ' · ${timeAgo(when)}' : ''}',
                        style: TextStyle(
                            fontSize: 13, color: cs.onSurface.withAlpha(150)),
                      ),
                    ],
                  ),
                ),
                Text(moodOf(v['mood'] as String).emoji,
                    style: const TextStyle(fontSize: 28)),
              ],
            ),
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(caption, style: const TextStyle(fontSize: 15, height: 1.45)),
          ],
          const SizedBox(height: 12),
          VoiceWave(id: id, audioPath: v['audio_path'] as String),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _action(context, Icons.favorite_border_rounded,
                  Icons.favorite_rounded, liked, onLike,
                  count: counts?[0]),
              _action(context, Icons.mode_comment_outlined,
                  Icons.mode_comment_outlined, false, onReply,
                  count: counts?[1]),
              _action(context, Icons.repeat_rounded, Icons.repeat_on_rounded,
                  reposted, onRepost,
                  count: counts?[2]),
              _action(context, Icons.bookmark_border_rounded,
                  Icons.bookmark_rounded, saved, onSave),
            ],
          ),
        ],
      ),
    );
  }
}
