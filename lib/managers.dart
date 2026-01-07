import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GameData extends ChangeNotifier {
  static final GameData _instance = GameData._internal();
  factory GameData() => _instance;

  GameData._internal();

  late SharedPreferences _prefs;

  // Persisted Stats
  int totalGems = 0;
  int levelHp = 0; // +20 HP per level
  int levelDash = 0; // -10% Cooldown per level
  int levelShield = 0; // Unlocks/Upgrades Shield
  bool unlockBlaster = false;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    load();
  }

  void load() {
    totalGems = _prefs.getInt('totalGems') ?? 0;
    levelHp = _prefs.getInt('levelHp') ?? 0;
    levelDash = _prefs.getInt('levelDash') ?? 0;
    levelShield = _prefs.getInt('levelShield') ?? 0;
    unlockBlaster = _prefs.getBool('unlockBlaster') ?? false;
    notifyListeners();
  }

  Future<void> save() async {
    await _prefs.setInt('totalGems', totalGems);
    await _prefs.setInt('levelHp', levelHp);
    await _prefs.setInt('levelDash', levelDash);
    await _prefs.setInt('levelShield', levelShield);
    await _prefs.setBool('unlockBlaster', unlockBlaster);
    notifyListeners();
  }

  // --- Upgrade Costs & Logic ---

  int get hpUpgradeCost => 100 * (levelHp + 1);
  int get dashUpgradeCost => 150 * (levelDash + 1);
  int get shieldUpgradeCost => 200 * (levelShield + 1);
  static const int blasterCost = 500;

  bool buyHpUpgrade() {
    if (totalGems >= hpUpgradeCost) {
      totalGems -= hpUpgradeCost;
      levelHp++;
      save();
      return true;
    }
    return false;
  }

  bool buyDashUpgrade() {
    if (totalGems >= dashUpgradeCost) {
      totalGems -= dashUpgradeCost;
      levelDash++;
      save();
      return true;
    }
    return false;
  }

  bool buyShieldUpgrade() {
    if (totalGems >= shieldUpgradeCost) {
      totalGems -= shieldUpgradeCost;
      levelShield++;
      save();
      return true;
    }
    return false;
  }

  bool buyBlaster() {
    if (!unlockBlaster && totalGems >= blasterCost) {
      totalGems -= blasterCost;
      unlockBlaster = true;
      save();
      return true;
    }
    return false;
  }

  void addGems(int amount) {
    totalGems += amount;
    save();
  }
}
