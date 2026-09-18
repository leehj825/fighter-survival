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

  group('run records', () {
    test('start unset', () {
      final data = GameData();
      expect(data.hasRecords, isFalse);
      expect(data.bestWave, 0);
      expect(data.bestKills, 0);
      expect(data.bestCombo, 0);
    });

    test('a first run sets every best and reports it as new', () async {
      final data = GameData();
      final records =
          await data.recordRun(wave: 5, kills: 40, combo: 8);

      expect(records.newBestWave, isTrue);
      expect(records.newBestKills, isTrue);
      expect(records.newBestCombo, isTrue);
      expect(records.any, isTrue);
      expect(data.hasRecords, isTrue);
      expect(data.bestWave, 5);
      expect(data.bestKills, 40);
      expect(data.bestCombo, 8);
    });

    test('a worse run does not overwrite a better one', () async {
      final data = GameData();
      await data.recordRun(wave: 10, kills: 100, combo: 20);

      final records =
          await data.recordRun(wave: 3, kills: 10, combo: 2);

      expect(records.any, isFalse);
      expect(data.bestWave, 10);
      expect(data.bestKills, 100);
      expect(data.bestCombo, 20);
    });

    test('records improve independently', () async {
      // A run can beat the wave record while falling short on kills/combo.
      final data = GameData();
      await data.recordRun(wave: 5, kills: 100, combo: 20);

      final records =
          await data.recordRun(wave: 12, kills: 30, combo: 5);

      expect(records.newBestWave, isTrue);
      expect(records.newBestKills, isFalse);
      expect(records.newBestCombo, isFalse);
      expect(data.bestWave, 12);
      expect(data.bestKills, 100, reason: 'the better kill run still stands');
      expect(data.bestCombo, 20, reason: 'the better combo run still stands');
    });

    test('resetProgress clears records', () async {
      final data = GameData();
      await data.recordRun(wave: 9, kills: 50, combo: 10);

      await data.resetProgress();

      expect(data.hasRecords, isFalse);
      expect(data.bestWave, 0);
      expect(data.bestKills, 0);
      expect(data.bestCombo, 0);
    });
  });

  group('haptics setting', () {
    test('defaults to enabled', () {
      expect(GameData().hapticsEnabled, isTrue);
    });

    test('persists across a reload', () async {
      final data = GameData();
      await data.setHapticsEnabled(false);
      data.load();
      expect(data.hapticsEnabled, isFalse);

      await data.setHapticsEnabled(true);
      data.load();
      expect(data.hapticsEnabled, isTrue);
    });
  });

  group('run state boons', () {
    test('default to empty', () {
      expect(GameData().savedBoons, isEmpty);
    });

    test('round-trip through a save', () async {
      final data = GameData();
      await data.saveRunState(4, 2, 10, 1.2, 80,
          boons: <String>['damage', 'regen', 'damage']);

      // Regression: boons were saved but never read back, so Resume silently
      // discarded every boon the player had picked.
      expect(data.savedBoons, <String>['damage', 'regen', 'damage']);
    });

    test('default to empty when the run was saved without any', () async {
      final data = GameData();
      await data.saveRunState(4, 2, 10, 1.2, 80);
      expect(data.savedBoons, isEmpty);
    });

    test('are cleared along with the rest of the run state', () async {
      final data = GameData();
      await data.saveRunState(4, 2, 10, 1.2, 80, boons: <String>['damage']);
      await data.clearRunState();
      expect(data.savedBoons, isEmpty);
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
