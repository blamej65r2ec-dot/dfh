import 'dart:math';
import 'package:flutter/material.dart';

/// Equal-width rounded bars. Bars before [progress] are drawn solid.
class WaveformPainter extends CustomPainter {
  WaveformPainter({
    required this.bars,
    required this.progress,
    required this.color,
  });

  final List<double> bars;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final n = bars.length;
    if (n == 0) return;
    const gap = 3.0;
    final w = (size.width - gap * (n - 1)) / n;
    final played = Paint()..color = color;
    final rest = Paint()..color = color.withAlpha(70);
    for (var i = 0; i < n; i++) {
      final h = (bars[i] * size.height).clamp(4.0, size.height).toDouble();
      final x = i * (w + gap);
      final y = (size.height - h) / 2;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        Radius.circular(w / 2),
      );
      canvas.drawRRect(r, (i / n) < progress ? played : rest);
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      old.progress != progress || old.color != color || old.bars != bars;
}

/// Stable pseudo-random bar heights for a voice, based on its id.
List<double> barsFor(String seed, {int n = 44}) {
  final r = Random(seed.hashCode);
  return List.generate(n, (_) => 0.2 + 0.8 * r.nextDouble());
}
