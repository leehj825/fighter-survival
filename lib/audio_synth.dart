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

  /// Plays the main theme throughout the app.
  /// If the track is already playing, it does nothing (prevents restart).
  static Future<void> playMainTheme() async {
    if (_musicPlayer.state == PlayerState.playing) {
      // Assuming we only play main2.mp3, if it's playing, we are good.
      // If we wanted to be stricter, we'd check the source, but AudioPlayer doesn't expose current source easily.
      // For this simple request, this is sufficient.
      return;
    }

    try {
      await _musicPlayer.stop();
      await _musicPlayer.setReleaseMode(ReleaseMode.loop);
      await _musicPlayer.setVolume(0.5);
      await _musicPlayer.setPlayerMode(PlayerMode.mediaPlayer);
      await _musicPlayer.play(AssetSource('audio/main2.mp3'));
    } catch (e) {
      print("Error playing music: $e");
    }
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
