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
        builder: (context) => GameWidget(
          game: RpgGame(),
          overlayBuilderMap: {
            'GameOver': (BuildContext context, RpgGame game) {
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
                          Navigator.of(context).pop(); // Go back to Main Menu
                        },
                        child: const Text("Return to Menu"),
                      ),
                    ],
                  ),
                ),
              );
            }
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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "FIGHTER SURVIVAL",
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

             // Blaster Unlock
             _buildUnlockRow(
               "Blaster Cannon",
               "Tap to Shoot",
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
    );
  }

  Widget _buildUpgradeRow(String title, String desc, int cost, VoidCallback onTap) {
    bool canAfford = data.totalGems >= cost;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
