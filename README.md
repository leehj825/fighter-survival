# Fight Survival

A single-finger Action RPG prototype built with [Flutter](https://flutter.dev) and the [Flame Engine](https://flame-engine.org/).

## Features

*   **Single-Finger Controls**:
    *   **Move**: Drag to move.
    *   **Dash**: Fast swipe/flick to dash (Yellow Triangle).
    *   **Slash**: Circular motion to attack (Spinning Sword).
*   **Visuals**: Neon geometric shapes using `CustomPainter` / Flame `PositionComponent`.

### Progression

*   **Level-up boons**: every level pauses the run and offers three of seven
    upgrades (damage, max HP, move speed, dash cooldown, pickup radius, melee
    reach, regen). Boons last for the run only.
*   **Workshop**: permanent upgrades bought with gems — Hull Strength,
    Thrusters, Orbital Shield, Power Core, Gem Magnet, Prospector and
    Capacitor — plus the Blaster Cannon, Magic Attack and Second Wind
    (one revive per run) unlocks.
*   **Waves**: enemy health and contact damage scale with the wave. An elite
    spawns every 5th wave; every 10th wave a multi-phase boss replaces it,
    gaining radial projectile volleys at two thirds health and summoning adds
    below one third.
*   **Enemy modifiers**: swift, regen, shieldBearer, ghostly, kamikaze and
    summoner are introduced one wave at a time from wave 3 and roll on regular
    enemies, not just elites.

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

*   **Dash Sensitivity**: Adjust `dashVelocityThreshold` in `lib/game.dart` (default: 1000.0).
*   **Difficulty and progression tuning**: `lib/balance.dart` holds the wave
    pacing, enemy scaling, modifier unlock waves, boss phase thresholds and the
    boon pool, all as pure functions covered by `test/balance_test.dart`.
*   **Workshop economy**: costs and effects are defined by the `Upgrade` and
    `Unlock` enums in `lib/managers.dart`. Their `key` values are persisted, so
    they must not be renamed.
*   **Audio**: the game mixes with other apps rather than interrupting them.
    See `SoundService.buildMixingAudioContext` before changing anything there.

## Development

Run the analyzer and the test suite before pushing; CI runs both:

```bash
flutter analyze
flutter test
```
