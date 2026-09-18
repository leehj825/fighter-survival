import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'balance.dart';
import 'game.dart';
import 'managers.dart';
import 'sound_service.dart';

class AdManager {
  // Production banner ad unit (App Bundle builds should use this by setting
  // the dart-define BUNDLE_BUILT=true when building an AAB)
  static const String bannerAdUnitId = 'ca-app-pub-4400173019354346/8395964292';
  

  // Google-provided test banner (safe to use during development and for APK/non-bundle builds)
  static const String admobBannerTestId = 'ca-app-pub-3940256099942544/6300978111';

  // Set at build time via --dart-define=BUNDLE_BUILT=true for App Bundle releases.
  static const bool isBundleBuild = bool.fromEnvironment('BUNDLE_BUILT', defaultValue: false);

  // Use production ID only for release + bundle builds; otherwise use the test ID.
  static String get bannerAdUnit => (kReleaseMode && isBundleBuild) ? bannerAdUnitId : admobBannerTestId;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GameData().init();

  // 1. Initialize Audio Context Globally
  await SoundService.instance.init();

  // 2. Initialize Google Mobile Ads SDK
  await MobileAds.instance.initialize();

  runApp(const MaterialApp(
    title: 'Fight Survival',
    home: MainMenu(),
  ));
}

class MainMenu extends StatefulWidget {
  const MainMenu({super.key});

  @override
  State<MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> with WidgetsBindingObserver {
  // We'll listen to GameData changes to update UI

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GameData().addListener(_onGameDataChanged);
    SoundService.instance.playBackgroundMusic('audio/main2.mp3');

    // No banner on the main menu (ads shown on Game screen)
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GameData().removeListener(_onGameDataChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      SoundService.instance.pauseBackgroundMusic();
    } else if (state == AppLifecycleState.resumed) {
      SoundService.instance.resumeBackgroundMusic();
    }
  }

  void _onGameDataChanged() {
    setState(() {});
  }

  void _startNewGame() {
    GameData().clearRunState();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const GameScreen(resume: false),
      ),
    );
  }

  void _resumeGame() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const GameScreen(resume: true),
      ),
    );
  }

  void _openWorkshop() {
    showDialog(context: context, builder: (ctx) => const WorkshopDialog());
  }

  void _openSettings() {
    showDialog(context: context, builder: (ctx) => const SettingsDialog());
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        // --- RESPONSIVE LOGIC ---
        final size = MediaQuery.of(context).size;
        final isPortrait = orientation == Orientation.portrait;

        // Use Width in Portrait, Height in Landscape for consistent sizing
        final double refSize = isPortrait ? size.width : size.height;

        // Relative sizes
        final double titleSize = refSize * 0.1;
        final double buttonTextSize = refSize * 0.06;
        final double paddingV = refSize * 0.04;
        final double paddingH = refSize * 0.1;

        return Scaffold(
          backgroundColor: Colors.blueGrey.shade900,
          body: Center(
            child: SingleChildScrollView(
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [

                    Text(
                      "FIGHT SURVIVAL",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: titleSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.cyanAccent),
                    ),
                    SizedBox(height: paddingV / 2),
                    Text(
                      "Total Gems: ${GameData().totalGems}",
                      style: TextStyle(
                          fontSize: buttonTextSize * 0.8, color: Colors.amber),
                    ),
                    if (GameData().hasRecords) ...[
                      SizedBox(height: paddingV / 4),
                      Text(
                        "Best Wave: ${GameData().bestWave}  |  Best Kills: ${GameData().bestKills}  |  Best Combo: ${GameData().bestCombo}x",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: buttonTextSize * 0.45,
                            color: Colors.white70),
                      ),
                    ],
                    SizedBox(height: paddingV * 2),
                    if (GameData().hasSavedRun) ...[
                      _buildButton("RESUME", Colors.orange, buttonTextSize,
                          paddingH, paddingV, _resumeGame),
                      SizedBox(height: paddingV),
                      _buildButton(
                          "NEW GAME",
                          Colors.green,
                          buttonTextSize * 0.8,
                          paddingH * 0.8,
                          paddingV * 0.8,
                          _startNewGame),
                    ] else
                      _buildButton("PLAY", Colors.green, buttonTextSize,
                          paddingH, paddingV, _startNewGame),
                    SizedBox(height: paddingV),
                    _buildButton(
                        "WORKSHOP",
                        Colors.purple,
                        buttonTextSize * 0.8,
                        paddingH * 0.8,
                        paddingV * 0.8,
                        _openWorkshop),
                    SizedBox(height: paddingV),
                    _buildButton(
                        "SETTINGS",
                        Colors.grey,
                        buttonTextSize * 0.8,
                        paddingH * 0.8,
                        paddingV * 0.8,
                        _openSettings),
                  ],
                ),
              ),
            ),
          ),

        );
      },
    );
  }

  Widget _buildButton(String label, Color color, double fontSize, double padH, double padV, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        backgroundColor: color,
      ),
      child: Text(label, style: TextStyle(fontSize: fontSize)),
    );
  }
}

class GameScreen extends StatefulWidget {
  final bool resume;
  const GameScreen({super.key, this.resume = false});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late RpgGame _game;
  late final BannerAd _bannerAd;
  bool _isBannerAdReady = false;
  String? _adLoadError;

  @override
  void initState() {
    super.initState();
    _game = RpgGame(resumeGame: widget.resume);
    WidgetsBinding.instance.addObserver(this);

    // Initialize banner ad for the Game screen
    debugPrint('Using banner ad unit: ${AdManager.bannerAdUnit}');
    _bannerAd = BannerAd(
      adUnitId: AdManager.bannerAdUnit,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('Game BannerAd loaded');
          if (!mounted) return; // Ad load can resolve after the route is popped
          setState(() { _isBannerAdReady = true; _adLoadError = null; });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Game BannerAd failed to load: ${error.message}');
          ad.dispose();
          if (!mounted) return;
          setState(() { _isBannerAdReady = false; _adLoadError = error.message; });
        },
      ),
    );
    _bannerAd.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bannerAd.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (!_game.gameOver && !_game.paused) {
        _game.paused = true;
        _game.overlays.add('PauseMenu');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!_game.gameOver && !_game.paused) {
           _game.paused = true;
           _game.overlays.add('PauseMenu');
        }
      },
      child: SafeArea(
        child: Column(
          children: [
            if (_isBannerAdReady)
              SizedBox(
                height: AdSize.banner.height.toDouble(),
                child: AdWidget(ad: _bannerAd),
              )
            else if (_adLoadError != null)
              Container(
                height: AdSize.banner.height.toDouble(),
                alignment: Alignment.center,
                color: Colors.black26,
                child: Text('Ad failed: $_adLoadError', style: const TextStyle(color: Colors.white70)),
              ),
            Expanded(
              child: GameWidget(
                game: _game,
                overlayBuilderMap: {
                  'LevelUp': (context, RpgGame game) {
                    return _LevelUpOverlay(game: game);
                  },
                  'GameOver': (context, RpgGame game) {
                    return _RunSummaryOverlay(game: game);
                  },
                  'PauseMenu': (context, RpgGame game) {
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        color: Colors.black.withValues(alpha: 0.8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              "PAUSED",
                              style: TextStyle(color: Colors.cyan, fontSize: 32, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              onPressed: () {
                                game.paused = false;
                                game.overlays.remove('PauseMenu');
                              },
                              child: const Text("Resume"),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                              onPressed: () {
                                game.exitRun();
                                Navigator.of(context).pop();
                              },
                              child: const Text("Exit to Menu (Save Gems)"),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  int _lastSoundTime = 0;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey.shade900,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("SETTINGS", style: TextStyle(color: Colors.white, fontSize: 24)),
            const SizedBox(height: 20),

            // Music Volume
            _buildVolumeSlider(
              label: "Music Volume",
              value: SoundService.instance.musicVolumeMultiplier,
              onChanged: (val) {
                setState(() {
                  SoundService.instance.setMusicVolumeMultiplier(val);
                });
              },
            ),

            const SizedBox(height: 10),

            // Sound Volume
            _buildVolumeSlider(
              label: "Sound Volume",
              value: SoundService.instance.soundVolumeMultiplier,
              onChanged: (val) {
                setState(() {
                  SoundService.instance.setSoundVolumeMultiplier(val);
                });

                // Play feedback sound (throttled)
                final now = DateTime.now().millisecondsSinceEpoch;
                if (now - _lastSoundTime > 150) {
                  SoundService.instance.playShoot(variant: 1);
                  _lastSoundTime = now;
                }
              },
            ),

            const SizedBox(height: 16),

            // Haptics
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Haptics", style: TextStyle(color: Colors.white70)),
                Switch(
                  value: GameData().hapticsEnabled,
                  activeTrackColor: Colors.cyanAccent,
                  onChanged: (val) {
                    setState(() {
                      GameData().setHapticsEnabled(val);
                    });
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CLOSE", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeSlider({required String label, required double value, required ValueChanged<double> onChanged}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$label: ${(value * 100).toInt()}%",
          style: const TextStyle(color: Colors.white70)
        ),
        Slider(
          value: value,
          onChanged: onChanged,
          min: 0.0,
          max: 1.0,
          activeColor: Colors.cyanAccent,
          inactiveColor: Colors.grey.shade800,
        ),
      ],
    );
  }
}

class WorkshopDialog extends StatefulWidget {
  const WorkshopDialog({super.key});

  @override
  State<WorkshopDialog> createState() => _WorkshopDialogState();
}

class _WorkshopDialogState extends State<WorkshopDialog> {
  final data = GameData();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.grey.shade900,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("WORKSHOP",
                  style: TextStyle(fontSize: 30, color: Colors.white)),
              const SizedBox(height: 20),
              Text("Gems: ${data.totalGems}",
                  style: const TextStyle(fontSize: 24, color: Colors.amber)),
              const SizedBox(height: 30),

              // Repeatable upgrades
              for (final upgrade in Upgrade.values) _buildUpgradeRow(upgrade),

              const SizedBox(height: 8),

              // One-off unlocks
              for (final unlock in Unlock.values) _buildUnlockRow(unlock),

              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("BACK",
                    style: TextStyle(color: Colors.white, fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow({
    required String title,
    required String description,
    required Color titleColor,
    required Widget trailing,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white10, borderRadius: BorderRadius.circular(8)),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: titleColor, fontWeight: FontWeight.bold)),
              Text(description,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildUpgradeRow(Upgrade upgrade) {
    final int level = data.levelOf(upgrade);
    final bool maxed = data.isMaxed(upgrade);
    final int cost = data.costOf(upgrade);

    return _buildRow(
      title: "${upgrade.title} (Lvl $level)",
      description: upgrade.description,
      titleColor: Colors.cyanAccent,
      trailing: maxed
          ? const Text("MAX",
              style:
                  TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
          : ElevatedButton(
              onPressed: data.canAfford(cost)
                  ? () => setState(() => data.buyUpgrade(upgrade))
                  : null,
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700),
              child: Text("$cost G"),
            ),
    );
  }

  Widget _buildUnlockRow(Unlock unlock) {
    final bool owned = data.has(unlock);

    return _buildRow(
      title: unlock.title,
      description: unlock.description,
      titleColor: Colors.pinkAccent,
      trailing: owned
          ? const Text("INSTALLED",
              style:
                  TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
          : ElevatedButton(
              onPressed: data.canAfford(unlock.cost)
                  ? () => setState(() => data.buyUnlock(unlock))
                  : null,
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700),
              child: Text("${unlock.cost} G"),
            ),
    );
  }
}

/// Shown (with the game paused) when the player levels up, to pick one of
/// three randomly offered boons.
class _LevelUpOverlay extends StatelessWidget {
  const _LevelUpOverlay({required this.game});

  final RpgGame game;

  @override
  Widget build(BuildContext context) {
    final List<Boon> boons = game.pendingBoons;

    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.cyanAccent, width: 2),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "LEVEL ${game.player.level}",
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "CHOOSE AN UPGRADE",
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              for (final boon in boons)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: SizedBox(
                    width: 260,
                    child: ElevatedButton(
                      onPressed: () => game.chooseBoon(boon),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey.shade800,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        alignment: Alignment.centerLeft,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            boon.title,
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            boon.description,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when a run ends: what the run added up to, and whether it beat any
/// records. Wraps in a ListenableBuilder on GameData because recordRun's
/// SharedPreferences write (and its "new best" result) completes slightly
/// after this overlay first appears.
class _RunSummaryOverlay extends StatelessWidget {
  const _RunSummaryOverlay({required this.game});

  final RpgGame game;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GameData(),
      builder: (context, _) {
        final records = game.lastRunRecords;
        final int gemsEarned = GameData().gemsEarned(game.runGems);

        return Center(
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent, width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "SIGNAL LOST",
                  style: TextStyle(
                      color: Colors.red,
                      fontSize: 30,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _statRow("Wave Reached", "${game.wave}",
                    isRecord: records?.newBestWave ?? false),
                _statRow("Kills", "${game.killCount}",
                    isRecord: records?.newBestKills ?? false),
                _statRow("Best Combo", "${game.maxCombo}x",
                    isRecord: records?.newBestCombo ?? false),
                _statRow("Gems Earned", "$gemsEarned"),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: game.restartRun,
                  child: const Text("Restart"),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Return to Menu"),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statRow(String label, String value, {bool isRecord = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ),
          Text(
            value,
            style: TextStyle(
              color: isRecord ? Colors.amber : Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (isRecord) ...[
            const SizedBox(width: 8),
            const Text("NEW BEST!",
                style: TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ],
      ),
    );
  }
}
