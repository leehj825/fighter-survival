import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fight_survival/game.dart';
import 'package:fight_survival/managers.dart';
import 'package:fight_survival/balance.dart';
import 'package:fight_survival/sound_service.dart';

/// Boots the real game inside a GameWidget. This is the test that catches a
/// crash in RpgGame.onLoad (asset loading, component wiring, the first frames
/// of the update loop).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const List<String> audioChannels = <String>[
    'xyz.luan/audioplayers',
    'xyz.luan/audioplayers.global',
  ];

  void stubAudioChannels(Future<Object?>? Function(MethodCall)? handler) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in audioChannels) {
      messenger.setMockMethodCallHandler(MethodChannel(name), handler);
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await GameData().init();
    // Belt and braces: SoundService is deliberately left uninitialised here,
    // so its playback calls are no-ops and nothing should reach the plugin.
    stubAudioChannels((call) async => null);
  });

  tearDown(() {
    stubAudioChannels(null);
    expect(SoundService.instance.isInitialized, isFalse,
        reason: 'the game must boot without audio being initialised');
  });

  Future<RpgGame> bootGame(WidgetTester tester, {bool resume = false}) async {
    final game = RpgGame(resumeGame: resume);
    // onLoad reads a real asset, so it needs genuine async progress rather
    // than the fake clock that pump() drives.
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(
        game: game,
        // Flame asserts that an overlay is registered before it can be shown,
        // so the harness has to declare the same names main.dart does.
        overlayBuilderMap: <String, Widget Function(BuildContext, RpgGame)>{
          for (final name in <String>['LevelUp', 'GameOver', 'PauseMenu'])
            name: (context, game) => const SizedBox.shrink(),
        },
      ));
      await game.loaded;
    });
    // Run a few frames of the game loop.
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return game;
  }

  testWidgets('RpgGame loads and runs its update loop', (tester) async {
    final game = await bootGame(tester);

    expect(find.byType(GameWidget<RpgGame>), findsOneWidget);
    expect(game.isLoaded, isTrue);
    expect(game.gameOver, isFalse);
    expect(game.wave, 1);

    // onLoad spawns a wave, obstacles and barrels into the world.
    expect(game.world.children.whereType<Enemy>(), isNotEmpty);
    expect(game.world.children.whereType<Obstacle>(), isNotEmpty);

    // Player starts at full health, derived from the persisted HP upgrades.
    expect(game.player.isLoaded, isTrue);
    expect(game.player.health, game.player.maxHealth);
    expect(game.player.maxHealth, 100);
  });

  testWidgets('resuming a saved run restores the saved health', (tester) async {
    // Regression: savedHealth was written but never read, so a resumed run
    // always started at full health.
    await GameData().saveRunState(5, 3, 12, 1.2, 41);

    final game = await bootGame(tester, resume: true);

    expect(game.wave, 5);
    expect(game.player.level, 3);
    expect(game.player.xp, 12);
    expect(game.player.health, 41);
  });

  testWidgets('a boss spawns on a boss wave', (tester) async {
    expect(Balance.isBossWave(10), isTrue);
    await GameData().saveRunState(10, 1, 0, 1.0, 100);

    final game = await bootGame(tester, resume: true);

    expect(game.wave, 10);
    final bosses = game.world.children.whereType<Boss>();
    expect(bosses, hasLength(1));

    final boss = bosses.first;
    expect(boss.health, Balance.enemyHealth(10, isBoss: true));
    expect(boss.phase, 0);
    // Bosses replace the elite, they do not stack with it.
    expect(
      game.world.children.whereType<Enemy>().where((e) => e.isElite),
      isEmpty,
    );
  });

  testWidgets('levelling up pauses and offers three boons', (tester) async {
    final game = await bootGame(tester);

    expect(game.paused, isFalse);
    expect(game.pendingBoons, isEmpty);

    game.player.gainXp(game.player.xpToNextLevel);
    await tester.pump();

    expect(game.player.level, 2);
    expect(game.paused, isTrue, reason: 'the run pauses for the choice');
    expect(game.pendingBoons, hasLength(3));
    expect(game.pendingBoons.toSet(), hasLength(3), reason: 'distinct');
    expect(game.overlays.isActive('LevelUp'), isTrue);

    final double before = game.player.damageScale;
    game.chooseBoon(Boon.damage);
    await tester.pump();

    expect(game.player.damageScale, greaterThan(before));
    expect(game.pendingBoons, isEmpty);
    expect(game.paused, isFalse, reason: 'the run resumes after choosing');
    expect(game.overlays.isActive('LevelUp'), isFalse);
  });

  testWidgets('several levels at once queue one choice each', (tester) async {
    final game = await bootGame(tester);

    // A big gem can cross several thresholds in one pickup.
    game.player.gainXp(1000);
    await tester.pump();

    expect(game.player.level, greaterThan(2));
    expect(game.pendingBoons, hasLength(3));

    // Each queued level still gets its own pick.
    game.chooseBoon(game.pendingBoons.first);
    await tester.pump();
    expect(game.pendingBoons, hasLength(3), reason: 'next choice is offered');
    expect(game.paused, isTrue);
  });

  testWidgets('Second Wind revives once instead of ending the run',
      (tester) async {
    GameData().addGems(Unlock.revive.cost);
    expect(GameData().buyUnlock(Unlock.revive), isTrue);

    final game = await bootGame(tester);
    final int maxHealth = game.player.maxHealth;

    game.player.takeDamage(9999);
    await tester.pump();

    expect(game.gameOver, isFalse, reason: 'the revive should catch this');
    expect(game.player.health, (maxHealth * 0.5).round());
  });

  testWidgets('regular enemies carry modifiers on later waves',
      (tester) async {
    // Regression: modifiers only ever reached the elite every 5th wave.
    await GameData().saveRunState(30, 1, 0, 1.0, 100);
    final game = await bootGame(tester, resume: true);

    final regulars = game.world.children
        .whereType<Enemy>()
        .where((e) => !e.isElite && !e.isBoss)
        .toList();
    expect(regulars, isNotEmpty);

    final pool = Balance.modifierPool(30).toSet()..add(EnemyModifier.none);
    for (final enemy in regulars) {
      expect(pool, contains(enemy.modifier));
    }
    // With a 45% chance across ~49 spawns, at least one should have rolled.
    expect(
      regulars.where((e) => e.modifier != EnemyModifier.none),
      isNotEmpty,
    );
  });

  /// Spawns an enemy into a booted game and waits for it to load.
  Future<Enemy> spawn(WidgetTester tester, RpgGame game, Enemy enemy) async {
    enemy.position = game.player.position + Vector2(100, 0);
    await tester.runAsync(() async {
      game.world.add(enemy);
      await enemy.loaded;
    });
    return enemy;
  }

  group('shield bearer', () {
    // Regression: the shield was tested against a facing recomputed towards
    // the player every frame, so every player attack counted as frontal and
    // was blocked. The enemy could not be killed at all.
    testWidgets('can always be killed from the front', (tester) async {
      final game = await bootGame(tester);
      final enemy = await spawn(
          tester, game, Enemy(modifier: EnemyModifier.shieldBearer));

      expect(enemy.hasShield, isTrue);
      final int startHealth = enemy.health;
      final Vector2 frontal = enemy.position - game.player.position;

      // The shield soaks a few hits...
      for (int i = 0; i < Enemy.shieldMaxHp; i++) {
        enemy.takeDamage(1, knockbackDir: frontal, invulnerability: 0.0);
      }
      expect(enemy.health, startHealth, reason: 'the shield absorbs these');

      // ...then shatters, and it takes damage head-on from there.
      expect(enemy.hasShield, isFalse, reason: 'the shield must break');
      enemy.takeDamage(1, knockbackDir: frontal, invulnerability: 0.0);
      expect(enemy.health, lessThan(startHealth));
    });

    testWidgets('takes damage when flanked, shield intact', (tester) async {
      final game = await bootGame(tester);
      final enemy = await spawn(
          tester, game, Enemy(modifier: EnemyModifier.shieldBearer));

      final int startHealth = enemy.health;
      // It spawns facing the player, so an attack from the far side lands.
      final Vector2 fromBehind = Vector2(-100, 0);
      enemy.takeDamage(1, knockbackDir: fromBehind, invulnerability: 0.0);

      expect(enemy.hasShield, isTrue, reason: 'no block, so no durability lost');
      expect(enemy.health, lessThan(startHealth));
    });

    testWidgets('is not immune to a nuke, which passes no direction',
        (tester) async {
      final game = await bootGame(tester);
      final enemy = await spawn(
          tester, game, Enemy(modifier: EnemyModifier.shieldBearer));

      enemy.takeDamage(9999);
      expect(enemy.health, 0);
    });
  });

  group('combo and hit-stop', () {
    testWidgets('kills build a combo that lapses after the window',
        (tester) async {
      final game = await bootGame(tester);

      game.registerKill();
      game.registerKill();
      game.registerKill();
      expect(game.combo, 3);
      expect(game.maxCombo, 3);

      // Let the combo window (2.2s) lapse.
      await tester.pump(const Duration(milliseconds: 2300));
      expect(game.combo, 0);
      expect(game.maxCombo, 3,
          reason: 'the best combo of the run is remembered');
    });

    testWidgets(
        'hit-stop freezes the simulation for a beat without blocking real time',
        (tester) async {
      final game = await bootGame(tester);
      final Vector2 before = game.player.position.clone();
      game.player.moveDirection = Vector2(1, 0);

      game.hitStop(0.5);
      await tester.pump(const Duration(milliseconds: 16));
      // The freeze should hold the world still even though real time passed.
      expect(game.player.position, before, reason: 'frozen during hit-stop');

      // Let the freeze fully elapse, then advance again -- movement resumes.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 16));
      expect(game.player.position.x, greaterThan(before.x));
    });
  });

  testWidgets('onGameOver records the run and reports new bests',
      (tester) async {
    final game = await bootGame(tester);
    game.killCount = 7;
    game.combo = 3;
    game.maxCombo = 3;
    game.wave = 4;

    game.player.takeDamage(9999);
    // recordRun's SharedPreferences write completes asynchronously; the
    // overlay is built with a ListenableBuilder on GameData for this reason.
    await tester.pump();

    expect(game.gameOver, isTrue);
    expect(game.lastRunRecords, isNotNull);
    expect(game.lastRunRecords!.newBestWave, isTrue);
    expect(GameData().bestWave, 4);
    expect(GameData().bestKills, 7);
    expect(GameData().bestCombo, 3);
  });

  testWidgets('boons survive Resume, including the restored health',
      (tester) async {
    // Regression: this exact path (Player.onLoad replaying boons after a
    // resume) previously deadlocked the whole game -- an earlier version of
    // this fix awaited the player's own mount from inside RpgGame.onLoad(),
    // which Flame can never resolve before onLoad() itself returns.
    final game = await bootGame(tester);

    game.player.gainXp(game.player.xpToNextLevel);
    await tester.pump();
    expect(game.pendingBoons, isNotEmpty);

    game.chooseBoon(Boon.maxHealth);
    await tester.pump();

    final int maxHealthWithBoon = game.player.maxHealth;
    expect(maxHealthWithBoon, greaterThan(100));

    // Take damage so the restored health is a real mid-run value, not just
    // "full again" -- which the boon's own heal-to-full side effect would
    // paper over.
    game.player.takeDamage(20);
    final int healthBeforeExit = game.player.health;
    game.exitRun();

    final resumedGame = await bootGame(tester, resume: true);

    expect(resumedGame.player.maxHealth, maxHealthWithBoon);
    expect(resumedGame.player.health, healthBeforeExit);
    expect(resumedGame.player.boonsTaken, contains(Boon.maxHealth));
  });
}
