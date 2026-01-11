Android Release Signing

This project supports using a standard Android keystore (`key.jks`) and a `key.properties` file to sign release APKs/AABs.

1) Generate a keystore (example):

```bash
keytool -genkeypair -v -keystore android/key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias your_key_alias
```

2) Create `android/key.properties` at the project root (do NOT commit it):

```
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=your_key_alias
storeFile=android/key.jks
```

3) Add `android/key.properties` and `android/key.jks` to `.gitignore` (do not commit private keys).

4) Build signed release artifacts:

- App bundle (AAB) using production AdMob (if desired):
  flutter build appbundle --release --dart-define=BUNDLE_BUILT=true

- APK release (signed if `key.properties` exists):
  flutter build apk --release

Notes:
- The Gradle config will create a `release` signingConfig when `android/key.properties` exists and will use it for `release` builds.
- If `key.properties` is missing, the build prints a warning and release builds use the debug key (which is what caused the warning you saw earlier).
- Verify the signing of your APK/AAB with `apksigner` or by inspecting the Play Console upload step.
