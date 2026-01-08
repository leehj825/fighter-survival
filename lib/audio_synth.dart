import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

class AudioSynth {
  static final AudioPlayer _musicPlayer = AudioPlayer();
  static final Random _rng = Random();

  /// Initialize Audio Context to allow MIXING (Fixes SFX blocking)
  static Future<void> initSystem() async {
    final AudioContext audioContext = AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.ambient,
        options: {AVAudioSessionOptions.mixWithOthers, AVAudioSessionOptions.duckOthers},
      ),
      android: AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: false,
        contentType: AndroidContentType.music,
        usageType: AndroidUsageType.game,
        audioFocus: AndroidAudioFocus.none, // Vital: prevents taking exclusive focus
      ),
    );
    await AudioPlayer.global.setAudioContext(audioContext);
  }

  // --- Music Control ---

  static Future<void> playMenuMusic() async {
    // Check if already playing (optional optimization)
    if (_musicPlayer.state == PlayerState.playing) return;

    await _startLoop('audio/main2.mp3', volume: 0.5);
  }

  static Future<void> playGameMusic() async {
    await _startLoop('audio/menu2.mp3', volume: 0.4);
  }

  static Future<void> _startLoop(String assetPath, {required double volume}) async {
    await _musicPlayer.stop(); // Stop current track
    await _musicPlayer.setReleaseMode(ReleaseMode.loop);
    await _musicPlayer.setVolume(volume);
    await _musicPlayer.setPlayerMode(PlayerMode.mediaPlayer);
    await _musicPlayer.play(AssetSource(assetPath));
  }

  static void stopMusic() {
    _musicPlayer.stop();
  }

  // --- SFX (Fire & Forget) ---

  static Future<void> playShoot({int variant = 0}) async {
    // Create new player for every shot to ensure polyphony
    final player = AudioPlayer();
    await player.setPlayerMode(PlayerMode.lowLatency);

    double baseFreq = 800.0;
    double duration = 0.12;
    if (variant == 1) { baseFreq = 1200.0; duration = 0.08; } // High
    if (variant == 2) { baseFreq = 300.0; duration = 0.2; }   // Low

    final bytes = _generateWave((t) {
      // Pulse Wave Sweep
      double freq = baseFreq - (baseFreq * 0.8 * (t / duration));
      return (sin(2 * pi * freq * t) > 0) ? 0.25 : -0.25;
    }, duration);

    await player.play(BytesSource(bytes));
    player.onPlayerComplete.listen((_) => player.dispose());
  }

  static Future<void> playExplosion({bool isLarge = false}) async {
    final player = AudioPlayer();
    await player.setPlayerMode(PlayerMode.lowLatency);

    double duration = isLarge ? 0.8 : 0.4;
    final bytes = _generateWave((t) {
      // White Noise + Low Pass Filter Simulation (Simple Decay)
      return ((_rng.nextDouble() * 2) - 1) * pow(1.0 - (t / duration), 2);
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

  // --- Advanced Music Sequencer ---

  static Uint8List _generateSequencedSong({required bool isGameTrack}) {
    const int sampleRate = 22050;
    // Game: Fast (150 BPM), Menu: March (120 BPM)
    final double bpm = isGameTrack ? 150 : 120;
    final double beatDur = 60 / bpm;
    // 32 bars * 4 beats = 128 beats
    const int totalBeats = 128;

    return _createWav((totalBeats * beatDur * sampleRate).toInt(), sampleRate, (i) {
      double t = i / sampleRate;
      double beatPos = t / beatDur;
      int beatIndex = beatPos.floor();
      double localBeat = beatPos % 1.0;
      int bar = (beatIndex ~/ 4) % 16;

      double mix = 0.0;

      // -----------------------------
      // TRACK 1: THE MENU "HEROIC" THEME
      // -----------------------------
      if (!isGameTrack) {
        // Bass (C -> Bb -> Ab -> G)
        int bassNote = 36; // C2
        if (bar >= 4 && bar < 8) bassNote = 34; // Bb
        if (bar >= 8 && bar < 12) bassNote = 32; // Ab
        if (bar >= 12) bassNote = 31; // G

        // Melody Pattern (Simple March)
        int leadNote = 0;
        int step = beatIndex % 16;
        if (bar < 8) {
           const melody = [60,0,60,63, 67,0,63,0, 65,0,65,63, 62,60,58,55];
           leadNote = melody[step % melody.length];
        } else {
           // Arpeggio part
           int root = bassNote + 24;
           if (step % 2 == 0) leadNote = root; // 8th notes
           else leadNote = root + 7; // Fifth
        }

        // Synthesis
        // Bass: Square
        if (beatIndex % 1 == 0) {
           mix += (sin(2 * pi * _midiToFreq(bassNote) * t) > 0 ? 0.3 : -0.3) * (1 - localBeat);
        }
        // Lead: Triangle
        if (leadNote > 0) {
           mix += (asin(sin(2 * pi * _midiToFreq(leadNote) * t)) * 2 / pi) * 0.3;
        }
        // Drums: Marching Snare
        if (beatIndex % 2 == 0) { // Kick
           mix += sin(2 * pi * 80 * (1-localBeat) * t) * pow(1-localBeat, 4) * 0.5;
        } else { // Snare
           mix += ((_rng.nextDouble()*2)-1) * pow(1-localBeat, 2) * 0.3;
        }
      }

      // -----------------------------
      // TRACK 2: THE GAME "CYBERPUNK" THEME (More Sophisticated)
      // -----------------------------
      else {
        // Harmony: Driving minor progression (C -> Eb -> F -> G)
        // 16th note Arpeggios
        double subBeat = (beatPos % 1.0) * 4; // 0..4
        int sixteenth = subBeat.floor(); // 0,1,2,3

        int root = 36; // C2
        if (bar >= 4 && bar < 8) root = 39; // Eb
        if (bar >= 8 && bar < 12) root = 41; // F
        if (bar >= 12) root = 43; // G

        // 1. FAST BASS (Off-beat "Transistor" Bass)
        // Plays on the "and" of the beat
        if (localBeat > 0.5) {
          double env = 1.0 - ((localBeat - 0.5) * 2);
          double freq = _midiToFreq(root);
          // Sawtooth-ish approximation
          double wave = (t * freq) % 1.0;
          mix += (wave * 2 - 1) * env * 0.5;
        }

        // 2. LEAD ARPEGGIO (Plucky Sine/Square hybrid)
        // Pattern: Root, +3, +7, +12 (Minor 7th arp)
        int arpNote = root + 24; // Up 2 octaves
        if (sixteenth == 1) arpNote += 3;
        if (sixteenth == 2) arpNote += 7;
        if (sixteenth == 3) arpNote += 10;

        // Envelope is very short (Pluck)
        double pluckEnv = max(0, 1.0 - (subBeat % 1.0) * 2.0);
        mix += (sin(2 * pi * _midiToFreq(arpNote) * t) > 0.5 ? 0.3 : -0.3) * pluckEnv * 0.25;

        // 3. PAD / ATMOSPHERE (Slow attack detuned saws)
        // Long chords
        double padFreq = _midiToFreq(root + 12);
        double detune = t * 2; // Slow phase shift
        mix += sin(2 * pi * (padFreq + 2) * t) * 0.1;
        mix += sin(2 * pi * (padFreq - 2) * t) * 0.1;

        // 4. DRUMS (Techno Beat)
        // Kick on 0, 1, 2, 3 (Four on floor)
        double kickEnv = pow(1.0 - localBeat, 8).toDouble();
        mix += sin(2 * pi * (120 - localBeat * 120) * t) * kickEnv * 0.7;

        // Hi-Hats (16th notes, closed/open)
        bool openHat = (beatIndex % 2 == 1 && sixteenth == 2); // Off-beat open
        double hatEnv = max(0, 1.0 - (subBeat % 1.0) * (openHat ? 2.0 : 8.0));
        mix += ((_rng.nextDouble()*2)-1) * hatEnv * 0.15;
      }

      return mix.clamp(-1.0, 1.0);
    });
  }

  static double _midiToFreq(int note) {
    return 440.0 * pow(2, (note - 69) / 12);
  }

  // --- WAV Helper ---
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
    for (int i = 0; i < value.length; i++) data.setUint8(offset + i, value.codeUnitAt(i));
  }
}
