import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

class AudioSynth {
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> playShoot() async {
    // Square wave: Sweep from 800Hz down to 200Hz
    final bytes = _generateWave((i, sampleRate) {
      double t = i / sampleRate;
      double freq = 800.0 - (3000.0 * t);
      if (freq < 100) freq = 100;
      return (sin(2 * pi * freq * t) > 0) ? 0.5 : -0.5;
    }, duration: 0.15);
    await _player.play(BytesSource(bytes));
  }

  static Future<void> playExplosion() async {
    // White noise with decay
    final Random rng = Random();
    final bytes = _generateWave((i, sampleRate) {
      return (rng.nextDouble() * 2.0) - 1.0;
    }, duration: 0.3, volumeDecay: true);
    await _player.play(BytesSource(bytes));
  }

  static Future<void> playPowerUp() async {
    // Sawtooth-ish sweep: 300Hz to 2000Hz
    final bytes = _generateWave((i, sampleRate) {
      double t = i / sampleRate;
      double freq = 300.0 + (2000.0 * t);
      return sin(2 * pi * freq * t);
    }, duration: 0.4);
    await _player.play(BytesSource(bytes));
  }

  static Uint8List _generateWave(double Function(int, int) generator, {required double duration, bool volumeDecay = false}) {
    const int sampleRate = 44100;
    final int numSamples = (duration * sampleRate).toInt();
    final int fileSize = 36 + numSamples * 2;
    final ByteData header = ByteData(44);
    final List<int> pcmData = [];

    // Construct WAV Header (RIFF, fmt, data)
    _writeString(header, 0, 'RIFF');
    header.setUint32(4, fileSize, Endian.little);
    _writeString(header, 8, 'WAVE');
    _writeString(header, 12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    _writeString(header, 36, 'data');
    header.setUint32(40, numSamples * 2, Endian.little);

    for (int i = 0; i < numSamples; i++) {
      double sample = generator(i, sampleRate);
      if (volumeDecay) sample *= (1.0 - (i / numSamples));
      int val = (sample.clamp(-1.0, 1.0) * 32767).toInt();
      pcmData.add(val & 0xFF);
      pcmData.add((val >> 8) & 0xFF);
    }

    final Uint8List result = Uint8List(44 + pcmData.length);
    result.setRange(0, 44, header.buffer.asUint8List());
    result.setRange(44, 44 + pcmData.length, pcmData);
    return result;
  }

  static void _writeString(ByteData data, int offset, String value) {
    for (int i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }
}
