import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fight_survival/managers.dart';

void main() {
  // GameData is a singleton, so each test resets it.
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await GameData().init();
    await GameData().resetProgress();
    await GameData().clearRunState();
  });

  group('upgrades', () {
    test('cost scales with the current level', () {
      final data = GameData();
      expect(data.costOf(Upgrade.hp), 100);

      data.addGems(100);
      expect(data.buyUpgrade(Upgrade.hp), isTrue);
      expect(data.levelOf(Upgrade.hp), 1);
      expect(data.costOf(Upgrade.hp), 200);
    });

    test('purchases are refused when gems are short', () {
      final data = GameData();
      data.addGems(data.costOf(Upgrade.hp) - 1);
      expect(data.buyUpgrade(Upgrade.hp), isFalse);
      expect(data.levelOf(Upgrade.hp), 0);
      expect(data.totalGems, 99);
    });

    test('spend deducts exactly the cost', () {
      final data = GameData();
      data.addGems(1000);
      final cost = data.costOf(Upgrade.dash);
      expect(data.buyUpgrade(Upgrade.dash), isTrue);
      expect(data.totalGems, 1000 - cost);
    });

    test('cannot be bought past their max level', () {
      final data = GameData();
      data.addGems(1000000);
      for (int i = 0; i < Upgrade.dashCharge.maxLevel; i++) {
        expect(data.buyUpgrade(Upgrade.dashCharge), isTrue);
      }
      expect(data.isMaxed(Upgrade.dashCharge), isTrue);
      final gemsAtMax = data.totalGems;
      expect(data.buyUpgrade(Upgrade.dashCharge), isFalse);
      expect(data.totalGems, gemsAtMax, reason: 'must not charge at max');
    });

    test('every upgrade has a distinct persistence key', () {
      final keys = Upgrade.values.map((u) => u.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
    });
  });

  group('unlocks', () {
    test('cannot be bought twice', () {
      final data = GameData();
      data.addGems(5000);
      expect(data.buyUnlock(Unlock.blaster), isTrue);
      expect(data.has(Unlock.blaster), isTrue);
      final afterFirst = data.totalGems;
      expect(data.buyUnlock(Unlock.blaster), isFalse);
      expect(data.totalGems, afterFirst, reason: 'must not charge twice');
    });

    test('are refused when gems are short', () {
      final data = GameData();
      data.addGems(Unlock.revive.cost - 1);
      expect(data.buyUnlock(Unlock.revive), isFalse);
      expect(data.has(Unlock.revive), isFalse);
    });

    test('every unlock has a distinct persistence key', () {
      final keys = Unlock.values.map((u) => u.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
    });
  });

  group('derived gameplay values', () {
    test('start at the unupgraded baseline', () {
      final data = GameData();
      expect(data.maxHealth, 100);
      expect(data.dashCooldown, closeTo(0.8, 1e-9));
      expect(data.damageMultiplier, closeTo(1.0, 1e-9));
      expect(data.pickupRadius, closeTo(100.0, 1e-9));
      expect(data.dashCharges, 1);
      expect(data.shieldCount, 0);
      expect(data.gemsEarned(100), 100);
    });

    test('scale with the purchased levels', () {
      final data = GameData();
      data.addGems(1000000);

      data.buyUpgrade(Upgrade.hp);
      expect(data.maxHealth, 120);

      data.buyUpgrade(Upgrade.dash);
      expect(data.dashCooldown, closeTo(0.72, 1e-9));

      data.buyUpgrade(Upgrade.damage);
      expect(data.damageMultiplier, closeTo(1.08, 1e-9));

      data.buyUpgrade(Upgrade.magnet);
      expect(data.pickupRadius, closeTo(125.0, 1e-9));

      data.buyUpgrade(Upgrade.dashCharge);
      expect(data.dashCharges, 2);

      // Regression: shield levels past the first used to do nothing.
      data.buyUpgrade(Upgrade.shield);
      data.buyUpgrade(Upgrade.shield);
      expect(data.shieldCount, 2);

      data.buyUpgrade(Upgrade.greed);
      expect(data.gemsEarned(100), 110);
    });
  });

  group('persistence', () {
    test('survives a reload', () async {
      final data = GameData();
      data.addGems(5000);
      data.buyUpgrade(Upgrade.damage);
      data.buyUnlock(Unlock.magic);
      await data.save();

      data.load();

      expect(data.levelOf(Upgrade.damage), 1);
      expect(data.has(Unlock.magic), isTrue);
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
      data.buyUpgrade(Upgrade.hp);
      data.buyUnlock(Unlock.magic);

      await data.resetProgress();

      expect(data.totalGems, 0);
      for (final upgrade in Upgrade.values) {
        expect(data.levelOf(upgrade), 0, reason: upgrade.title);
      }
      for (final unlock in Unlock.values) {
        expect(data.has(unlock), isFalse, reason: unlock.title);
      }
    });
  });
}
