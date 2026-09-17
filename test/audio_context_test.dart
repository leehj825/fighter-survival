import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fight_survival/sound_service.dart';

/// Guards the "do not stop other apps' audio" behaviour.
///
/// The game must mix with whatever the user is already playing. Getting this
/// wrong is invisible in a unit test unless the actual values handed to the
/// platform are checked, because the failure mode was an exception thrown while
/// *building* the context, swallowed by a catch, leaving the plugin on its
/// defaults.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String globalChannel = 'xyz.luan/audioplayers.global';
  const String playerChannel = 'xyz.luan/audioplayers';

  group('buildMixingAudioContext', () {
    test('can be constructed without throwing', () {
      // Regression: `ambient` + an explicit `mixWithOthers` option trips an
      // assertion inside audioplayers, on Android as well as iOS.
      expect(SoundService.buildMixingAudioContext, returnsNormally);
    });

    test('requests no audio focus on Android', () {
      final android = SoundService.buildMixingAudioContext().android;
      // Anything other than `none` (the plugin default is `gain`) makes the
      // plugin request focus, which stops other apps.
      expect(android.audioFocus, AndroidAudioFocus.none);
    });

    test('does not touch global device audio settings on Android', () {
      final android = SoundService.buildMixingAudioContext().android;
      // Both of these are written straight to the global AudioManager by the
      // plugin, so they affect the whole device, not just this app.
      expect(android.isSpeakerphoneOn, isFalse);
      expect(android.audioMode, AndroidAudioMode.normal);
    });

    test('uses a non-interrupting category on iOS', () {
      final ios = SoundService.buildMixingAudioContext().iOS;
      // `ambient` does not interrupt non-mixable apps. `playback` and
      // `soloAmbient` do unless mixWithOthers is set.
      expect(ios.category, AVAudioSessionCategory.ambient);
      expect(ios.options, isNot(contains(AVAudioSessionOptions.duckOthers)));
    });
  });

  group('SoundService.init', () {
    final List<MethodCall> globalCalls = <MethodCall>[];

    setUpAll(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel(globalChannel),
        (call) async {
          globalCalls.add(call);
          return null;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel(playerChannel),
        (call) async => null,
      );

      // The singleton can only be initialised once (its player is `late
      // final`), so this runs for the whole group.
      await SoundService.instance.init().timeout(const Duration(seconds: 20));
    });

    tearDownAll(() async {
      await SoundService.instance.dispose();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel(globalChannel), null);
      messenger.setMockMethodCallHandler(
          const MethodChannel(playerChannel), null);
    });

    test('reports that the mixing context was applied', () {
      expect(SoundService.instance.audioContextApplied, isTrue);
    });

    test('sends the mixing values the native side reads', () {
      final setContextCalls = globalCalls
          .where((call) => call.method == 'setAudioContext')
          .toList();
      expect(setContextCalls, hasLength(1));

      final args =
          (setContextCalls.single.arguments as Map).cast<String, dynamic>();

      // AudioManager.AUDIOFOCUS_NONE == 0. AUDIOFOCUS_GAIN (1) would stop
      // other apps.
      expect(args['audioFocus'], 0);
      expect(args['isSpeakerphoneOn'], false);
      expect(args['audioMode'], 0); // MODE_NORMAL
    });
  });
}
