import 'package:flutter/widgets.dart';

class Mood {
  const Mood(this.key, this.emoji, this.label);
  final String key;
  final String emoji;
  final String label;
}

// Temporary emojis until you design your own.
const moods = [
  Mood('happy', '😊', 'Happy'),
  Mood('sad', '😔', 'Sad'),
  Mood('funny', '😂', 'Funny'),
  Mood('help', '🆘', 'Need help'),
  Mood('thinking', '🤔', 'Thinking'),
  Mood('frustrated', '😤', 'Frustrated'),
  Mood('calm', '😌', 'Calm'),
];

Mood moodOf(String key) =>
    moods.firstWhere((m) => m.key == key, orElse: () => moods.first);

String fmtDuration(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String greeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Good night';
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  if (h < 21) return 'Good evening';
  return 'Good night';
}

/// Bottom padding for scrolling pages: room for the floating nav bar,
/// or just above the keyboard while it is open.
double pageBottomPad(BuildContext context) {
  final m = MediaQuery.of(context);
  final kb = m.viewInsets.bottom;
  return kb > 0 ? kb + 24 : 130 + m.padding.bottom;
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t.toLocal());
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return '${(d.inDays / 7).floor()}w';
}
