import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fight_survival/game.dart';
import 'package:fight_survival/managers.dart';

/// Boots the real game inside a GameWidget. This is the test that catches a
/// crash in RpgGame.onLoad (asset loading, component wiring, the first frames
/// of the update loop).
///
/// The audio plugin has no implementation under `flutter test`, so its method
/// channels are stubbed out; without that, SoundService leaves pending timers
/// and the harness fails the test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> audioCalls = <MethodCall>[];

  setUp(() async {
    audioCalls.clear();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await GameData().init();

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in <String>[
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        audioCalls.add(call);
        return null;
      });
    }
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in <String>[
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  testWidgets('RpgGame loads and runs its update loop', (tester) async {
    final game = RpgGame();
    // onLoad reads a real asset, so it needs genuine async progress rather
    // than the fake clock pump() drives.
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(game: game));
      await game.loaded;
    });

    expect(find.byType(GameWidget<RpgGame>), findsOneWidget);

    // Run a few frames of the game loop.
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

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

    // Drain the audio service's fade-in timers before the tree is torn down.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('resuming a saved run restores the saved health', (tester) async {
    // Regression: savedHealth was written but never read, so a resumed run
    // always started at full health.
    await GameData().saveRunState(5, 3, 12, 1.2, 41);

    final game = RpgGame(resumeGame: true);
    await tester.runAsync(() async {
      await tester.pumpWidget(GameWidget(game: game));
      await game.loaded;
    });
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(game.wave, 5);
    expect(game.player.level, 3);
    expect(game.player.xp, 12);
    expect(game.player.health, 41);

    await tester.pump(const Duration(seconds: 3));
  });
}
