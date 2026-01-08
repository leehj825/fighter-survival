import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'game.dart';
import 'managers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GameData().init();
  runApp(const MaterialApp(home: MainMenu()));
}

class MainMenu extends StatefulWidget {
  const MainMenu({super.key});

  @override
  State<MainMenu> createState() => _MainMenuState();
}

class _MainMenuState extends State<MainMenu> {
  // We'll listen to GameData changes to update UI
  @override
  void initState() {
    super.initState();
    GameData().addListener(_onGameDataChanged);
  }

  @override
  void dispose() {
    GameData().removeListener(_onGameDataChanged);
    super.dispose();
  }

  void _onGameDataChanged() {
    setState(() {});
  }

  void _startGame() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const GameScreen(),
      ),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late RpgGame _game;

  @override
  void initState() {
    super.initState();
    _game = RpgGame();
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

  void _openWorkshop() {
    showDialog(
      context: context,
      builder: (ctx) => const WorkshopDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blueGrey.shade900,
      body: Container(
        width: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "FIGHTER SURVIVAL",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
            ),
            const SizedBox(height: 10),
            Text(
              "Total Gems: ${GameData().totalGems}",
              style: const TextStyle(fontSize: 20, color: Colors.amber),
            ),
            const SizedBox(height: 50),
            ElevatedButton(
              onPressed: _startGame,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                backgroundColor: Colors.green,
              ),
              child: const Text("PLAY", style: TextStyle(fontSize: 24)),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _openWorkshop,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                backgroundColor: Colors.purple,
              ),
              child: const Text("WORKSHOP", style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _openSettings,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                backgroundColor: Colors.grey,
              ),
              child: const Text("SETTINGS", style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings() {
    showDialog(
      context: context,
      builder: (ctx) => const SettingsDialog(),
    );
  }
}

class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

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
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                // Confirm dialog
                showDialog(context: context, builder: (context) => AlertDialog(
                  title: const Text("Reset Progress?"),
                  content: const Text("This will delete all gems and upgrades."),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                    TextButton(onPressed: () async {
                       await GameData().resetProgress();
                       Navigator.pop(context); // Close alert
                       Navigator.pop(context); // Close settings
                    }, child: const Text("Reset", style: TextStyle(color: Colors.red))),
                  ],
                ));
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text("RESET GAME DATA"),
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
