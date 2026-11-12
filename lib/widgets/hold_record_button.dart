import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/common.dart';
import '../services/voice_player.dart';
import 'waveform.dart';

/// Big pill: hold to record, release to send, slide left to cancel.
class HoldRecordButton extends StatefulWidget {
  const HoldRecordButton({
    super.key,
    required this.onRecorded,
    this.label = 'Hold to record',
    this.icon = Icons.mic_none_rounded,
  });

  /// Called with the audio file and its length in milliseconds.
  final Future<void> Function(String path, int ms) onRecorded;
  final String label;
  final IconData icon;

  @override
  State<HoldRecordButton> createState() => _HoldRecordButtonState();
}

class _HoldRecordButtonState extends State<HoldRecordButton> {
  final _rec = AudioRecorder();
  final _watch = Stopwatch();
  final ValueNotifier<bool> _recording = ValueNotifier(false);
  final ValueNotifier<bool> _cancel = ValueNotifier(false);
  final ValueNotifier<int> _elapsed = ValueNotifier(0);
  final ValueNotifier<List<double>> _levels =
      ValueNotifier(List<double>.filled(20, 0.1));
  Timer? _tick;
  StreamSubscription<Amplitude>? _amp;
  int _pressId = 0;
  bool _down = false;
  bool _busy = false;
  double _downX = 0;
  String? _path;

  @override
  void dispose() {
    _tick?.cancel();
    _amp?.cancel();
    _rec.dispose();
    _recording.dispose();
    _cancel.dispose();
    _elapsed.dispose();
    _levels.dispose();
    super.dispose();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t)));
  }

  void _onDown(PointerDownEvent e) {
    if (_busy) return;
    _downX = e.position.dx;
    _down = true;
    _begin();
  }

  void _onMove(PointerMoveEvent e) {
    if (!_recording.value) return;
    final c = e.position.dx - _downX < -90;
    if (c != _cancel.value) {
      _cancel.value = c;
      if (c) HapticFeedback.selectionClick();
    }
  }

  void _onUp(PointerEvent e) {
    _down = false;
    if (_recording.value) _finish();
  }

  Future<void> _begin() async {
    if (_recording.value) return;
    final id = ++_pressId;
    try {
      if (!await _rec.hasPermission()) {
        _down = false;
        _snack('Microphone permission is needed to record.');
        return;
      }
      if (!_down || id != _pressId || !mounted) return;
      await VoicePlayer.instance.stop();
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/rep_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        const RecordConfig(
            encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100),
        path: path,
      );
      if (!mounted) return;
      _path = path;
      HapticFeedback.mediumImpact();
      _watch
        ..reset()
        ..start();
      _elapsed.value = 0;
      _levels.value = List<double>.filled(20, 0.1);
      _cancel.value = false;
      _tick = Timer.periodic(const Duration(milliseconds: 100),
          (_) => _elapsed.value = _watch.elapsedMilliseconds);
      _amp = _rec
          .onAmplitudeChanged(const Duration(milliseconds: 90))
          .listen((a) {
        final v = ((a.current + 50) / 50).clamp(0.1, 1.0).toDouble();
        _levels.value = List<double>.of(_levels.value)
          ..removeAt(0)
          ..add(v);
      });
      _recording.value = true;
      if (!_down) _finish();
    } catch (_) {
      _recording.value = false;
    }
  }

  Future<void> _finish() async {
    if (!_recording.value) return;
    _recording.value = false;
    _tick?.cancel();
    await _amp?.cancel();
    _watch.stop();
    final ms = _watch.elapsedMilliseconds;
    final cancel = _cancel.value;
    _cancel.value = false;
    String? p;
    try {
      p = await _rec.stop();
    } catch (_) {}
    p ??= _path;
    if (p == null) return;
    if (cancel || ms < 700) {
      try {
        await File(p).delete();
      } catch (_) {}
      if (!cancel) _snack('Hold to record');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      await widget.onRecorded(p, ms);
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: ValueListenableBuilder<bool>(
        valueListenable: _recording,
        builder: (context, rec, _) => ValueListenableBuilder<bool>(
          valueListenable: _cancel,
          builder: (context, cancel, _) {
            final bg = cancel ? cs.error : cs.primary;
            final fg = cancel ? cs.onError : cs.onPrimary;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(28),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: _busy
                    ? Center(
                        key: const ValueKey('busy'),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: fg),
                        ),
                      )
                    : rec
                        ? Row(
                            key: const ValueKey('rec'),
                            children: [
                              ValueListenableBuilder<int>(
                                valueListenable: _elapsed,
                                builder: (context, ms, _) => Text(
                                  fmtDuration(ms),
                                  style: TextStyle(
                                      color: fg,
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: cancel
                                    ? Text('Release to cancel',
                                        style: TextStyle(
                                            color: fg,
                                            fontWeight: FontWeight.w700))
                                    : ValueListenableBuilder<List<double>>(
                                        valueListenable: _levels,
                                        builder: (context, lv, _) => SizedBox(
                                          height: 28,
                                          child: CustomPaint(
                                            size: Size.infinite,
                                            painter: WaveformPainter(
                                                bars: lv,
                                                progress: 1,
                                                color: fg),
                                          ),
                                        ),
                                      ),
                              ),
                              if (!cancel) ...[
                                const SizedBox(width: 10),
                                Icon(Icons.chevron_left_rounded,
                                    color: fg.withAlpha(170), size: 18),
                                Text('Cancel',
                                    style: TextStyle(
                                        color: fg.withAlpha(170),
                                        fontSize: 12)),
                              ],
                            ],
                          )
                        : Row(
                            key: const ValueKey('idle'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(widget.icon, color: fg, size: 22),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  widget.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: fg,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
              ),
            );
          },
        ),
      ),
    );
  }
}
