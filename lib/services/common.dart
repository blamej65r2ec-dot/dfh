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
