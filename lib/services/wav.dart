import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Editing audio (cut and record again) is done on raw 16 kHz mono audio.
const kSampleRate = 16000;

/// 80 ms of audio: one bar of the waveform.
const kBytesPerBar = 2560;

Future<int> wavDataOffset(File f) async {
  final raf = await f.open();
  try {
    final head = await raf.read(512);
    for (var i = 12; i + 8 <= head.length; i++) {
      if (head[i] == 0x64 &&
          head[i + 1] == 0x61 &&
          head[i + 2] == 0x74 &&
          head[i + 3] == 0x61) {
        return i + 8;
      }
    }
  } finally {
    await raf.close();
  }
  return 44;
}

/// Appends the raw audio of a WAV file to [out]. Returns the bytes written.
Future<int> appendPcm(File wav, RandomAccessFile out) async {
  final off = await wavDataOffset(wav);
  final len = await wav.length();
  if (len <= off) return 0;
  var written = 0;
  await for (final chunk in wav.openRead(off)) {
    await out.writeFrom(chunk);
    written += chunk.length;
  }
  return written;
}

Uint8List _header(int dataLen) {
  final b = ByteData(44);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + dataLen, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, kSampleRate, Endian.little);
  b.setUint32(28, kSampleRate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  b.setUint32(40, dataLen, Endian.little);
  return b.buffer.asUint8List();
}

/// Writes a playable WAV file from the first [byteLen] bytes of [pcm].
Future<File> buildWav(File pcm, int byteLen, String outPath) async {
  final out = File(outPath);
  final sink = out.openWrite();
  sink.add(_header(byteLen));
  if (byteLen > 0) {
    await for (final chunk in pcm.openRead(0, byteLen)) {
      sink.add(chunk);
    }
  }
  await sink.close();
  return out;
}

/// Bar heights (8..60) from raw audio, one bar per 80 ms.
Future<List<double>> barsFromPcm(File f, int offset) async {
  final out = <double>[];
  final raf = await f.open();
  try {
    await raf.setPosition(offset);
    while (true) {
      final b = await raf.read(kBytesPerBar);
      final n = b.length ~/ 2;
      if (n == 0) break;
      final bd = ByteData.sublistView(b);
      var sum = 0.0;
      for (var i = 0; i < n; i++) {
        final v = bd.getInt16(i * 2, Endian.little);
        sum += v * v;
      }
      final rms = sqrt(sum / n) / 32768.0;
      out.add(8 + 52 * min(1.0, rms * 6));
      if (b.length < kBytesPerBar) break;
    }
  } finally {
    await raf.close();
  }
  return out;
}
