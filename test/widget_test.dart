import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fight_survival/game.dart';
import 'package:fight_survival/managers.dart';
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
      await tester.pumpWidget(GameWidget(game: game));
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
}
