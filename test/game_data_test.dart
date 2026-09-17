import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fight_survival/managers.dart';

void main() {
  // GameData is a singleton, so each test resets it through resetProgress().
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await GameData().init();
    await GameData().resetProgress();
    await GameData().clearRunState();
  });

  group('upgrade costs', () {
    test('scale with the current level', () {
      final data = GameData();
      expect(data.hpUpgradeCost, 100);
      expect(data.dashUpgradeCost, 150);
      expect(data.shieldUpgradeCost, 200);

      data.addGems(100);
      expect(data.buyHpUpgrade(), isTrue);
      expect(data.levelHp, 1);
      expect(data.hpUpgradeCost, 200);
    });

    test('purchases are refused when gems are short', () {
      final data = GameData();
      data.addGems(data.hpUpgradeCost - 1);
      expect(data.buyHpUpgrade(), isFalse);
      expect(data.levelHp, 0);
      expect(data.totalGems, 99);
    });

    test('spend deducts exactly the cost', () {
      final data = GameData();
      data.addGems(1000);
      final cost = data.dashUpgradeCost;
      expect(data.buyDashUpgrade(), isTrue);
      expect(data.totalGems, 1000 - cost);
    });

    test('one-shot unlocks cannot be bought twice', () {
      final data = GameData();
      data.addGems(5000);
      expect(data.buyBlaster(), isTrue);
      expect(data.unlockBlaster, isTrue);
      final afterFirst = data.totalGems;
      expect(data.buyBlaster(), isFalse);
      expect(data.totalGems, afterFirst, reason: 'must not charge twice');
    });
  });

  group('run state', () {
    test('is absent until saved', () {
      expect(GameData().hasSavedRun, isFalse);
    });

    test('round-trips every field, health included', () async {
      final data = GameData();
      await data.saveRunState(7, 4, 25, 1.4, 63);

      expect(data.hasSavedRun, isTrue);
      expect(data.savedWave, 7);
      expect(data.savedLevel, 4);
      expect(data.savedXp, 25);
      expect(data.savedDamageMult, closeTo(1.4, 1e-9));
      // Regression: savedHealth was persisted but never read back, so every
      // resumed run started at full health.
      expect(data.savedHealth, 63);
    });

    test('clearing removes the save', () async {
      final data = GameData();
      await data.saveRunState(3, 2, 5, 1.1, 40);
      await data.clearRunState();
      expect(data.hasSavedRun, isFalse);
      expect(data.savedWave, 1, reason: 'falls back to the default');
      expect(data.savedHealth, 100);
    });
  });

  group('resetProgress', () {
    test('clears gems, levels and unlocks', () async {
      final data = GameData();
      data.addGems(5000);
      data.buyHpUpgrade();
      data.buyMagic();

      await data.resetProgress();

      expect(data.totalGems, 0);
      expect(data.levelHp, 0);
      expect(data.levelDash, 0);
      expect(data.levelShield, 0);
      expect(data.unlockBlaster, isFalse);
      expect(data.unlockMagic, isFalse);
    });
  });
}
