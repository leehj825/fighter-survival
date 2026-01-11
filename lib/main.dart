import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'game.dart';
import 'managers.dart';
import 'sound_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GameData().init();

  // 1. Initialize Audio Context Globally
  await SoundService.instance.init();

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GameData().addListener(_onGameDataChanged);
    SoundService.instance.playBackgroundMusic('audio/main2.mp3');
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
    // --- RESPONSIVE LOGIC ---
    final size = MediaQuery.of(context).size;
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    // Use Width in Portrait, Height in Landscape for consistent sizing
    final double refSize = isPortrait ? size.width : size.height;

    // Relative sizes
    final double titleSize = refSize * 0.1;
    final double buttonTextSize = refSize * 0.06;
    final double paddingV = refSize * 0.04;
    final double paddingH = refSize * 0.1;

    return Scaffold(
      backgroundColor: Colors.blueGrey.shade900,
      body: Container(
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
                color: Colors.cyanAccent
              ),
            ),
            SizedBox(height: paddingV / 2),
            Text(
              "Total Gems: ${GameData().totalGems}",
              style: TextStyle(fontSize: buttonTextSize * 0.8, color: Colors.amber),
            ),
            SizedBox(height: paddingV * 2),

            if (GameData().hasSavedRun) ...[
              _buildButton("RESUME", Colors.orange, buttonTextSize, paddingH, paddingV, _resumeGame),
              SizedBox(height: paddingV),
              _buildButton("NEW GAME", Colors.green, buttonTextSize * 0.8, paddingH * 0.8, paddingV * 0.8, _startNewGame),
            ] else
              _buildButton("PLAY", Colors.green, buttonTextSize, paddingH, paddingV, _startNewGame),

            SizedBox(height: paddingV),
            _buildButton("WORKSHOP", Colors.purple, buttonTextSize * 0.8, paddingH * 0.8, paddingV * 0.8, _openWorkshop),

            SizedBox(height: paddingV),
            _buildButton("SETTINGS", Colors.grey, buttonTextSize * 0.8, paddingH * 0.8, paddingV * 0.8, _openSettings),
          ],
        ),
      ),
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

  @override
  void initState() {
    super.initState();
    _game = RpgGame(resumeGame: widget.resume);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (!_game.gameOver && !_game.paused) {
           _game.paused = true;
           _game.overlays.add('PauseMenu');
        }
      },
      child: SafeArea(
        child: GameWidget(
          game: _game,
          overlayBuilderMap: {
            'GameOver': (context, RpgGame game) {
              return Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  color: Colors.black.withOpacity(0.8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "GAME OVER",
                        style: TextStyle(color: Colors.red, fontSize: 32, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Text("Return to Menu"),
                      ),
                    ],
                  ),
                ),
              );
            },
            'PauseMenu': (context, RpgGame game) {
              return Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  color: Colors.black.withOpacity(0.8),
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
               const Text("WORKSHOP", style: TextStyle(fontSize: 30, color: Colors.white)),
               const SizedBox(height: 20),
             Text("Gems: ${data.totalGems}", style: const TextStyle(fontSize: 24, color: Colors.amber)),
             const SizedBox(height: 30),

             // HP Upgrade
             _buildUpgradeRow(
               "Hull Strength (Lvl ${data.levelHp})",
               "+20 Max HP",
               data.hpUpgradeCost,
               () {
                 setState(() {
                   data.buyHpUpgrade();
                 });
               }
             ),

             // Dash Upgrade
             _buildUpgradeRow(
               "Thrusters (Lvl ${data.levelDash})",
               "-10% Dash Cooldown",
               data.dashUpgradeCost,
               () {
                 setState(() {
                   data.buyDashUpgrade();
                 });
               }
             ),

             // Shield Upgrade
             _buildUpgradeRow(
               "Orbital Shield (Lvl ${data.levelShield})",
               data.levelShield == 0 ? "Unlocks Shield" : "Upgrades Shield",
               data.shieldUpgradeCost,
               () {
                 setState(() {
                   data.buyShieldUpgrade();
                 });
               }
             ),

             // Blaster Unlock
             _buildUnlockRow(
               "Blaster Cannon",
               "Hold Right Stick to Aim, Release to Shoot",
               GameData.blasterCost,
               data.unlockBlaster,
               () {
                 setState(() {
                   data.buyBlaster();
                 });
               }
             ),

             const SizedBox(height: 20),
             TextButton(
               onPressed: () => Navigator.of(context).pop(),
               child: const Text("BACK", style: TextStyle(color: Colors.white, fontSize: 18)),
             ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpgradeRow(String title, String desc, int cost, VoidCallback onTap) {
    bool canAfford = data.totalGems >= cost;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
              Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          ElevatedButton(
            onPressed: canAfford ? onTap : null,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700),
            child: Text("$cost G"),
          )
        ],
      ),
    );
  }

  Widget _buildUnlockRow(String title, String desc, int cost, bool unlocked, VoidCallback onTap) {
    bool canAfford = data.totalGems >= cost;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
              Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          unlocked
          ? const Text("INSTALLED", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
          : ElevatedButton(
            onPressed: canAfford ? onTap : null,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700),
            child: Text("$cost G"),
          )
        ],
      ),
    );
  }
}
