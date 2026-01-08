import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

class AudioSynth {
  static final AudioPlayer _musicPlayer = AudioPlayer();
  static final Random _rng = Random();

  /// Generates and plays a 1-minute procedural song
  static Future<void> initMusic() async {
    // Generate ~51 seconds at 150 BPM (128 beats)
    // 22050Hz is sufficient for retro style and saves memory/CPU
    final musicBytes = _generateSongBuffer();

    await _musicPlayer.setReleaseMode(ReleaseMode.loop);
    await _musicPlayer.setVolume(0.35); // Background volume
    await _musicPlayer.play(BytesSource(musicBytes));
  }

  static void stopMusic() {
    _musicPlayer.stop();
  }

  // --- Sound Effects (Fire & Forget) ---

  /// Shoot sound with pitch variation
  /// variants: 0 = Normal, 1 = Power High, 2 = Heavy Low
  static Future<void> playShoot({int variant = 0}) async {
    final player = AudioPlayer();

    double baseFreq = 800.0;
    double duration = 0.14;

    // Random Variance (+/- 10%)
    double pitchVar = 0.9 + (_rng.nextDouble() * 0.2);

    if (variant == 1) { baseFreq = 1200.0; duration = 0.1; }
    if (variant == 2) { baseFreq = 400.0; duration = 0.25; }

    final bytes = _generateWave((t) {
      // Fast sweep down
      double freq = (baseFreq * pitchVar) - (baseFreq * 2.5 * (t / duration));
      if (freq < 100) freq = 100;
      // Pulse wave
      return (sin(2 * pi * freq * t) > 0.1) ? 0.5 : -0.5;
    }, duration);

    await player.play(BytesSource(bytes));
    player.onPlayerComplete.listen((_) => player.dispose());
  }

  static Future<void> playExplosion({bool isLarge = false}) async {
    final player = AudioPlayer();
    double duration = isLarge ? 0.8 : 0.4;

    final bytes = _generateWave((t) {
      // White noise with exponential decay
      double noise = (_rng.nextDouble() * 2.0) - 1.0;
      double decay = pow(1.0 - (t / duration), 2).toDouble();
      return noise * decay;
    }, duration);

    await player.setVolume(0.6);
    await player.play(BytesSource(bytes));
    player.onPlayerComplete.listen((_) => player.dispose());
  }

  static Future<void> playPowerUp() async {
    final player = AudioPlayer();
    final bytes = _generateWave((t) {
      // Ascending Arpeggio effect
      double freq = 400 + (t * 4000);
      return sin(2 * pi * freq * t) * 0.5;
    }, 0.5);
    await player.play(BytesSource(bytes));
    player.onPlayerComplete.listen((_) => player.dispose());
  }

  // --- Music Generator Logic ---

  static Uint8List _generateSongBuffer() {
    const int sampleRate = 22050;
    const double bpm = 140;
    const double beatDur = 60 / bpm; // ~0.42 seconds per beat
    const int totalBeats = 128; // ~54 seconds
    final int numSamples = (totalBeats * beatDur * sampleRate).toInt();

    // Frequencies for C Minor scale: C3, D3, Eb3, F3, G3, Ab3, Bb3, C4
    final scale = [130.8, 146.8, 155.6, 174.6, 196.0, 207.7, 233.1, 261.6];

    // Song Structure (Chord Progression Indices in Scale)
    // 0=C, 2=Eb, 4=G, 5=Ab, 6=Bb
    final progression = [
      0, 0, 0, 0, // Intro (C)
      5, 5, 6, 6, // Ab -> Bb
      0, 0, 2, 4, // C -> Eb -> G
      5, 4, 2, 0, // Ab -> G -> Eb -> C
    ]; // 16 blocks of 8 beats = 128 beats

    return _createWav(numSamples, sampleRate, (i) {
      double t = i / sampleRate;
      double beatPos = t / beatDur;
      int currentBeat = beatPos.floor();
      int measure = (currentBeat ~/ 8); // Change chord every 8 beats
      double localBeat = beatPos % 1.0;

      // 1. DETERMINE ROOT NOTE
      int chordIndex = progression[measure % progression.length];
      double rootFreq = scale[chordIndex % scale.length];

      // --- VOICE 1: BASS (Square Wave) ---
      // Plays on beats 0, 2, 4, 6... or distinct rhythm
      double bass = 0.0;
      double bassFreq = rootFreq / 2; // Octave down
      // Simple bass rhythm: Pum-Pum-Pum-Pum
      if (localBeat < 0.8) {
         bass = (sin(2 * pi * bassFreq * t) > 0) ? 0.6 : -0.6;
      }

      // --- VOICE 2: MELODY (Triangle Wave) ---
      double lead = 0.0;
      if (measure >= 4) { // Kick in after intro
        // Arpeggiator pattern based on beat
        int noteOffset = (currentBeat % 4) * 2; // 0, 2, 4, 6 (1-3-5-7 intervals)
        double leadFreq = scale[(chordIndex + noteOffset) % scale.length] * 2; // Octave up

        // Envelope: Short pluck
        double env = max(0, 1.0 - (localBeat * 3.0));
        // Vibrato
        leadFreq += sin(t * 15) * 5;
        lead = (asin(sin(2 * pi * leadFreq * t)) * 2 / pi) * env * 0.5;
      }

      // --- VOICE 3: DRUMS (Noise) ---
      double drum = 0.0;
      // Kick on 0, 2, 4... Snare on 1, 3, 5...
      bool isKick = (currentBeat % 2 == 0);
      double drumEnv = max(0, 1.0 - (localBeat * (isKick ? 4.0 : 8.0)));

      if (isKick) {
        // Low freq sine sweep + noise
        drum = sin(2 * pi * (100 - localBeat * 100) * t) * drumEnv * 0.8;
      } else {
        // Snare (White noise)
        drum = ((_rng.nextDouble() * 2) - 1) * drumEnv * 0.6;
      }

      // --- MIXER ---
      // Combine and clamp
      double mix = (bass * 0.4) + (lead * 0.3) + (drum * 0.3);
      return mix.clamp(-1.0, 1.0);
    });
  }

  // --- WAV Header Helper ---
  static Uint8List _generateWave(double Function(double) generator, double duration) {
    const int rate = 22050;
    return _createWav((duration * rate).toInt(), rate, (i) => generator(i / rate));
  }

  static Uint8List _createWav(int numSamples, int sampleRate, double Function(int) getSample) {
    final int fileSize = 36 + numSamples * 2;
    final ByteData header = ByteData(44);
    final List<int> pcmData = [];

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
      int val = (getSample(i) * 32767).toInt();
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
