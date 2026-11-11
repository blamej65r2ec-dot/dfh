import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One shared player so only one voice plays at a time.
class VoicePlayer {
  VoicePlayer._();
  static final instance = VoicePlayer._();

  final AudioPlayer _p = AudioPlayer();
  final ValueNotifier<String?> currentId = ValueNotifier(null);
  final ValueNotifier<bool> playing = ValueNotifier(false);
  final ValueNotifier<double> progress = ValueNotifier(0);
  bool _ready = false;

  void _init() {
    if (_ready) return;
    _ready = true;
    _p.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        playing.value = false;
        progress.value = 0;
        currentId.value = null;
        _p.pause();
        _p.seek(Duration.zero);
      } else {
        playing.value = s.playing;
      }
    });
    _p.positionStream.listen((pos) {
      final d = _p.duration;
      if (d != null && d.inMilliseconds > 0 && currentId.value != null) {
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

  Future<void> stop() async {
    if (!_ready) return;
    await _p.stop();
    currentId.value = null;
    playing.value = false;
    progress.value = 0;
  }
}
