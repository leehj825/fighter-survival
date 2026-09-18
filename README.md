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
    reach, regen). Boons last for the run only. The XP curve is tuned for
    roughly one level per wave, so the modal appears about once a wave.
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
    enemies, not just elites. The blue shieldBearer blocks hits inside a
    120-degree frontal arc that turns to follow you at a limited rate, so it
    has to be flanked (dashing around it works) -- and the shield shatters
    after three blocks, so it is always killable head-on too.
*   **Boss telegraph**: a boss roots and glows for half a second before
    firing a volley, so it is a dodgeable read rather than a surprise.

### Feel

*   **Combo counter**: kills within ~2 seconds of each other keep a combo
    climbing, shown top-right with a small pop. Cosmetic only — it does not
    change damage or drops.
*   **Hit-stop**: a few frames of freeze on a kill, boss phase change, or
    Second Wind save, scaled to how big the moment was.
*   **Haptics**: light/medium/heavy feedback on dashing, taking a hit,
    killing an enemy, and boss phase changes. Toggle in Settings.
*   **Run records**: best wave, kills and combo persist across runs and show
    on the main menu; the end-of-run summary flags any that were just beaten.

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
*   **Difficulty and progression tuning**: `lib/balance.dart` holds the XP
    curve, wave pacing, enemy scaling, modifier unlock waves, boss phase
    thresholds and the boon pool, all as pure functions covered by
    `test/balance_test.dart`. A regular enemy drops 10 XP, so
    `Balance.xpForLevel` is read in units of roughly ten per kill.
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
