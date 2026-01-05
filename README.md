# Flame Action RPG Prototype

A single-finger Action RPG prototype built with [Flutter](https://flutter.dev) and the [Flame Engine](https://flame-engine.org/).

## Features

*   **Single-Finger Controls**:
    *   **Move**: Drag to move.
    *   **Dash**: Fast swipe/flick to dash (Yellow Triangle).
    *   **Slash**: Circular motion to attack (Spinning Sword).
*   **Visuals**: Neon geometric shapes using `CustomPainter` / Flame `PositionComponent`.

## Getting Started

### 1. Add Platform Support

This repository contains the `lib` and `test` code. To generate the necessary platform folders (Android, iOS, macOS) and install dependencies, run the following command in the project root:

```bash
flutter create .
```

This will create:
*   `android/`
*   `ios/`
*   `macos/`
*   `web/`
*   `linux/`
*   `windows/`

### 2. Install Dependencies

```bash
flutter pub get
```

### 3. Run the Game

**Android:**
```bash
flutter run
```

**macOS:**
```bash
flutter run -d macos
```

**iOS:**
(Requires a Mac with Xcode)
```bash
flutter run -d ios
```

### 4. Build for Release

**Android APK:**
```bash
flutter build apk
```
The APK will be at `build/app/outputs/flutter-apk/app-release.apk`.

**macOS App:**
```bash
flutter build macos
```

## Configuration

*   **Dash Sensitivity**: Adjust `dashVelocityThreshold` in `lib/main.dart` (default: 2500.0).
