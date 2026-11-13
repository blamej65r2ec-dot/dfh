import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/app_events.dart';
import '../services/common.dart';
import '../services/drafts.dart';
import '../services/voice_player.dart';
import '../services/wav.dart';
import '../widgets/animations.dart';
import '../widgets/glass.dart';
import 'post_details_page.dart';

/// Step 1 of posting: record, listen, cut. Then "Next".
class RecordPage extends StatefulWidget {
  const RecordPage({
    super.key,
    required this.onPosted,
    required this.onClose,
    this.storyMode = false,
  });

  final VoidCallback onPosted;
  final VoidCallback onClose;
  final bool storyMode;

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final _rec = AudioRecorder();
  final _preview = AudioPlayer();

  // The recording, as bars (one per 80 ms) and raw audio in a master file.
  final List<double> _bars = [];
  int? _cut; // bars from here on are "cut" (faded) until you record again
  File? _master;
  String? _legacyPath; // an old draft that cannot be edited
  int _legacyMs = 0;
  String? _draftId;
  String? _dMood;
  String _dCaption = '';
  String _dVis = 'public';
  String? _exportPath;

  bool _recording = false;
  bool _locked = false;
  double _lockP = 0;
  bool _pressActive = false;
  double _downY = 0;
  int _pressId = 0;
  int _segStartBar = 0;
  double _level = 0.1;
  Timer? _tick;
  StreamSubscription<Amplitude>? _amp;
  StreamSubscription<Duration>? _posSub;

  // waveform window
  int _viewStart = 0;
  int _visible = 39;
  double _acc = 0;
  double _playPos = -1; // in bars; -1 = not playing

  bool _busy = false;
  bool _previewPlaying = false;
  String? _previewKey;
  String? _error;
  int _storyHours = 24;
  bool _dirty = false;

  int get _effective => _cut ?? _bars.length;
  int get _ms => _legacyPath != null ? _legacyMs : _effective * 80;
  bool get _hasAudio => _legacyPath != null || _effective >= 8;

  @override
  void initState() {
    super.initState();
    _preview.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _preview.pause();
        _preview.seek(Duration.zero);
        _playPos = -1;
        _viewStart = max(0, _bars.length - _visible);
      }
      final pl = s.playing && s.processingState != ProcessingState.completed;
      if (mounted && (pl != _previewPlaying || _playPos == -1)) {
        setState(() => _previewPlaying = pl);
      }
    });
    _posSub = _preview
        .createPositionStream(
            minPeriod: const Duration(milliseconds: 40),
            maxPeriod: const Duration(milliseconds: 80))
        .listen((pos) {
      if (!_previewPlaying || !mounted) return;
      final p = pos.inMilliseconds / 80.0;
      // The wave follows the playing position.
      var vs = _viewStart;
      if (p < vs || p > vs + _visible - 3) {
        vs = max(0, min(p.floor() - 2, max(0, _bars.length - _visible)));
      }
      setState(() {
        _playPos = p;
        _viewStart = vs;
      });
    });
    DraftStore.pendingTick.addListener(_checkPending);
    _loadStoryHours();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPending());
  }

  void _checkPending() {
    final d = DraftStore.takePending();
    if (d != null) _loadDraft(d);
  }

  Future<void> _loadStoryHours() async {
    try {
      final c = Supabase.instance.client;
      final p = await c
          .from('profiles')
          .select('story_hours')
          .eq('id', c.auth.currentUser!.id)
          .single();
      if (mounted) setState(() => _storyHours = (p['story_hours'] as int?) ?? 24);
    } catch (_) {}
  }

  @override
  void dispose() {
    DraftStore.pendingTick.removeListener(_checkPending);
    AppEvents.pagingLocked.value = false;
    _tick?.cancel();
    _amp?.cancel();
    _posSub?.cancel();
    if (_recording) _rec.stop();
    // Leaving with audio you did not post: keep it as a draft.
    if (_dirty && _hasAudio) _autosaveDraft();
    _rec.dispose();
    _preview.dispose();
    super.dispose();
  }

  Future<void> _autosaveDraft() async {
    try {
      final exp = await _export();
      if (exp == null) return;
      await DraftStore.add(Draft(
        id: _draftId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        path: exp.$1,
        durationMs: exp.$2,
        mood: _dMood,
        caption: _dCaption,
        visibility: _dVis,
      ));
    } catch (_) {}
  }

  // ---------- files ----------

  Future<Directory> _dir() async {
    final d = await getApplicationDocumentsDirectory();
    final f = Directory('${d.path}/rec');
    await f.create(recursive: true);
    return f;
  }

  Future<File> _ensureMaster() async {
    if (_master != null) return _master!;
    final d = await _dir();
    final f =
        File('${d.path}/master_${DateTime.now().millisecondsSinceEpoch}.pcm');
    await f.writeAsBytes(const []);
    _master = f;
    return f;
  }

  Future<void> _truncateMaster(int bytes) async {
    final m = _master;
    if (m == null) return;
    final raf = await m.open(mode: FileMode.append);
    await raf.truncate(bytes);
    await raf.close();
  }

  /// Builds the final audio. Returns (path, milliseconds).
  Future<(String, int)?> _export() async {
    if (_legacyPath != null) return (_legacyPath!, _legacyMs);
    final m = _master;
    if (m == null || _effective < 1) return null;
    final have = await m.length();
    final bytes = min(have, _effective * kBytesPerBar);
    final d = await _dir();
    final out = await buildWav(m, bytes,
        '${d.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav');
    return (out.path, (bytes / kBytesPerBar * 80).round());
  }

  // ---------- recording ----------

  void _onDown(PointerDownEvent e) {
    if (_busy) return;
    if (_recording && _locked) {
      _stopRecording();
      return;
    }
    _downY = e.position.dy;
    _pressActive = true;
    AppEvents.pagingLocked.value = true;
    _beginRecording();
  }

  void _onMove(PointerMoveEvent e) {
    if (!_recording || _locked) return;
    final p = ((_downY - e.position.dy) / 70).clamp(0.0, 1.0).toDouble();
    if ((p - _lockP).abs() > 0.02) setState(() => _lockP = p);
    if (p >= 1) {
      HapticFeedback.mediumImpact();
      setState(() => _locked = true);
    }
  }

  void _onUp(PointerEvent e) {
    _pressActive = false;
    if (_recording && !_locked) _stopRecording();
    if (!_recording || !_locked) AppEvents.pagingLocked.value = false;
  }

  Future<void> _beginRecording() async {
    if (_recording) return;
    final id = ++_pressId;
    try {
      if (!await _rec.hasPermission()) {
        _pressActive = false;
        AppEvents.pagingLocked.value = false;
        setState(() => _error = 'Microphone permission is needed to record.');
        return;
      }
      if (!_pressActive || id != _pressId || !mounted) return;
      await _preview.stop();
      await VoicePlayer.instance.stop();

      if (_legacyPath != null) {
        // Old drafts cannot be edited: start fresh.
        _legacyPath = null;
        _bars.clear();
        _cut = null;
      }
      final master = await _ensureMaster();
      if (_cut != null) {
        await _truncateMaster(_cut! * kBytesPerBar);
        _bars.removeRange(_cut!, _bars.length);
        _cut = null;
      }
      final temp = await getTemporaryDirectory();
      final seg =
          '${temp.path}/seg_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: kSampleRate,
          numChannels: 1,
        ),
        path: seg,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _segStartBar = _bars.length;
      _level = 0.1;
      _amp = _rec
          .onAmplitudeChanged(const Duration(milliseconds: 60))
          .listen((a) {
        final v = ((a.current + 50) / 50).clamp(0.05, 1.0).toDouble();
        _level = max(v, _level * 0.6);
      });
      final startedAt = DateTime.now();
      _tick = Timer.periodic(const Duration(milliseconds: 80), (_) {
        final want = DateTime.now().difference(startedAt).inMilliseconds ~/ 80;
        while (_bars.length - _segStartBar < want) {
          _bars.add(8 + 52 * _level);
        }
        if (mounted) setState(() {});
      });
      _previewKey = null;
      _playPos = -1;
      setState(() {
        _recording = true;
        _locked = false;
        _lockP = 0;
        _error = null;
        _dirty = true;
      });
      _master = master;
      if (!_pressActive) _stopRecording();
    } catch (_) {
      AppEvents.pagingLocked.value = false;
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _tick?.cancel();
    await _amp?.cancel();
    AppEvents.pagingLocked.value = false;
    setState(() {
      _recording = false;
      _locked = false;
      _lockP = 0;
    });
    String? p;
    try {
      p = await _rec.stop();
    } catch (_) {}
    HapticFeedback.lightImpact();
    if (p == null) return;
    try {
      final raf = await _master!.open(mode: FileMode.append);
      final n = await appendPcm(File(p), raf);
      await raf.close();
      try {
        await File(p).delete();
      } catch (_) {}
      // Make the bars match the audio that was really saved.
      final target = _segStartBar + (n / kBytesPerBar).round();
      while (_bars.length > target) {
        _bars.removeLast();
      }
      while (_bars.length < target) {
        _bars.add(8);
      }
    } catch (_) {
      setState(() => _error = 'Could not save the recording. Try again.');
    }
    if (mounted) {
      setState(() => _viewStart = max(0, _bars.length - _visible));
    }
  }

  // ---------- cut, preview ----------

  /// Dragging moves the cut marker. When it reaches the left edge the voice
  /// slides, so you can go back to earlier parts. Drag right to bring it back.
  void _dragCut(double dx) {
    if (_recording || _bars.isEmpty || _previewPlaying) return;
    _acc += dx / 8.0;
    final steps = _acc.truncate();
    if (steps == 0) return;
    _acc -= steps;
    final len = _bars.length;
    final h = ((_cut ?? len) + steps).clamp(0, len);
    var vs = _viewStart;
    if (h - vs < 1) vs = max(0, h - 1);
    if (h - vs > _visible - 2) vs = h - (_visible - 2);
    vs = vs.clamp(0, max(0, len - _visible));
    final next = h >= len ? null : h;
    if (next != _cut || vs != _viewStart) {
      HapticFeedback.selectionClick();
      setState(() {
        _cut = next;
        _viewStart = vs;
        _previewKey = null;
      });
    }
  }

  Future<void> _togglePreview() async {
    if (_preview.playing) {
      await _preview.pause();
      return;
    }
    try {
      if (_legacyPath != null) {
        if (_previewKey != 'legacy') {
          await _preview.setFilePath(_legacyPath!);
          _previewKey = 'legacy';
        }
      } else {
        final key = '$_effective-${_bars.length}';
        if (_previewKey != key) {
          final temp = await getTemporaryDirectory();
          final f = await buildWav(
            _master!,
            min(await _master!.length(), _effective * kBytesPerBar),
            '${temp.path}/preview_${DateTime.now().millisecondsSinceEpoch}.wav',
          );
          await _preview.setFilePath(f.path);
          _previewKey = key;
        }
      }
      _preview.play();
    } catch (_) {
      setState(() => _error = 'Could not play the preview.');
    }
  }

  // ---------- actions ----------

  void _reset() {
    _bars.clear();
    _cut = null;
    final m = _master;
    _master = null;
    if (m != null) {
      m.delete().catchError((_) => m);
    }
    _legacyPath = null;
    _draftId = null;
    _dMood = null;
    _dCaption = '';
    _dVis = 'public';
    _previewKey = null;
    _exportPath = null;
    _dirty = false;
    _viewStart = 0;
    _playPos = -1;
    setState(() {
      _recording = false;
      _locked = false;
    });
  }

  Future<void> _loadDraft(Draft d) async {
    try {
      _reset();
      if (d.path.toLowerCase().endsWith('.wav')) {
        final master = await _ensureMaster();
        final raf = await master.open(mode: FileMode.write);
        await appendPcm(File(d.path), raf);
        await raf.close();
        final bars = await barsFromPcm(master, 0);
        _bars
          ..clear()
          ..addAll(bars);
      } else {
        _legacyPath = d.path;
        _legacyMs = d.durationMs;
      }
      _draftId = d.id;
      _dMood = d.mood;
      _dCaption = d.caption;
      _dVis = d.visibility;
      if (mounted) {
        setState(() => _viewStart = max(0, _bars.length - _visible));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open that draft.');
    }
  }

  Future<void> _next() async {
    if (!_hasAudio || _busy || _recording) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _preview.stop();
      final old = _exportPath;
      final exp = await _export();
      if (exp == null) throw Exception('nothing to post');
      if (old != null && old != exp.$1 && old != _legacyPath) {
        try {
          await File(old).delete();
        } catch (_) {}
      }
      _exportPath = exp.$1;
      if (!mounted) return;
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => PostDetailsPage(
            audioPath: exp.$1,
            durationMs: exp.$2,
            bars: _bars.sublist(0, _effective),
            storyMode: widget.storyMode,
            storyHours: _storyHours,
            draftId: _draftId,
            initialMood: _dMood,
            initialCaption: _dCaption,
            initialVisibility: _dVis,
          ),
        ),
      );
      if (result == 'posted') {
        try {
          await File(exp.$1).delete();
        } catch (_) {}
        _reset();
        AppEvents.notifyPosted();
        widget.onPosted();
      } else if (result == 'draft') {
        _reset();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Saved. Find it in Drafts on your profile.')));
        }
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    }
    if (mounted) setState(() => _busy = false);
  }

  // ---------- widgets ----------

  String get _hint {
    if (_recording) {
      return _locked
          ? 'Recording locked. Tap to stop.'
          : 'Release to stop. Slide up to lock.';
    }
    if (_previewPlaying) return 'Listening...';
    if (!_hasAudio) return 'Hold the button to record';
    if (_cut != null) return 'The faded part is removed when you record again';
    return 'Drag on the wave to cut the end';
  }

  Widget _waveBox() {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    return GlassBox(
      blur: false,
      radius: 28,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: SizedBox(
        height: 84,
        child: LayoutBuilder(builder: (context, c) {
          _visible = max(8, ((c.maxWidth + 4) / 8).floor());
          final start = _recording
              ? max(0, _bars.length - _visible)
              : _viewStart.clamp(0, max(0, _bars.length - _visible));
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => _acc = 0,
            onHorizontalDragUpdate: (d) => _dragCut(d.delta.dx),
            child: CustomPaint(
              size: Size(c.maxWidth, 84),
              painter: _RecWavePainter(
                bars: List<double>.of(_bars),
                start: start,
                cut: _cut,
                playPos: _playPos,
                showHandle:
                    !_recording && _bars.isNotEmpty && !_previewPlaying,
                on: cs.onSurface,
                off: dark
                    ? const Color.fromRGBO(255, 255, 255, .25)
                    : const Color.fromRGBO(0, 0, 0, .18),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _recordButton() {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 150,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            bottom: 96 + 46 * _lockP,
            child: AnimatedOpacity(
              opacity: _recording ? 0.25 + 0.75 * _lockP : 0,
              duration: const Duration(milliseconds: 120),
              child: GlassBox(
                blur: false,
                radius: 22,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    _locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerCancel: _onUp,
            child: AnimatedScale(
              scale: _recording ? 1.12 : 1,
              duration: const Duration(milliseconds: 180),
              child: GlassBox(
                radius: 44,
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: _recording ? 30 : 56,
                      height: _recording ? 30 : 56,
                      decoration: BoxDecoration(
                        color: cs.onSurface,
                        borderRadius:
                            BorderRadius.circular(_recording ? 8 : 28),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grey = cs.onSurface.withAlpha(150);
    final canNext = _hasAudio && !_busy && !_recording;
    return SafeArea(
      bottom: false,
      child: ListView(
        physics: _recording ? const NeverScrollableScrollPhysics() : null,
        padding: EdgeInsets.fromLTRB(20, 8, 20, pageBottomPad(context)),
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: widget.onClose,
                child: GlassBox(
                  radius: 23,
                  child: const SizedBox(
                    width: 46,
                    height: 46,
                    child: Icon(Icons.close_rounded, size: 22),
                  ),
                ),
              ),
              const Spacer(),
              if (widget.storyMode)
                GlassBox(
                  blur: false,
                  radius: 20,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Text('Story · ${_storyHours}h',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              fmtDuration(_previewPlaying && _playPos >= 0
                  ? (_playPos * 80).round()
                  : _ms),
              style: const TextStyle(
                fontSize: 52,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(_hint,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: grey)),
          ),
          const SizedBox(height: 18),
          _waveBox(),
          SizedBox(
            height: 46,
            child: Center(
              child: AnimatedOpacity(
                opacity: (_hasAudio && !_recording) ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: !(_hasAudio && !_recording),
                  child: GestureDetector(
                    onTap: _togglePreview,
                    child: GlassBox(
                      blur: false,
                      radius: 18,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              _previewPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 20),
                          const SizedBox(width: 4),
                          Text(_previewPlaying ? 'Pause' : 'Listen',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _recordButton(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Center(
                  child: Text(_error!, style: TextStyle(color: cs.error))),
            ),
          const SizedBox(height: 14),
          PressScale(
            child: GestureDetector(
              onTap: canNext ? _next : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(canNext ? 255 : 90),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: _busy
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: cs.onPrimary),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Next',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onPrimary)),
                          const SizedBox(width: 6),
                          Icon(Icons.arrow_forward_rounded,
                              size: 20, color: cs.onPrimary),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrolling bars, a cut marker you can drag, and a playhead while listening.
class _RecWavePainter extends CustomPainter {
  _RecWavePainter({
    required this.bars,
    required this.start,
    required this.cut,
    required this.playPos,
    required this.showHandle,
    required this.on,
    required this.off,
  });

  final List<double> bars;
  final int start;
  final int? cut;
  final double playPos;
  final bool showHandle;
  final Color on;
  final Color off;

  @override
  void paint(Canvas canvas, Size size) {
    final pOn = Paint()..color = on;
    final pMid = Paint()..color = on.withAlpha(120);
    final pOff = Paint()..color = off;
    final maxBars = ((size.width + 4) / 8).floor();
    final playing = playPos >= 0;
    for (var i = 0; i < maxBars; i++) {
      final idx = start + i;
      if (idx >= bars.length) break;
      final h = bars[idx].clamp(8.0, 60.0);
      final x = i * 8.0;
      final y = (size.height - h) / 2;
      final faded = cut != null && idx >= cut!;
      Paint paint;
      if (faded) {
        paint = pOff;
      } else if (playing) {
        paint = idx < playPos ? pOn : pMid;
      } else {
        paint = pOn;
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, 4, h), const Radius.circular(2)),
        paint,
      );
    }
    if (playing) {
      final px = ((playPos - start) * 8.0).clamp(0.0, size.width - 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(px, 0, 2, size.height), const Radius.circular(1)),
        pOn,
      );
    }
    if (showHandle) {
      final at = (cut ?? bars.length) - start;
      final hx = (at * 8.0 - 2).clamp(0.0, size.width - 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(hx, 2, 3, size.height - 4), const Radius.circular(2)),
        pOn,
      );
      canvas.drawCircle(Offset(hx + 1.5, size.height - 2), 5, pOn);
    }
  }

  @override
  bool shouldRepaint(_RecWavePainter old) => true;
}
