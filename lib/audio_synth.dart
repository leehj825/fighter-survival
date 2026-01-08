import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

class AudioSynth {
  static final AudioPlayer _sfxPlayer = AudioPlayer();
  static final AudioPlayer _musicPlayer = AudioPlayer();
  static final Random _rng = Random();

  /// Initialize and start background music
  static Future<void> initMusic() async {
    // Generate a 3.2-second loop (8 notes at 0.4s each)
    final musicBytes = _generateMusicLoop();

    await _musicPlayer.setReleaseMode(ReleaseMode.loop);
    await _musicPlayer.setVolume(0.4); // Lower volume for background
    await _musicPlayer.play(BytesSource(musicBytes));
  }

  static void stopMusic() {
    _musicPlayer.stop();
  }

  /// Play Shoot with slight randomization
  /// variation: 0 = Normal, 1 = High Pitch (Powerup), 2 = Low Pitch
  static Future<void> playShoot({int variant = 0}) async {
    double startFreq = 800.0;
    double endFreq = 200.0;
    double duration = 0.15;

    // Apply Random Variance
    double pitchMod = 1.0 + (_rng.nextDouble() * 0.2 - 0.1); // +/- 10%

    if (variant == 1) { // High / Laser
      startFreq = 1200.0;
      duration = 0.1;
    } else if (variant == 2) { // Heavy
      startFreq = 500.0;
      duration = 0.25;
    }

    final bytes = _generateWave((i, sampleRate) {
      double t = i / sampleRate;
      // Frequency Sweep
      double freq = (startFreq * pitchMod) - ((startFreq - endFreq) * (t / duration));
      if (freq < 100) freq = 100;

      // Square Wave with Duty Cycle
      return (sin(2 * pi * freq * t) > 0.2) ? 0.5 : -0.5;
    }, duration: duration);

    // Create a new player for overlapping SFX to avoid cutting off sounds
    final player = AudioPlayer();
    await player.play(BytesSource(bytes));
    player.onPlayerComplete.listen((_) => player.dispose());
  }

  /// Play Explosion with size variance
  static Future<void> playExplosion({bool isLarge = false}) async {
    double duration = isLarge ? 0.6 : 0.3;

    final bytes = _generateWave((i, sampleRate) {
      // White Noise
      return (_rng.nextDouble() * 2.0) - 1.0;
    }, duration: duration, volumeDecay: true);

    final player = AudioPlayer();
    await player.play(BytesSource(bytes));
    player.onPlayerComplete.listen((_) => player.dispose());
  }

  static Future<void> playPowerUp() async {
    // Sawtooth-ish sweep: 300Hz to 2000Hz
    final bytes = _generateWave((i, sampleRate) {
      double t = i / sampleRate;
      double freq = 300.0 + (2000.0 * t);
      return sin(2 * pi * freq * t);
    }, duration: 0.4);

    final player = AudioPlayer();
    await player.play(BytesSource(bytes));
    player.onPlayerComplete.listen((_) => player.dispose());
  }

  // --- Music Generation Logic ---
  static Uint8List _generateMusicLoop() {
    // Simple Arpeggio Sequence (C Minor: C, Eb, G, C)
    // Frequencies: C3=130, Eb3=155, G3=196, C4=261
    final List<double> notes = [130.81, 196.00, 155.56, 261.63, 130.81, 155.56, 196.00, 261.63];
    const double noteDuration = 0.25; // seconds per note
    const double totalDuration = noteDuration * 8;

    return _generateWave((i, sampleRate) {
      double t = i / sampleRate;

      // Determine which note we are on
      int noteIndex = (t / noteDuration).floor() % notes.length;
      double freq = notes[noteIndex];

      // Bassline (Square Wave)
      double signal = (sin(2 * pi * freq * t) > 0) ? 0.4 : -0.4;

      // Add a simple "Hi-hat" noise every off-beat
      if ((t % 0.5) > 0.45) {
        signal += (_rng.nextDouble() * 0.5 - 0.25);
      }

      return signal;
    }, duration: totalDuration, volumeDecay: false);
  }

  // --- Core Waveform Generator ---
  static Uint8List _generateWave(double Function(int, int) generator, {required double duration, bool volumeDecay = false}) {
    const int sampleRate = 22050; // Lower sample rate for retro feel & performance
    final int numSamples = (duration * sampleRate).toInt();
    final int fileSize = 36 + numSamples * 2;
    final ByteData header = ByteData(44);
    final List<int> pcmData = [];

    // Header
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
      if (volumeDecay) {
        sample *= (1.0 - (i / numSamples)); // Linear fade out
      }
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
