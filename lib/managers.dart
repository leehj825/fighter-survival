import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A permanent, repeatable Workshop upgrade bought with gems.
enum Upgrade {
  hp('levelHp', 'Hull Strength', '+20 Max HP', 100),
  dash('levelDash', 'Thrusters', '-10% Dash Cooldown', 150, maxLevel: 8),
  shield('levelShield', 'Orbital Shield', 'Adds an orbiting shield', 200,
      maxLevel: 4),
  damage('levelDamage', 'Power Core', '+8% Damage', 120),
  magnet('levelMagnet', 'Gem Magnet', '+25 Pickup Radius', 80, maxLevel: 6),
  greed('levelGreed', 'Prospector', '+10% Gems Earned', 130, maxLevel: 10),
  dashCharge('levelDashCharge', 'Capacitor', '+1 Dash Charge', 300,
      maxLevel: 2);

  const Upgrade(
    this.key,
    this.title,
    this.description,
    this.baseCost, {
    this.maxLevel = 10,
  });

  /// SharedPreferences key. These are persisted, so they must not change.
  final String key;
  final String title;
  final String description;
  final int baseCost;
  final int maxLevel;
}

/// A one-off Workshop purchase that unlocks an ability.
enum Unlock {
  blaster('unlockBlaster', 'Blaster Cannon',
      'Hold the right stick to aim and fire', 500),
  magic('unlockMagic', 'Magic Attack', 'Tap the magic button for area damage',
      300),
  revive('unlockRevive', 'Second Wind', 'Revive once per run at half health',
      800);

  const Unlock(this.key, this.title, this.description, this.cost);

  /// SharedPreferences key. These are persisted, so they must not change.
  final String key;
  final String title;
  final String description;
  final int cost;
}

class GameData extends ChangeNotifier {
  static final GameData _instance = GameData._internal();
  factory GameData() => _instance;

  GameData._internal();

  late SharedPreferences _prefs;

  // Persisted Stats
  int totalGems = 0;
  final Map<Upgrade, int> _levels = <Upgrade, int>{};
  final Set<Unlock> _unlocks = <Unlock>{};

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    load();
  }

  void load() {
    totalGems = _prefs.getInt('totalGems') ?? 0;
    for (final upgrade in Upgrade.values) {
      _levels[upgrade] = _prefs.getInt(upgrade.key) ?? 0;
    }
    _unlocks.clear();
    for (final unlock in Unlock.values) {
      if (_prefs.getBool(unlock.key) ?? false) _unlocks.add(unlock);
    }
    notifyListeners();
  }

  Future<void> save() async {
    await _prefs.setInt('totalGems', totalGems);
    for (final upgrade in Upgrade.values) {
      await _prefs.setInt(upgrade.key, levelOf(upgrade));
    }
    for (final unlock in Unlock.values) {
      await _prefs.setBool(unlock.key, has(unlock));
    }
    notifyListeners();
  }

  // --- Upgrades ---

  int levelOf(Upgrade upgrade) => _levels[upgrade] ?? 0;

  bool has(Unlock unlock) => _unlocks.contains(unlock);

  bool isMaxed(Upgrade upgrade) => levelOf(upgrade) >= upgrade.maxLevel;

  /// Cost of the next level; each level costs one more multiple of the base.
  int costOf(Upgrade upgrade) => upgrade.baseCost * (levelOf(upgrade) + 1);

  bool canAfford(int cost) => totalGems >= cost;

  bool buyUpgrade(Upgrade upgrade) {
    if (isMaxed(upgrade)) return false;
    final int cost = costOf(upgrade);
    if (!canAfford(cost)) return false;

    totalGems -= cost;
    _levels[upgrade] = levelOf(upgrade) + 1;
    save();
    return true;
  }

  bool buyUnlock(Unlock unlock) {
    if (has(unlock) || !canAfford(unlock.cost)) return false;

    totalGems -= unlock.cost;
    _unlocks.add(unlock);
    save();
    return true;
  }

  // --- Derived gameplay values ---

  int get maxHealth => 100 + (levelOf(Upgrade.hp) * 20);

  double get dashCooldown => 0.8 * _pow(0.9, levelOf(Upgrade.dash));

  int get shieldCount => levelOf(Upgrade.shield);

  double get damageMultiplier => 1.0 + (0.08 * levelOf(Upgrade.damage));

  double get pickupRadius => 100.0 + (25.0 * levelOf(Upgrade.magnet));

  int get dashCharges => 1 + levelOf(Upgrade.dashCharge);

  /// Gems actually banked for a run of [runGems] raw gems.
  int gemsEarned(int runGems) =>
      (runGems * (1.0 + 0.10 * levelOf(Upgrade.greed))).round();

  static double _pow(double base, int exponent) {
    double result = 1.0;
    for (int i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }

  // --- Legacy accessors (kept so existing call sites keep reading naturally) ---

  int get levelHp => levelOf(Upgrade.hp);
  int get levelDash => levelOf(Upgrade.dash);
  int get levelShield => levelOf(Upgrade.shield);
  bool get unlockBlaster => has(Unlock.blaster);
  bool get unlockMagic => has(Unlock.magic);
  bool get unlockRevive => has(Unlock.revive);

  // --- Session Persistence ---

  bool get hasSavedRun => _prefs.containsKey('savedWave');

  Future<void> saveRunState(
      int wave, int level, int xp, double damageMult, int health) async {
    await _prefs.setInt('savedWave', wave);
    await _prefs.setInt('savedLevel', level);
    await _prefs.setInt('savedXp', xp);
    await _prefs.setDouble('savedDamageMult', damageMult);
    await _prefs.setInt('savedHealth', health);
    notifyListeners();
  }

  Future<void> clearRunState() async {
    await _prefs.remove('savedWave');
    await _prefs.remove('savedLevel');
    await _prefs.remove('savedXp');
    await _prefs.remove('savedDamageMult');
    await _prefs.remove('savedHealth');
    notifyListeners();
  }

  int get savedWave => _prefs.getInt('savedWave') ?? 1;
  int get savedLevel => _prefs.getInt('savedLevel') ?? 1;
  int get savedXp => _prefs.getInt('savedXp') ?? 0;
  double get savedDamageMult => _prefs.getDouble('savedDamageMult') ?? 1.0;
  int get savedHealth => _prefs.getInt('savedHealth') ?? 100;

  void addGems(int amount) {
    totalGems += amount;
    save();
  }

  Future<void> resetProgress() async {
    totalGems = 0;
    _levels.clear();
    _unlocks.clear();
    await save();
  }
}
