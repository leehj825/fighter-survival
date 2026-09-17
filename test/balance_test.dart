import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fight_survival/balance.dart';

void main() {
  group('wave composition', () {
    test('elites every 5th wave, bosses every 10th, never both', () {
      for (int wave = 1; wave <= 40; wave++) {
        final bool elite = Balance.isEliteWave(wave);
        final bool boss = Balance.isBossWave(wave);
        expect(elite && boss, isFalse,
            reason: 'wave $wave must not be both elite and boss');
        expect(boss, wave % 10 == 0, reason: 'wave $wave boss');
        if (wave % 5 == 0 && wave % 10 != 0) {
          expect(elite, isTrue, reason: 'wave $wave should be an elite wave');
        }
      }
    });

    test('enemy count grows with the wave', () {
      expect(Balance.enemyCount(1), 5);
      expect(Balance.enemyCount(10), greaterThan(Balance.enemyCount(1)));
    });
  });

  group('enemy scaling', () {
    test('wave 1 keeps the original values', () {
      expect(Balance.enemyHealth(1), 2);
      expect(Balance.enemyHealth(1, isElite: true), 100);
      expect(Balance.enemyMeleeDamage(1), 10);
      expect(Balance.enemyMeleeDamage(1, isElite: true), 20);
    });

    test('health increases monotonically with the wave', () {
      int previous = 0;
      for (int wave = 1; wave <= 60; wave++) {
        final int health = Balance.enemyHealth(wave);
        expect(health, greaterThanOrEqualTo(previous), reason: 'wave $wave');
        previous = health;
      }
      // Regression: enemy health used to be a flat 2 forever, so late waves
      // were only ever bigger crowds.
      expect(Balance.enemyHealth(40), greaterThan(Balance.enemyHealth(1)));
    });

    test('bosses are tougher than elites, elites than regulars', () {
      for (final wave in <int>[1, 10, 20, 40]) {
        final int regular = Balance.enemyHealth(wave);
        final int elite = Balance.enemyHealth(wave, isElite: true);
        final int boss = Balance.enemyHealth(wave, isBoss: true);
        expect(elite, greaterThan(regular), reason: 'wave $wave');
        expect(boss, greaterThan(elite), reason: 'wave $wave');
      }
    });

    test('damage scales but stays survivable', () {
      // A player starts with 100 HP; a single hit should never one-shot them.
      for (int wave = 1; wave <= 40; wave++) {
        expect(Balance.enemyMeleeDamage(wave, isBoss: true), lessThan(100),
            reason: 'wave $wave');
      }
    });
  });

  group('enemy modifiers', () {
    test('none are available before wave 3', () {
      expect(Balance.modifierPool(1), isEmpty);
      expect(Balance.modifierPool(2), isEmpty);
      expect(Balance.modifierChance(1), 0.0);
      expect(Balance.modifierChance(2), 0.0);
    });

    test('are introduced one at a time, in order', () {
      expect(Balance.modifierPool(3), <EnemyModifier>[EnemyModifier.swift]);
      expect(Balance.modifierPool(5),
          <EnemyModifier>[EnemyModifier.swift, EnemyModifier.regen]);
      expect(Balance.modifierPool(6).length, 2);
      expect(Balance.modifierPool(7).length, 3);
    });

    test('every modifier eventually becomes reachable on a regular enemy', () {
      // Regression: these behaviours were only ever given to the elite on
      // every 5th wave, so most players never saw them.
      final pool = Balance.modifierPool(100).toSet();
      for (final modifier in EnemyModifier.values) {
        if (modifier == EnemyModifier.none) continue;
        expect(pool, contains(modifier), reason: modifier.name);
      }
    });

    test('chance ramps and then caps', () {
      expect(Balance.modifierChance(3), closeTo(0.04, 1e-9));
      expect(Balance.modifierChance(10), closeTo(0.32, 1e-9));
      expect(Balance.modifierChance(100), closeTo(0.45, 1e-9));
    });

    test('never returns a modifier that is not yet unlocked', () {
      final rng = Random(7);
      for (int wave = 1; wave <= 20; wave++) {
        final allowed = Balance.modifierPool(wave).toSet()
          ..add(EnemyModifier.none);
        for (int i = 0; i < 200; i++) {
          expect(allowed, contains(Balance.rollModifier(wave, rng)),
              reason: 'wave $wave');
        }
      }
    });

    test('stops handing out summoners once the cap is reached', () {
      final rng = Random(3);
      for (int i = 0; i < 500; i++) {
        expect(
          Balance.rollModifier(30, rng, summonersSpawned: 1, maxSummoners: 1),
          isNot(EnemyModifier.summoner),
        );
      }
    });

    test('elites never roll summoner', () {
      // An elite that never stops spawning adds is a stalemate.
      final rng = Random(11);
      for (int i = 0; i < 500; i++) {
        expect(Balance.rollEliteModifier(30, rng),
            isNot(EnemyModifier.summoner));
      }
    });
  });

  group('boss phases', () {
    test('escalate as health drops', () {
      expect(Balance.bossPhase(1.0), 0);
      expect(Balance.bossPhase(0.7), 0);
      expect(Balance.bossPhase(2 / 3), 1);
      expect(Balance.bossPhase(0.5), 1);
      expect(Balance.bossPhase(1 / 3), 2);
      expect(Balance.bossPhase(0.0), 2);
    });
  });

  group('boons', () {
    test('offers three distinct choices', () {
      final rng = Random(1);
      for (int i = 0; i < 100; i++) {
        final boons = Balance.rollBoons(rng);
        expect(boons, hasLength(3));
        expect(boons.toSet(), hasLength(3), reason: 'must be distinct');
      }
    });

    test('never offers more than there are boons', () {
      final boons = Balance.rollBoons(Random(1), count: 99);
      expect(boons, hasLength(Boon.values.length));
    });

    test('every boon can be offered', () {
      final rng = Random(5);
      final seen = <Boon>{};
      for (int i = 0; i < 500; i++) {
        seen.addAll(Balance.rollBoons(rng));
      }
      expect(seen, hasLength(Boon.values.length));
    });

    test('every boon has a title and description', () {
      for (final boon in Boon.values) {
        expect(boon.title, isNotEmpty);
        expect(boon.description, isNotEmpty);
      }
    });
  });
}
