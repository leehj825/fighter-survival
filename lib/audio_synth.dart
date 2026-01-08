import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

class AudioSynth {
  static final AudioPlayer _musicPlayer = AudioPlayer();
  static final Random _rng = Random();

  /// 1. Fix: Configure Global Audio Context to MIX sounds instead of pausing them
  static Future<void> initSystem() async {
    final AudioContext audioContext = AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.ambient, // Allow mixing
        options: {
          AVAudioSessionOptions.mixWithOthers,
          AVAudioSessionOptions.duckOthers
        },
      ),
      android: AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: false,
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.game,
        audioFocus: AndroidAudioFocus.none, // Do not request focus (prevents pausing)
      ),
    );
    await AudioPlayer.global.setAudioContext(audioContext);
  }

  /// Generates and plays the "Heroic" composed track
  static Future<void> startMusic() async {
    final musicBytes = _generateSequencedSong();

    await _musicPlayer.setReleaseMode(ReleaseMode.loop);
    await _musicPlayer.setVolume(0.4);
    // Use MediaPlayer mode for long music tracks to save CPU
    await _musicPlayer.setPlayerMode(PlayerMode.mediaPlayer);
    await _musicPlayer.play(BytesSource(musicBytes));
  }

  static void stopMusic() {
    _musicPlayer.stop();
  }

  // --- Optimized SFX ---

  static Future<void> playShoot({int variant = 0}) async {
    final player = AudioPlayer();
    // 2. Fix: Use Low Latency for SFX to avoid consuming heavy MediaPlayers
    await player.setPlayerMode(PlayerMode.lowLatency);

    double baseFreq = 800.0;
    double duration = 0.12;

    if (variant == 1) { baseFreq = 1200.0; duration = 0.08; } // High
    if (variant == 2) { baseFreq = 400.0; duration = 0.2; }   // Low

    final bytes = _generateWave((t) {
      double freq = baseFreq - (baseFreq * 0.8 * (t / duration));
      return (sin(2 * pi * freq * t) > 0) ? 0.3 : -0.3; // Square wave
    }, duration);

    await player.play(BytesSource(bytes));
    player.onPlayerComplete.listen((_) => player.dispose());
  }

  static Future<void> playExplosion({bool isLarge = false}) async {
    final player = AudioPlayer();
    await player.setPlayerMode(PlayerMode.lowLatency);

    double duration = isLarge ? 0.6 : 0.3;
    final bytes = _generateWave((t) {
      // Noise with decay
      return ((_rng.nextDouble() * 2) - 1) * pow(1.0 - (t / duration), 3);
    }, duration);

    await player.setVolume(0.5);
    await player.play(BytesSource(bytes));
    player.onPlayerComplete.listen((_) => player.dispose());
  }

  static Future<void> playPowerUp() async {
    final player = AudioPlayer();
    await player.setPlayerMode(PlayerMode.lowLatency);
    final bytes = _generateWave((t) {
      double freq = 400 + (t * 4000);
      return sin(2 * pi * freq * t) * 0.5;
    }, 0.5);
    await player.play(BytesSource(bytes));
    player.onPlayerComplete.listen((_) => player.dispose());
  }

  // --- Music Sequencer (The "Actual Music") ---

  static Uint8List _generateSequencedSong() {
    const int sampleRate = 22050;
    const double bpm = 160;
    const double beatDur = 60 / bpm; // ~0.375s
    const int totalBeats = 128; // 32 Bars

    return _createWav((totalBeats * beatDur * sampleRate).toInt(), sampleRate, (i) {
      double t = i / sampleRate;
      double beatPos = t / beatDur;
      int beatIndex = beatPos.floor();
      double localBeat = beatPos % 1.0;

      // --- PATTERN DEFINITIONS (MIDI Note Numbers) ---
      // 0 = Rest. 60 = C4 (Middle C)

      // BASSLINE (Repeat pattern)
      // C2(36) -> Bb1(34) -> Ab1(32) -> G1(31)
      int bar = (beatIndex ~/ 4) % 16;
      int bassNote = 36;
      if (bar >= 4 && bar < 8) bassNote = 34; // Bb
      if (bar >= 8 && bar < 12) bassNote = 32; // Ab
      if (bar >= 12) bassNote = 31; // G

      // MELODY (Simple Heroic Theme)
      int leadNote = 0;
      int localBarBeat = beatIndex % 16;

      // "Verse" Melody Pattern (Defined sequence)
      const List<int> melodyPattern = [
        60, 0, 60, 63,  67, 0, 63, 0,  // C C Eb G ... Eb
        65, 0, 65, 63,  62, 60, 58, 55 // F F Eb D C Bb G
      ];

      if (bar < 8) { // First half: Verse
         leadNote = melodyPattern[localBarBeat % melodyPattern.length];
      } else { // Second half: High Energy Arpeggios
         int chordRoot = bassNote + 24; // 2 octaves up
         int arpStep = beatIndex % 4;
         if (arpStep == 0) leadNote = chordRoot;
         if (arpStep == 1) leadNote = chordRoot + 3; // Minor 3rd
         if (arpStep == 2) leadNote = chordRoot + 7; // 5th
         if (arpStep == 3) leadNote = chordRoot + 12; // Octave
      }

      // --- MIXER ---
      double mix = 0.0;

      // 1. BASS (Square Wave)
      if (beatIndex % 1 == 0) {
         double freq = _midiToFreq(bassNote);
         double env = 1.0 - localBeat;
         mix += (sin(2 * pi * freq * t) > 0 ? 0.4 : -0.4) * env;
      }

      // 2. LEAD (Triangle Wave)
      if (leadNote > 0) {
        double freq = _midiToFreq(leadNote);
        mix += (asin(sin(2 * pi * freq * t)) * 2 / pi) * 0.3;
      }

      // 3. DRUMS
      bool isKick = (beatIndex % 2 == 0);
      double drumEnv = pow(1.0 - localBeat, 4).toDouble();
      if (isKick) {
        mix += sin(2 * pi * 80 * (1 - localBeat) * t) * drumEnv * 0.5;
      } else {
        mix += ((_rng.nextDouble() * 2) - 1) * drumEnv * 0.4;
      }

      return mix.clamp(-1.0, 1.0);
    });
  }

  static double _midiToFreq(int note) {
    return 440.0 * pow(2, (note - 69) / 12);
  }

  // --- WAV Helper ---
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

  static Uint8List _generateWave(double Function(double) generator, double duration) {
    const int rate = 22050;
    return _createWav((duration * rate).toInt(), rate, (i) => generator(i / rate));
  }
}
