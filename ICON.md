App Icon

Place your app icon image at `assets/icon.png` (preferably a square PNG at 512×512 or 1024×1024).

Then generate platform icons using the `flutter_launcher_icons` package (configured in `pubspec.yaml`):

1. Install the package:

   flutter pub get

2. Generate icons:

   flutter pub run flutter_launcher_icons:main

This will replace the Android `mipmap-*` and iOS asset catalog app icons with the provided image.

Notes:
- Use the **test** or placeholder icon while developing; replace with the final high-resolution icon before release.
- Do not commit large/binary assets you don't want in the repo; consider storing the final icon in a secure release branch or an asset pipeline if needed.
