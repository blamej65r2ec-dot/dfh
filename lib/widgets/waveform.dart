import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../services/voice_player.dart';

/// Equal-width rounded bars stretched over the width (used for live bars).
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

final Map<String, List<double>> _barsCache = {};

/// Stable pseudo-random bar heights (0..1) from a seed. Cached.
List<double> barsFor(String seed, {int n = 44}) {
  return _barsCache.putIfAbsent('$seed#$n', () {
    final r = Random(seed.hashCode);
    return List<double>.unmodifiable(
        List.generate(n, (_) => 0.2 + 0.8 * r.nextDouble()));
  });
}

/// The design's bars: 4 px wide, 4 px gap, centred.
class FixedBarsPainter extends CustomPainter {
  FixedBarsPainter({
    required this.heights,
    required this.progress,
    required this.on,
    required this.off,
    this.barW = 4.0,
    this.gap = 4.0,
  });

  final List<double> heights;
  final double progress;
  final Color on;
  final Color off;
  final double barW;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final n = heights.length;
    if (n == 0) return;
    final total = n * barW + (n - 1) * gap;
    final x0 = (size.width - total) / 2;
    final pOn = Paint()..color = on;
    final pOff = Paint()..color = off;
    for (var i = 0; i < n; i++) {
      final h = heights[i];
      final x = x0 + i * (barW + gap);
      final y = (size.height - h) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, barW, h), Radius.circular(barW / 2)),
        (i + 0.5) / n <= progress ? pOn : pOff,
      );
    }
  }

  @override
  bool shouldRepaint(FixedBarsPainter old) => true;
}

/// The Voice component from the design.
/// Tap = play / pause. Drag = move through the voice. Press = small squeeze.
class VoiceWave extends StatefulWidget {
  const VoiceWave({
    super.key,
    required this.id,
    required this.audioPath,
    this.small = false,
  });

  final String id;
  final String audioPath;
  final bool small;

  @override
  State<VoiceWave> createState() => _VoiceWaveState();
}

class _VoiceWaveState extends State<VoiceWave>
    with SingleTickerProviderStateMixin {
  final _player = VoicePlayer.instance;
  final ValueNotifier<double> _t = ValueNotifier(0);
  late final Ticker _ticker;
  bool _press = false;
  bool _dragging = false;
  bool _wasPlaying = false;
  double _width = 1;

  bool get _active => _player.currentId.value == widget.id;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _t.value = d.inMilliseconds / 1000.0);
    _player.playing.addListener(_sync);
    _player.currentId.addListener(_sync);
    _sync();
  }

  void _sync() {
    final should = _active && _player.playing.value;
    if (should && !_ticker.isActive) _ticker.start();
    if (!should && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _player.playing.removeListener(_sync);
    _player.currentId.removeListener(_sync);
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  double _fractionAt(double dx) {
    final n = widget.small ? 22 : 28;
    final total = n * 8 - 4.0;
    final x0 = (_width - total) / 2;
    return ((dx - x0) / total).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final n = widget.small ? 22 : 28;
    final maxH = widget.small ? 30.0 : 56.0;
    const minH = 8.0;
    final seed = (widget.id.hashCode.abs() % 20 + 1).toDouble();
    final on = cs.onSurface;
    final off = dark
        ? const Color.fromRGBO(255, 255, 255, .3)
        : const Color.fromRGBO(0, 0, 0, .2);

    return LayoutBuilder(builder: (context, c) {
      _width = c.maxWidth;
      return AnimatedScale(
        scale: _press ? 0.96 : 1,
        duration: const Duration(milliseconds: 150),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _press = true),
          onTapCancel: () => setState(() => _press = false),
          onTapUp: (_) => setState(() => _press = false),
          onTap: () {
            HapticFeedback.selectionClick();
            _player.toggle(widget.id, widget.audioPath);
          },
          onHorizontalDragStart: (d) {
            if (!_active) return;
            _dragging = true;
            _wasPlaying = _player.playing.value;
            _player.pause();
            setState(() => _press = true);
            _player.seekFraction(_fractionAt(d.localPosition.dx));
          },
          onHorizontalDragUpdate: (d) {
            if (_dragging) _player.seekFraction(_fractionAt(d.localPosition.dx));
          },
          onHorizontalDragEnd: (_) {
            if (!_dragging) return;
            _dragging = false;
            setState(() => _press = false);
            if (_wasPlaying) _player.resume();
          },
          child: SizedBox(
            height: maxH + 8,
            width: double.infinity,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge(
                    [_player.currentId, _player.progress, _player.playing, _t]),
                builder: (context, _) {
                  final active = _active;
                  final playing = active && _player.playing.value;
                  final t = _t.value;
                  final hs = <double>[];
                  for (var i = 0; i < n; i++) {
                    final v = 0.45 * sin(i * 0.5 + seed).abs() +
                        0.55 * sin(i * 1.3 + seed * 2.1).abs();
                    final k = playing ? 0.8 + 0.3 * sin(t * 9 + i * 0.8) : 0.75;
                    hs.add(((minH + (maxH - minH) * v) * k)
                        .clamp(minH, maxH)
                        .toDouble());
                  }
                  return CustomPaint(
                    size: Size.infinite,
                    painter: FixedBarsPainter(
                      heights: hs,
                      progress: active ? _player.progress.value : 0,
                      on: on,
                      off: off,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    });
  }
}
