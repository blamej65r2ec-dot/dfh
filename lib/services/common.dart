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
  Mood('thinking', '💭', 'Thinking'),
  Mood('frustrated', '🔥', 'Fired up'),
  Mood('calm', '🤍', 'Calm'),
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

String fmtClock(DateTime t) {
  final l = t.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final m = l.minute.toString().padLeft(2, '0');
  return '$h:$m ${l.hour < 12 ? 'AM' : 'PM'}';
}

String dayLabel(DateTime t) {
  final l = t.toLocal();
  final now = DateTime.now();
  bool same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  if (same(l, now)) return 'Today';
  if (same(l, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  const mon = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${l.day} ${mon[l.month - 1]}';
}
