import 'dart:async';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

/// Service for managing game audio (sound effects and background music)
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;

  /// Public static getter for singleton instance
  static SoundService get instance => _instance;

  SoundService._internal() {
    _settingsLoadCompleter = Completer<void>();
  }

  // Instantiate players after configuring global audio context so they inherit
  // the configured mixing/audio-focus behavior. Using `late final` ensures
  // they're created once during initialization.
  late final AudioPlayer _backgroundMusicPlayer;

  // SFX Pool
  final List<AudioPlayer> _sfxPool = [];
  static const int _maxSfxPlayers = 8;
  int _poolIndex = 0;

  final bool _isMusicEnabled = true;
  final bool _isSoundEnabled = true;
  bool _isMusicOperationInProgress = false; // Prevent concurrent music operations
  final double _musicVolume = AppConfig.menuMusicVolume; // Base music volume
  double _soundVolumeMultiplier = AppConfig.soundVolumeMultiplier; // Overall sound effects multiplier (player adjustable)
  double _musicVolumeMultiplier = AppConfig.musicVolumeMultiplier; // Overall music multiplier (player adjustable)
  String? _currentMusicPath; // Track what music is currently playing
  DateTime? _lastMusicStartTime; // Track when music was last started (to prevent immediate stops)
  int _fadeGeneration = 0; // Cancels an in-flight fade when volume changes
  bool _wasPlayingBeforePause = false; // Track if music was playing before app was paused
  Completer<void>? _settingsLoadCompleter; // Completer to track when settings are loaded

  // New unified initialization sequence
  Future<void> init() async {
    // 1. FIRST: Configure Audio Context and WAIT for it to finish
    await _initAudioContext();

    // 2. Initialize SFX Pool
    await _initSfxPool();

    // 3. THEN: Load settings and complete the completer
    await _loadVolumeSettings();
  }

  Future<void> _initSfxPool() async {
    for (int i = 0; i < 4; i++) {
        final player = AudioPlayer();
        await player.setPlayerMode(PlayerMode.lowLatency);
        _sfxPool.add(player);
    }
  }

  Future<AudioPlayer> _getSfxPlayer() async {
    // 1. Try to find a free player (not playing)
    for (final player in _sfxPool) {
      if (player.state != PlayerState.playing) {
        return player;
      }
    }

    // 2. If all busy, expand pool if below limit
    if (_sfxPool.length < _maxSfxPlayers) {
       final player = AudioPlayer();
       await player.setPlayerMode(PlayerMode.lowLatency);
       _sfxPool.add(player);
       return player;
    }

    // 3. Fallback: Round-robin steal
    _poolIndex = (_poolIndex + 1) % _sfxPool.length;
    return _sfxPool[_poolIndex];
  }

  /// Initialize audio context to allow mixing with other sounds
  Future<void> _initAudioContext() async {
    try {
      // Configure audio context to allow mixing with other apps (like YouTube)
      // This prevents the game from stopping background music when sounds play
      final audioContext = AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: false,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.game, // Reverted to 'game' for better compatibility
          audioFocus: AndroidAudioFocus.none, // Key setting: Don't request focus to avoid stopping other apps
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.ambient,
          options: const {
            AVAudioSessionOptions.mixWithOthers,
          },
        ),
      );

      await AudioPlayer.global.setAudioContext(audioContext);
      // Instantiate players after the global context is set so they use
      // the intended AudioContext (mixing with other apps / no focus).
      _backgroundMusicPlayer = AudioPlayer();

      debugPrint('✅ Audio context configured to mix with other apps and players created');
    } catch (e) {
      debugPrint('⚠️ Error configuring audio context: $e');
      // Ensure players are created even if context setup fails
      try { _backgroundMusicPlayer = AudioPlayer(); } catch(_) {}
    }
  }

  /// Load volume settings from SharedPreferences
  Future<void> _loadVolumeSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load sound volume multiplier (default to config value if not set)
      final savedSoundVolume = prefs.getDouble('sound_volume_multiplier');
      if (savedSoundVolume != null) {
        _soundVolumeMultiplier = savedSoundVolume.clamp(0.0, 1.0);
      }

      // Load music volume multiplier (default to config value if not set)
      final savedMusicVolume = prefs.getDouble('music_volume_multiplier');
      if (savedMusicVolume != null) {
        _musicVolumeMultiplier = savedMusicVolume.clamp(0.0, 1.0);
      }

      debugPrint('🔊 Loaded volume settings: Sound=${_soundVolumeMultiplier.toStringAsFixed(2)}, Music=${_musicVolumeMultiplier.toStringAsFixed(2)}');

      // If music is already playing, update its volume with the loaded settings
      if (_currentMusicPath != null) {
        setMusicVolumeMultiplier(_musicVolumeMultiplier);
      }
    } catch (e) {
      debugPrint('⚠️ Error loading volume settings: $e');
    } finally {
      // Complete the completer to signal that settings are loaded (or failed)
      if (_settingsLoadCompleter != null && !_settingsLoadCompleter!.isCompleted) {
        _settingsLoadCompleter!.complete();
      }
    }
  }

  /// Wait for volume settings to be loaded (used before playing music)
  Future<void> _ensureSettingsLoaded() async {
    if (_settingsLoadCompleter != null && !_settingsLoadCompleter!.isCompleted) {
      // Add a timeout to prevent blocking indefinitely
      try {
        await _settingsLoadCompleter!.future.timeout(const Duration(seconds: 2));
      } catch (e) {
        debugPrint("⚠️ Settings load timed out, proceeding with defaults.");
      }
    }
  }

  /// Save volume settings to SharedPreferences
  Future<void> _saveVolumeSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('sound_volume_multiplier', _soundVolumeMultiplier);
      await prefs.setDouble('music_volume_multiplier', _musicVolumeMultiplier);
      debugPrint('💾 Saved volume settings: Sound=${_soundVolumeMultiplier.toStringAsFixed(2)}, Music=${_musicVolumeMultiplier.toStringAsFixed(2)}');
    } catch (e) {
      debugPrint('⚠️ Error saving volume settings: $e');
    }
  }

  /// Apply non-linear volume curve for more responsive adjustment at higher percentages
  double _applyVolumeCurve(double linearVolume) {
    if (linearVolume <= 0.0) return 0.0;
    if (linearVolume >= 1.0) return 1.0;
    return linearVolume * linearVolume * math.sqrt(linearVolume);
  }

  // --- Music Control ---

  /// Play background music (looping)
  Future<void> playBackgroundMusic(String assetPath) async {
    if (!_isMusicEnabled) {
      debugPrint('🔇 Music is disabled, skipping: $assetPath');
      return;
    }

    // Wait for volume settings to be loaded before playing music
    await _ensureSettingsLoaded();

    // Prevent concurrent play operations (but allow play even if stop is in progress)
    if (_isMusicOperationInProgress) {
      // Wait a bit and retry
      for (int i = 0; i < 3; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!_isMusicOperationInProgress) break;
      }
    }

    _isMusicOperationInProgress = true;

    try {
      // Check if we are already supposed to be playing this track
      if (_currentMusicPath == assetPath) {
        // Check if it is actually playing
        bool isPlaying = false;
        try {
          isPlaying = _backgroundMusicPlayer.state == PlayerState.playing;
        } catch (_) {}

        if (isPlaying) {
          debugPrint('🎵 Music already playing: $assetPath');
          _isMusicOperationInProgress = false;
          return; // EXIT EARLY - DO NOT RESTART
        }

        debugPrint('🔄 Music path matches current but stopped, restarting: $assetPath');
        await _restartMusic(assetPath);
        _isMusicOperationInProgress = false;
        return;
      }

      // Stop any currently playing music first (only if different)
      if (_currentMusicPath != null && _currentMusicPath != assetPath) {
        await stopBackgroundMusic(forceStop: true);
      }

      await _restartMusic(assetPath);
      _isMusicOperationInProgress = false;
    } catch (e) {
      debugPrint('❌ Error playing background music ($assetPath): $e');
      _currentMusicPath = null; // Reset on error
      _isMusicOperationInProgress = false;
    }
  }

  /// Internal method to start/restart music from beginning
  Future<void> _restartMusic(String assetPath) async {
    // Determine base volume, then apply the non-linear volume curve
    final curvedMultiplier = _applyVolumeCurve(_musicVolumeMultiplier);
    final volume = (_musicVolume * curvedMultiplier).clamp(0.0, 1.0);

    _currentMusicPath = assetPath;
    _lastMusicStartTime = DateTime.now();

    try {
      try {
        await _backgroundMusicPlayer.stop();
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (_) {}

      await _backgroundMusicPlayer.setReleaseMode(ReleaseMode.loop);
      await _backgroundMusicPlayer.setVolume(0.0);

      debugPrint('🎵 Playing background music: $assetPath (target volume: $volume)');

      await _backgroundMusicPlayer.play(AssetSource(assetPath));
    } catch (e) {
      debugPrint('⚠️ Error starting playback: $e');
      _currentMusicPath = null;
      rethrow;
    }

    // Fade in
    const fadeInDuration = Duration(milliseconds: 500);
    _fadeIn(fadeInDuration, volume);
    _wasPlayingBeforePause = true;
  }

  /// Ramps the volume up. Tagged with a generation so that a volume change or
  /// a new track abandons an in-flight fade instead of fighting it over
  /// setVolume.
  Future<void> _fadeIn(Duration duration, double targetVolume) async {
    final int generation = ++_fadeGeneration;
    const steps = 20;
    final stepDuration = duration ~/ steps;
    final volumeStep = targetVolume / steps;

    for (int i = 0; i <= steps; i++) {
      if (_currentMusicPath == null || _fadeGeneration != generation) return;
      await _backgroundMusicPlayer.setVolume(volumeStep * i);
      await Future.delayed(stepDuration);
    }
  }

  /// Stop background music
  Future<void> stopBackgroundMusic({bool forceStop = false}) async {
    if (_isMusicOperationInProgress && !forceStop) return;

    try {
      if (_currentMusicPath != null) {
        if (!forceStop && _lastMusicStartTime != null) {
          if (DateTime.now().difference(_lastMusicStartTime!).inMilliseconds < 500) return;
        }

        _isMusicOperationInProgress = true;
        _fadeGeneration++; // Abandon any in-flight fade

        try {
          await _backgroundMusicPlayer.stop();
        } catch (_) {}

        _currentMusicPath = null;
        _wasPlayingBeforePause = false;
        _isMusicOperationInProgress = false;
      }
    } catch (e) {
      _isMusicOperationInProgress = false;
    }
  }

  /// Pause music (app background)
  Future<void> pauseBackgroundMusic() async {
    try {
      if (_currentMusicPath != null) {
        _wasPlayingBeforePause =
            _backgroundMusicPlayer.state == PlayerState.playing;

        if (_wasPlayingBeforePause) {
          _fadeGeneration++; // Abandon any in-flight fade
          await _backgroundMusicPlayer.pause(); // Pause instead of stop to allow resume
        }
      }
    } catch (_) {}
  }

  /// Resume music (app foreground)
  Future<void> resumeBackgroundMusic() async {
    if (!_isMusicEnabled || !_wasPlayingBeforePause || _currentMusicPath == null) return;
    try {
      await _backgroundMusicPlayer.resume();
    } catch (_) {
       // If resume fails (e.g. stopped/released), restart
       await playBackgroundMusic(_currentMusicPath!);
    }
  }

  // --- Asset-based SFX (Pooled) ---

  Future<void> _playSound(String assetName, {double volumeMult = 1.0}) async {
    await _ensureSettingsLoaded();
    if (!_isSoundEnabled) return;

    final curvedMultiplier = _applyVolumeCurve(_soundVolumeMultiplier);
    final volume = (curvedMultiplier * volumeMult).clamp(0.0, 1.0);

    try {
      final player = await _getSfxPlayer();
      // Force stop before reuse to prevent "dead player" state
      await player.stop();
      await player.setVolume(volume);
      await player.play(AssetSource(assetName));
    } catch (e) {
      debugPrint("Error playing SFX $assetName: $e");
    }
  }

  Future<void> playShoot({int variant = 0}) async {
    // Map variant to asset
    String assetName = 'audio/shoot_0.wav';
    if (variant == 1) assetName = 'audio/shoot_1.wav';
    if (variant == 2) assetName = 'audio/shoot_2.wav';

    await _playSound(assetName);
  }

  Future<void> playExplosion({bool isLarge = false}) async {
    String assetName = isLarge ? 'audio/explosion_large.wav' : 'audio/explosion.wav';
    await _playSound(assetName, volumeMult: 0.5);
  }

  Future<void> playLevelUp() async {
    await _playSound('audio/levelup.wav');
  }

  Future<void> playDamage() async {
    await _playSound('audio/damage.wav');
  }

  /// Set sound volume multiplier (0.0 to 1.0)
  void setSoundVolumeMultiplier(double multiplier) {
    _soundVolumeMultiplier = multiplier.clamp(0.0, 1.0);
    _saveVolumeSettings();
  }

  /// Set music volume multiplier (0.0 to 1.0)
  void setMusicVolumeMultiplier(double multiplier) {
    _musicVolumeMultiplier = multiplier.clamp(0.0, 1.0);
    _saveVolumeSettings();

    if (_currentMusicPath != null) {
      _fadeGeneration++; // A fade in flight would overwrite this immediately
      final curvedMultiplier = _applyVolumeCurve(_musicVolumeMultiplier);
      final finalVolume = (_musicVolume * curvedMultiplier).clamp(0.0, 1.0);
      _backgroundMusicPlayer.setVolume(finalVolume);
    }
  }

  double get soundVolumeMultiplier => _soundVolumeMultiplier;
  double get musicVolumeMultiplier => _musicVolumeMultiplier;
}
