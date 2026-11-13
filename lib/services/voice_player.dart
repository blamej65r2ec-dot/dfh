import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'activity.dart';

/// One shared player so only one voice plays at a time.
class VoicePlayer {
  VoicePlayer._();
  static final instance = VoicePlayer._();

  final AudioPlayer _p = AudioPlayer();
  final ValueNotifier<String?> currentId = ValueNotifier(null);
  final ValueNotifier<bool> playing = ValueNotifier(false);
  final ValueNotifier<double> progress = ValueNotifier(0);
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> duration = ValueNotifier(Duration.zero);

  /// Goes up by one every time a voice plays to the end.
  final ValueNotifier<int> finished = ValueNotifier(0);
  bool _ready = false;

  void _init() {
    if (_ready) return;
    _ready = true;
    _p.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        playing.value = false;
        progress.value = 0;
        position.value = Duration.zero;
        currentId.value = null;
        _p.pause();
        _p.seek(Duration.zero);
        finished.value++;
      } else {
        playing.value = s.playing;
      }
    });
    _p.durationStream.listen((d) {
      if (d != null) duration.value = d;
    });
    _p.positionStream.listen((pos) {
      final d = _p.duration;
      if (currentId.value == null) return;
      position.value = pos;
      if (d != null && d.inMilliseconds > 0) {
        progress.value =
            (pos.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0).toDouble();
      }
    });
  }

  Future<void> toggle(String id, String audioPath) async {
    _init();
    if (currentId.value == id) {
      if (_p.playing) {
        await _p.pause();
      } else {
        _p.play();
      }
      return;
    }
    currentId.value = id;
    progress.value = 0;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    Activity.recordView(id);
    try {
      final url = await Supabase.instance.client.storage
          .from('voices')
          .createSignedUrl(audioPath, 3600);
      await _p.setUrl(url);
      _p.play();
    } catch (_) {
      currentId.value = null;
      playing.value = false;
    }
  }

  /// Start a voice from the beginning (used by stories).
  Future<void> play(String id, String audioPath) async {
    _init();
    if (currentId.value == id) {
      await _p.seek(Duration.zero);
      _p.play();
      return;
    }
    await toggle(id, audioPath);
  }

  Future<void> pause() async {
    if (_ready) await _p.pause();
  }

  Future<void> resume() async {
    if (_ready && currentId.value != null) _p.play();
  }

  /// Move inside the current voice. [fraction] is 0..1.
  Future<void> seekFraction(double fraction) async {
    final d = _p.duration;
    if (!_ready || d == null || currentId.value == null) return;
    final f = fraction.clamp(0.0, 1.0).toDouble();
    progress.value = f;
    await _p.seek(Duration(milliseconds: (d.inMilliseconds * f).round()));
  }

  Future<void> stop() async {
    if (!_ready) return;
    await _p.stop();
    currentId.value = null;
    playing.value = false;
    progress.value = 0;
    position.value = Duration.zero;
  }
}
