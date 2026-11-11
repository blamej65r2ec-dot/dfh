import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/common.dart';
import '../services/voice_player.dart';
import 'avatar.dart';
import 'glass.dart';
import 'waveform.dart';

class VoiceCard extends StatelessWidget {
  const VoiceCard({
    required this.v,
    required this.liked,
    required this.reposted,
    required this.onLike,
    required this.onRepost,
    required this.onReport,
    this.onDelete,
    this.onOpenProfile,
  });

  final Map<String, dynamic> v;
  final bool liked;
  final bool reposted;
  final VoidCallback onLike;
  final VoidCallback onRepost;
  final VoidCallback onReport;
  final VoidCallback? onDelete;
  final VoidCallback? onOpenProfile;

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
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpenProfile,
                    child: Row(
                      children: [
                    Avatar(
                      name: nick.isNotEmpty ? nick : username,
                      path: profile['avatar_path'] as String?,
                      size: 42,
                    ),
                    const SizedBox(width: 12),
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
                      ],
                    ),
                  ),
                ),
                Text(moodOf(v['mood'] as String).emoji,
                    style: const TextStyle(fontSize: 30)),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz_rounded),
                  padding: EdgeInsets.zero,
                  onSelected: (a) {
                    if (a == 'report') onReport();
                    if (a == 'delete') onDelete?.call();
                  },
                  itemBuilder: (_) => [
                    if (onDelete != null)
                      const PopupMenuItem(value: 'delete', child: Text('Delete'))
                    else
                      const PopupMenuItem(value: 'report', child: Text('Report')),
                  ],
                ),
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
