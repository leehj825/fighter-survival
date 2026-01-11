AdMob integration notes

App ID: `ca-app-pub-4400173019354346~2329249391`
Banner Ad Unit ID: `bannerca-app-pub-4400173019354346/8395964292`

Steps performed in this repository:

1. Added `google_mobile_ads` dependency to `pubspec.yaml`.
2. Added Android meta-data `com.google.android.gms.ads.APPLICATION_ID` in `android/app/src/main/AndroidManifest.xml`.
3. Added `GADApplicationIdentifier` key to `ios/Runner/Info.plist`.
4. Initialized `MobileAds` and integrated a `BannerAd` in `lib/main.dart` (see comments in file).

Notes and reminders:
- Use test ads during development and follow AdMob policies: https://support.google.com/admob/answer/6128543
- Rebuild the app after running `flutter pub get` to pick up native changes.
- Replace test ad unit IDs with your production IDs before release.

Test ID behavior and App Bundle builds:
- A test banner ID (`ca-app-pub-3940256099942544/6300978111`) is included as `AdManager.admobBannerTestId` and is used by default for non-bundle builds and during development.
- To use the production ad unit for App Bundle (AAB) release builds, pass the dart-define flag when building the bundle:

  flutter build appbundle --dart-define=BUNDLE_BUILT=true

- For APK (non-bundle) builds, omit the dart-define so the app will use the test ID by default to avoid accidental policy violations during distribution.
