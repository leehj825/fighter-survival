import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame/input.dart'; // Added to fix TapDetector not found
import 'package:flutter/material.dart' hide Draggable;

import 'hud.dart';
import 'managers.dart';
import 'visual_effects.dart';
import 'sound_service.dart';
import 'stickman_animator.dart'; // Import the new file

/// True when a hit lands on a Shield Bearer's shield.
///
/// [towardsPlayer] points from the enemy to the player (enemies always face the
/// player); [knockbackDir] points from the attacker towards the enemy, which is
/// how every damage source passes it. A frontal hit therefore travels *against*
/// the facing direction, so the dot product is negative.
bool isBlockedByShield(Vector2 towardsPlayer, Vector2 knockbackDir) {
  final Vector2 facing = towardsPlayer.safeNormalized();
  final Vector2 incoming = knockbackDir.safeNormalized();
  if (facing.isZero() || incoming.isZero()) return false;
  return facing.dot(incoming) < 0;
}

/// Shared RNG. Constructing a `Random()` per frame (camera shake) or per call
/// (roam targets, drops) is needless churn.
final Random _rng = Random();

/// Extension for safe vector normalization
extension SafeVector2 on Vector2 {
  Vector2 safeNormalized() {
    if (x.isNaN || y.isNaN || length2 < 1e-6) {
      return Vector2.zero();
    }
    return normalized();
  }
}

/// A simple virtual joystick component
class VirtualJoystick extends PositionComponent with HasVisibility {
  final double knobRadius = 15; // Reduced from 20
  final double baseRadius = 35; // Reduced from 50

  Vector2 _knobPos = Vector2.zero();

  final Paint _basePaint = Paint()..color = Colors.white.withValues(alpha: 0.2)..style = PaintingStyle.fill;
  final Paint _baseStroke = Paint()..color = Colors.white.withValues(alpha: 0.4)..style = PaintingStyle.stroke..strokeWidth = 2;
  final Paint _knobPaint = Paint()..color = Colors.cyanAccent.withValues(alpha: 0.8);

  VirtualJoystick() : super(anchor: Anchor.center, size: Vector2.all(70)) { // Reduced from 100
    isVisible = false;
  }

  void updateKnob(Vector2 delta) {
    if (delta.length > baseRadius) {
      _knobPos = delta.normalized() * baseRadius;
    } else {
      _knobPos = delta;
    }
  }

  void reset() {
    _knobPos = Vector2.zero();
  }

  @override
  void render(Canvas canvas) {
    if (!isVisible) return;

    // Fix: Shift origin to center of the component so visuals align with the touch point
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);

    // Draw Base (centered)
    canvas.drawCircle(Offset.zero, baseRadius, _basePaint);
    canvas.drawCircle(Offset.zero, baseRadius, _baseStroke);

    // Draw Knob (relative to center)
    canvas.drawCircle(_knobPos.toOffset(), knobRadius, _knobPaint);

    canvas.restore();
  }
}

class ActionButton extends PositionComponent with HasVisibility {
  final String label;
  final Color color;
  final Paint _bgPaint;
  final Paint _strokePaint;
  late TextPainter _textPainter;

  ActionButton({required this.label, required this.color})
      : _bgPaint = Paint()..color = color.withValues(alpha: 0.5),
        _strokePaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
        super(anchor: Anchor.center, size: Vector2.all(60)) { // Reduced from 80
    isVisible = false; // Hidden by default, shown when unlocked
  }

  @override
  Future<void> onLoad() async {
    _textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    _textPainter.layout();
  }

  @override
  void render(Canvas canvas) {
    if (!isVisible) return;
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), size.x / 2, _bgPaint);
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), size.x / 2, _strokePaint);

    // Draw Whirlwind Icon instead of Text
    if (label == "SLASH") {
       final Paint iconPaint = Paint()
         ..color = Colors.white.withValues(alpha: 0.9)
         ..style = PaintingStyle.stroke
         ..strokeWidth = 3.0
         ..strokeCap = StrokeCap.round;

       canvas.save();
       canvas.translate(size.x / 2, size.y / 2);
       // Simple spiral
       for(int i=0; i<2; i++) {
          canvas.drawArc(
            Rect.fromCircle(center: Offset.zero, radius: 10 + (i * 8.0)),
            0.5 + (i * 1.0),
            4.0,
            false,
            iconPaint
          );
       }
       canvas.restore();
    } else {
      _textPainter.paint(
        canvas,
        Offset((size.x - _textPainter.width) / 2, (size.y - _textPainter.height) / 2),
      );
    }
  }
}

/// The main Game class.
class RpgGame extends FlameGame with MultiTouchDragDetector { // Removed TapDetector mixin
  final bool resumeGame;
  late Player player;
  late Hud hud;
  late VirtualJoystick joystick;
  late VirtualJoystick rightJoystick; // Right-side joystick for blaster control
  late ActionButton slashButton;

  RpgGame({this.resumeGame = false});

  // Game State
  int killCount = 0;
  int wave = 1;
  double _waveTimer = 0.0;
  bool gameOver = false;

  // Run Session Data
  int runGems = 0;

  // Story Data
  final Map<int, String> storyLog = {
    1: "SIMULATION INITIALIZED.\nSURVIVE THE SWARM.",
    3: "THREAT LEVEL RISING.\nHOSTILES ADAPTING.",
    5: "WARNING: HEAVY SIGNAL.\nELITE UNIT DETECTED.",
    10: "SYSTEM OVERLOAD.\nTHEY ARE EVERYWHERE.",
  };

  // --- Input State ---
  int? _movePointerId;
  int? _actionPointerId;
  int? _rightJoystickPointerId; // For blaster control joystick

  // Movement State
  Vector2? _moveStartPos;
  Vector2? _rightJoystickStartPos;

  // Action Gesture State
  Vector2? _lastActionPos;
  DateTime? _lastActionTime;
  bool _dashTriggered = false; // Track if dash was triggered during this touch
  double _actionTouchDistance = 0.0; // Track total distance moved during action touch
  
  // Shoot direction from right joystick
  Vector2? _shootDirection;
  double _shootAccumulator = 0.0;
  static const double _autoShootInterval = 0.2; // Auto-shoot interval when joystick is held


  // Tweakable Variable for Dash Sensitivity
  static const double dashVelocityThreshold = 1000.0; // Lowered from 2500.0

  // Camera Shake State
  double _shakeTimer = 0.0;
  double _shakeIntensity = 0.0;

  @override
  late World world;
  late CameraComponent cameraComponent;
  String? animationData;

  @override
  Future<void> onLoad() async {
    // Ensure music is playing (but don't restart if it is)
    SoundService.instance.playBackgroundMusic('audio/main2.mp3');

    // Load Animation Data Once
    animationData = await assets.readFile('data/fighter_animations.sap');

    // Create World
    world = World();

    // Initialize Player with Stats from GameData.
    // Health has to be handed to the constructor: Player.onLoad runs when the
    // component is added, and it would otherwise overwrite a restored value.
    final GameData data = GameData();
    final bool resuming = resumeGame && data.hasSavedRun;

    player = Player(restoreHealth: resuming ? data.savedHealth : null);

    if (resuming) {
      wave = data.savedWave;
      player.level = data.savedLevel;
      player.xp = data.savedXp;
      player.damageMult = data.savedDamageMult;
      player.xpToNextLevel = (10 * pow(1.5, player.level - 1)).toInt(); // Recalculate xpToNext
    }

    world.add(player);

    // Add Orbital Shields (If Unlocked/Leveled)
    _spawnShields();

    // Spawn Obstacles (Rough background elements)
    _spawnObstacles();

    // Setup Camera
    cameraComponent = CameraComponent(world: world);
    cameraComponent.viewfinder.anchor = Anchor.center;
    cameraComponent.follow(player); // Locked follow (Bird's Eye is handled by StickmanPainter rotation)
    add(cameraComponent);
    add(world);

    // Add HUD
    hud = Hud();
    add(hud);

    // Add Joystick (On top of HUD or World? HUD is Priority 100. Joystick on top of everything)
    joystick = VirtualJoystick()..priority = 200;
    hud.add(joystick); // Add to HUD (Root Component) to ensure screen-space alignment

    // Add Right Joystick for Blaster (if unlocked)
    // Initialize it but keep it hidden until blaster is unlocked
    rightJoystick = VirtualJoystick()..priority = 200;
    rightJoystick.position = Vector2(size.x - 150, size.y - 150); // Moved inward to avoid overlap with magic button
    rightJoystick.isVisible = GameData().unlockBlaster; // Only visible when blaster is unlocked
    hud.add(rightJoystick);

    // Add Action Buttons
    slashButton = ActionButton(label: "SLASH", color: Colors.redAccent)
      ..priority = 200
      ..position = Vector2(size.x - 80, size.y - 70) // Adjusted for smaller button
      ..isVisible = GameData().unlockMagic; // Only visible when magic is unlocked
    hud.add(slashButton);

    // Initial Wave
    _spawnWave();
  }

  @override
  void onRemove() {
    // SoundService.instance.stopBackgroundMusic(); // Keep music playing
    super.onRemove();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      slashButton.position = Vector2(size.x - 80, size.y - 70); // Adjusted for smaller button
      slashButton.isVisible = GameData().unlockMagic; // Update visibility on resize
      if (rightJoystick.isLoaded) {
        rightJoystick.position = Vector2(size.x - 150, size.y - 150); // Moved inward to avoid overlap with magic button
        rightJoystick.isVisible = GameData().unlockBlaster;
      }
    }
  }

  /// One orbiting shield per purchased level, evenly spaced around the player.
  /// Without this every level past the first was a no-op.
  void _spawnShields() {
    final int level = GameData().levelShield;
    for (int i = 0; i < level; i++) {
      world.add(OrbitalShield(
        player,
        level: level,
        orbitOffset: (2 * pi / level) * i,
      ));
    }
  }

  void _spawnObstacles() {
    final Random rng = _rng;
    // Spawn 20 random obstacles near start
    for (int i = 0; i < 20; i++) {
      bool isBig = rng.nextBool();
      Vector2 pos = Vector2(
        (rng.nextDouble() - 0.5) * 2000,
        (rng.nextDouble() - 0.5) * 2000,
      );
      // Don't spawn on top of player
      if (pos.length > 200) {
        world.add(Obstacle(radius: isBig ? 40 : 20, bodyHeight: isBig ? 60 : 30)
          ..position = pos);
      }
    }

    // Add Barrels randomly
    for (int i = 0; i < 8; i++) {
      Vector2 pos = Vector2(
        (rng.nextDouble() - 0.5) * 1800,
        (rng.nextDouble() - 0.5) * 1800,
      );
      if (pos.length > 200) {
        world.add(Barrel()..position = pos);
      }
    }

    // Add Spike Traps
    for (int i = 0; i < 5; i++) {
      Vector2 pos = Vector2(
        (rng.nextDouble() - 0.5) * 1800,
        (rng.nextDouble() - 0.5) * 1800,
      );
      if (pos.length > 200) {
        world.add(SpikeTrap()..position = pos);
      }
    }
  }

  void cameraShake(double intensity) {
    _shakeTimer = 0.4;
    _shakeIntensity = intensity;
  }

  void _spawnWave() {
    // Story Display
    if (storyLog.containsKey(wave)) {
      hud.showStory(storyLog[wave]!);
    } else {
      hud.showStory("WAVE $wave");
    }

    final Random rng = _rng;
    int enemyCount = 4 + (wave * 1.5).toInt();
    bool isEliteWave = wave % 5 == 0;

    for (int i = 0; i < enemyCount; i++) {
      Vector2 pos = player.position + Vector2(
        (rng.nextDouble() - 0.5) * 800 + (rng.nextBool() ? 500 : -500),
        (rng.nextDouble() - 0.5) * 800 + (rng.nextBool() ? 500 : -500),
      );

      // 20% Shooter chance, or alternating in Elite waves
      bool isShooter = rng.nextDouble() < 0.2 || (isEliteWave && i % 2 == 0);

      if (isShooter) {
        world.add(ShooterEnemy()..position = pos);
      } else {
        world.add(Enemy()..position = pos);
      }
    }

    if (isEliteWave) {
      // Spawn Boss
      // Randomly pick a modifier
      final modifier = EnemyModifier.values[rng.nextInt(EnemyModifier.values.length)];
      world.add(Enemy(isElite: true, modifier: modifier)..position = player.position + Vector2(600, 0));
      hud.showBossWarning();
    }
  }

  @override
  void update(double dt) {
    // Failsafe: Recover from NaN position to prevent freeze
    if (player.position.x.isNaN || player.position.y.isNaN) {
      player.position = Vector2(0, 0);
    }

    // Camera Shake Logic
    if (_shakeTimer > 0) {
      _shakeTimer -= dt;
      final double offX = (_rng.nextDouble() - 0.5) * 0.025 * _shakeIntensity;
      final double offY = (_rng.nextDouble() - 0.5) * 0.025 * _shakeIntensity;
      cameraComponent.viewfinder.anchor = Anchor(0.5 + offX, 0.5 + offY);
    } else {
      cameraComponent.viewfinder.anchor = Anchor.center;
    }

    super.update(dt);
    if (gameOver) return;

    // --- AUTO FIRE ---
    // Driven by the game clock, so holding the stick still keeps firing. This
    // used to live in onDragUpdate, which only runs when the pointer moves.
    if (_shootDirection != null) {
      _shootAccumulator -= dt;
      if (_shootAccumulator <= 0) {
        _shootAccumulator = _autoShootInterval;
        player.shoot(_shootDirection!);
      }
    }

    // --- SINGLE PASS OVER THE WORLD ---
    // Y-sorting and all the collision tests below share one walk of the child
    // list, replacing the five separate scans (plus a nested rescan for every
    // obstacle) this used to do.
    final List<Enemy> enemies = <Enemy>[];
    final List<Obstacle> obstacles = <Obstacle>[];
    final List<Barrel> barrels = <Barrel>[];
    final List<XpGem> gems = <XpGem>[];

    for (final child in world.children) {
      if (child is PositionComponent) {
        // Sort components by Y position for depth (2.5D view)
        child.priority = child.position.y.toInt();
      }
      if (child is Enemy) {
        enemies.add(child);
      } else if (child is Obstacle) {
        obstacles.add(child);
      } else if (child is Barrel) {
        barrels.add(child);
      } else if (child is XpGem) {
        gems.add(child);
      }
    }

    // Next wave once every enemy is dead (Base Enemy + ShooterEnemy)
    if (enemies.isEmpty) {
      _waveTimer += dt;
      if (_waveTimer > 3.0) {
        wave++;
        _spawnWave();
        _waveTimer = 0.0;
      }
    }

    // --- XP COLLECTION ---
    for (final gem in gems) {
      bool collected = false;
      if (gem.isMagnetized) {
        // Fast magnetic pull
        gem.position.add((player.position - gem.position).safeNormalized() * 800 * dt);
        collected = player.position.distanceTo(gem.position) < 20;
      } else if (player.position.distanceTo(gem.position) < 100) {
        // Normal magnetic pull
        gem.position.add((player.position - gem.position).safeNormalized() * 300 * dt);
        collected = player.position.distanceTo(gem.position) < 10;
      }

      if (collected) {
        runGems += gem.amount;
        player.gainXp(gem.amount);
        gem.removeFromParent();
      }
    }

    // --- OBSTACLE COLLISION ---
    for (final obstacle in obstacles) {
      _pushApart(player, obstacle);
      for (final enemy in enemies) {
        // Ghostly enemies can pass through obstacles
        if (enemy.modifier != EnemyModifier.ghostly) {
          _pushApart(enemy, obstacle);
        }
      }
    }

    // --- BARREL COLLISION ---
    for (final barrel in barrels) {
      if (player.position.distanceTo(barrel.position) <
          (player.size.x / 2) + barrel.radius) {
        barrel.takeDamage(); // Explode on contact
      }
    }

    // --- COMBAT ---
    for (final enemy in enemies) {
      final double dist = player.position.distanceTo(enemy.position);
      final double combinedRadius = (player.size.x / 2) + (enemy.size.x / 2);
      final Vector2 awayFromPlayer = enemy.position - player.position;

      // Check DASH Hit
      if (player.isDashing && dist < (combinedRadius + 10)) {
        enemy.takeDamage((20 * player.damageMult).toInt(),
            knockbackDir: awayFromPlayer);
      }

      // Check SLASH Hit (Magic)
      if (player.isSlashing && dist < (combinedRadius + 60)) {
        enemy.takeDamage((10 * player.damageMult).toInt(),
            knockbackDir: awayFromPlayer);
      }

      // Check PLAYER DAMAGE Hit (Enemy Melee)
      if (!player.isDashing && dist < combinedRadius) {
        // Elite enemies deal more damage
        player.takeDamage(enemy.isElite ? 20 : 10, fromEnemyMelee: true);
      }
    }
  }

  /// Resolves an overlap by pushing [body] out of [obstacle].
  void _pushApart(PositionComponent body, Obstacle obstacle) {
    final double dist = body.position.distanceTo(obstacle.position);
    final double minDist = (body.size.x / 2) + obstacle.radius;
    if (dist >= minDist) return;

    Vector2 dir = body.position - obstacle.position;
    if (dir.x.isNaN || dir.y.isNaN) return;
    // Prevent getting stuck if center positions overlap exactly
    if (dir.length2 < 0.001) dir = Vector2(1, 0);

    final Vector2 push = dir.safeNormalized() * (minDist - dist);
    if (!push.x.isNaN && !push.y.isNaN) {
      body.position += push;
    }
  }

  // --- MULTI-TOUCH INPUT HANDLING ---

  @override
  void onDragStart(int pointerId, DragStartInfo info) {
    if (gameOver) {
       return; // Do nothing, wait for UI button
    }

    final Vector2 startPos = info.eventPosition.widget;

    // 1. Check Button first
    // Only allow slash if magic is unlocked and button is visible
    if (GameData().unlockMagic && slashButton.isVisible && slashButton.containsPoint(startPos - hud.position)) {
        player.slash(); // Fixed: Handle slash here
        return;
    }

    // 2. Assign Movement Pointer (Left side)
    if (_movePointerId == null && startPos.x < size.x / 2) {
      _movePointerId = pointerId;
      _moveStartPos = startPos;

      // Show Joystick
      joystick.position = startPos;
      joystick.isVisible = true;
      joystick.reset();
    }
    // 2b. Assign Right Joystick Pointer (Right side, for blaster control)
    // Only if touch is specifically near the joystick position
    bool assignedToRightJoystick = false;
    if (GameData().unlockBlaster && _rightJoystickPointerId == null && 
        startPos.x > size.x / 2 && !slashButton.containsPoint(startPos - hud.position)) {
      final Vector2 joystickPos = rightJoystick.position;
      if (startPos.distanceTo(joystickPos) < 100) { // Within joystick activation radius
        _rightJoystickPointerId = pointerId;
        _rightJoystickStartPos = joystickPos; // Fixed position
        rightJoystick.reset();
        assignedToRightJoystick = true;
      }
    }
    
    // 3. Assign Action Pointer (Right side, Swipe for Dash or Tap to Attack)
    // This should work even when blaster is unlocked (for dash swipes)
    // Only assign if not already assigned to right joystick
    if (!assignedToRightJoystick && _actionPointerId == null && 
        startPos.x > size.x / 2 && !slashButton.containsPoint(startPos - hud.position)) {
      _actionPointerId = pointerId;
      _lastActionPos = startPos;
      _lastActionTime = DateTime.now();
      _dashTriggered = false; // Reset dash flag
      _actionTouchDistance = 0.0; // Reset distance tracking
      // Do NOT call tapAttack() here - wait for release
    }
  }

  @override
  void onDragUpdate(int pointerId, DragUpdateInfo info) {
    if (gameOver) return;

    final Vector2 currentPos = info.eventPosition.widget;

    // Handle Movement
    if (pointerId == _movePointerId && _moveStartPos != null) {
      final Vector2 offset = currentPos - _moveStartPos!;
      joystick.updateKnob(offset);

      if (offset.length > 5) {
        player.moveDirection = offset.safeNormalized();
      } else {
        player.moveDirection = Vector2.zero();
      }
    }

    // Handle Right Joystick (Blaster Control)
    if (pointerId == _rightJoystickPointerId && _rightJoystickStartPos != null) {
      final Vector2 offset = currentPos - _rightJoystickStartPos!;
      rightJoystick.updateKnob(offset);

      if (offset.length > 5) {
        final Vector2 dir = offset.safeNormalized();
        // Fire at once when the stick is first pushed; update() then keeps
        // firing every _autoShootInterval for as long as it is held.
        if (_shootDirection == null) {
          _shootAccumulator = _autoShootInterval;
          player.shoot(dir);
        }
        _shootDirection = dir;
      } else {
        _shootDirection = null;
      }
    }

    // Handle Dash Swipe
    if (pointerId == _actionPointerId && _lastActionPos != null) {
      // 1. Calculate distance from the LAST RECORDED position
      final double dist = currentPos.distanceTo(_lastActionPos!);
      
      // Track total distance moved
      _actionTouchDistance += dist;

      // 2. CRITICAL CHANGE: Only process if moved enough (> 10 pixels)
      // If we moved less, we RETURN immediately.
      // We do NOT update _lastActionPos, allowing movement to accumulate over multiple frames.
      if (dist < 10) return;

      final DateTime now = DateTime.now();
      if (_lastActionTime != null) {
        final double dtSeconds = now.difference(_lastActionTime!).inMicroseconds / 1000000.0;
        
        // Ensure strictly positive time to avoid division by zero
        if (dtSeconds > 0.001) { 
          final double velocity = dist / dtSeconds;

          // Check velocity
          if (velocity > dashVelocityThreshold) {
             Vector2 dashDir = currentPos - _lastActionPos!;
             if (!dashDir.isNaN) {
                player.dash(dashDir);
                _dashTriggered = true; // Mark that dash was triggered
             }
          }
        }
      }
      
      // 3. Reset state ONLY after we processed a significant chunk of movement
      _lastActionPos = currentPos;
      _lastActionTime = now;
    }
  }

  @override
  void onDragEnd(int pointerId, DragEndInfo info) {
    _handleTouchEnd(pointerId);
  }

  @override
  void onDragCancel(int pointerId) {
    _handleTouchEnd(pointerId);
  }

  void _handleTouchEnd(int pointerId) {
    if (pointerId == _movePointerId) {
      _movePointerId = null;
      _moveStartPos = null;
      player.moveDirection = null;
      joystick.isVisible = false;
    }

    if (pointerId == _rightJoystickPointerId) {
      _rightJoystickPointerId = null;
      _rightJoystickStartPos = null;
      _shootDirection = null;
      _shootAccumulator = 0.0;
      rightJoystick.reset();
    }

    if (pointerId == _actionPointerId) {
      // Only trigger punch if:
      // 1. Dash was NOT triggered (was a tap, not a swipe)
      // 2. Total distance moved was small (was a tap, not a drag)
      // 3. Player is NOT currently dashing
      // Note: Punch works even when blaster is unlocked (right joystick is for shooting, action pointer is for dash/punch)
      if (!_dashTriggered && 
          _actionTouchDistance < 50 && 
          !player.isDashing) {
        player.tapAttack();
      }
      
      _actionPointerId = null;
      _lastActionPos = null;
      _dashTriggered = false;
      _actionTouchDistance = 0.0;
    }
  }

  /// Restarts the run in place. Reachable from the Game Over overlay.
  void restartRun() {
    gameOver = false;
    killCount = 0;
    wave = 1;
    runGems = 0;
    _waveTimer = 0.0;
    _shakeTimer = 0.0;
    _shootDirection = null;
    _shootAccumulator = 0.0;

    player.resetForNewRun();
    player.position = Vector2.zero();

    // Clear the world, keeping the player (and its child components) alive.
    for (final child in world.children.toList()) {
      if (child != player) child.removeFromParent();
    }

    hud.storyText.text = "";
    _spawnObstacles(); // Respawn obstacles and barrels
    _spawnShields(); // Respawn shields with current stats
    _spawnWave();

    overlays.remove('GameOver');
  }

  void onGameOver() {
    // Guard against re-entry: components keep updating after death, so traps
    // and projectiles could otherwise re-trigger this and bank runGems again.
    if (gameOver) return;
    gameOver = true;
    GameData().addGems(runGems);
    GameData().clearRunState(); // Clear save on death
    overlays.add('GameOver');
  }

  void exitRun() {
    GameData().addGems(runGems);
    // Save state for Resume
    if (!gameOver) {
      GameData().saveRunState(wave, player.level, player.xp, player.damageMult, player.health);
    } else {
      GameData().clearRunState();
    }
  }
}

class Obstacle extends PositionComponent {
  final double radius;

  /// Drawn cylinder height. Named to avoid shadowing PositionComponent.height,
  /// which is size.y.
  final double bodyHeight;

  static final Paint _shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.3);
  static final Paint _bodyPaint = Paint()..color = Colors.grey.shade700;
  static final Paint _topPaint = Paint()..color = Colors.grey.shade400;
  static final Paint _rimPaint = Paint()
    ..style = PaintingStyle.stroke
    ..color = Colors.white.withValues(alpha: 0.3);

  Obstacle({required this.radius, required this.bodyHeight})
      : super(anchor: Anchor.center, size: Vector2.all(radius * 2));

  @override
  void render(Canvas canvas) {
    // 2.5D Cylinder Render
    final Offset center = (size / 2).toOffset();
    final double r = radius;
    final double h = bodyHeight;

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: center, width: width, height: width * 0.6),
      _shadowPaint,
    );

    // Body
    final Offset topCenter = center + Offset(0, -h);
    final Path bodyPath = Path();
    bodyPath.moveTo(center.dx - r, center.dy);
    bodyPath.lineTo(center.dx + r, center.dy);
    bodyPath.lineTo(topCenter.dx + r, topCenter.dy);
    bodyPath.lineTo(topCenter.dx - r, topCenter.dy);
    bodyPath.close();
    canvas.drawPath(bodyPath, _bodyPaint);

    // Top
    canvas.drawCircle(topCenter, r, _topPaint);
    // Rim
    canvas.drawCircle(topCenter, r, _rimPaint);
  }
}

class Player extends PositionComponent with HasGameReference<RpgGame> {
  // ... Keep existing stats (health, level, etc) ...
  Vector2? moveDirection;
  static const double _baseSpeed = 200.0;
  static const double _dashSpeedMult = 3.5;

  late int health;
  late int maxHealth;
  double _damageCooldown = 0.0;
  int level = 1;
  int xp = 0;
  int xpToNextLevel = 10;
  double damageMult = 1.0;
  late double dashCooldownMax;

  bool isDashing = false;
  double _dashTimer = 0.0;
  static const double _dashDuration = 0.32;
  double _currentDashCooldown = 0.0;
  double get currentDashCooldown => _currentDashCooldown;

  Vector2 _dashDirection = Vector2.zero();
  double _trailTimer = 0.0;
  static const double _trailInterval = 0.05;
  bool isSlashing = false;
  double _shootCooldown = 0.0;
  static const double _shootCooldownTime = 0.15; // Time between shots
  
  // Frenzy power-up state
  double _frenzyTimer = 0.0;
  bool get isFrenzyActive => _frenzyTimer > 0.0;
  double get frenzySpeedMult => isFrenzyActive ? 2.0 : 1.0; // Double animation speed

  // Animation alternation state
  bool _useRoundKick = true; // Alternate between Round Kick and Roundhouse Kick
  String _dashClipName = "Round Kick"; // Chosen once per dash, not per frame
  bool _useHook = true; // Alternate between Hook and Hook Punch
  
  // Attack state to prevent stacking
  bool _isTapAttacking = false;

  // NEW: Track facing direction for aiming attacks (Default right)
  Vector2 _facingDirection = Vector2(1, 0);

  // NEW: Animator
  late StickmanAnimator _animator;

  final Paint _shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.3);

  /// Health to restore when resuming a saved run; null starts at full health.
  final int? restoreHealth;

  Player({this.restoreHealth})
      : super(size: Vector2.all(60), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    super.onLoad();
    // ... Keep existing stat initialization ...
    final data = GameData();
    maxHealth = 100 + (data.levelHp * 20);
    health = (restoreHealth ?? maxHealth).clamp(1, maxHealth);
    dashCooldownMax = 0.8 * pow(0.9, data.levelDash);

    // Initialize the animator with the loaded data from GameRef
    _animator = StickmanAnimator(
      color: Colors.cyanAccent,
      scale: 1.2,
      attackType: AttackType.kick,
      weaponType: WeaponType.none,
      data: game.animationData // Pass the loaded data here
    );

    // Set default animation
    _animator.play("idle");

    // Add Dash Cooldown Bar
    add(DashCooldownBar(this)..position = Vector2(size.x / 2, -10));
  }

  @override
  void update(double dt) {
    super.update(dt);

    // ... Keep existing cooldown logic ...
    if (_damageCooldown > 0) _damageCooldown -= dt;
    if (_currentDashCooldown > 0) _currentDashCooldown -= dt;
    if (_shootCooldown > 0) _shootCooldown -= dt;
    if (_frenzyTimer > 0) _frenzyTimer -= dt;

    Vector2 velocity = Vector2.zero();

    if (isDashing) {
      _dashTimer -= dt;
      double progress = (1.0 - (_dashTimer / _dashDuration)).clamp(0.0, 1.0);
      double currentSpeedMult = _dashSpeedMult * (1.0 - Curves.easeOutCubic.transform(progress) * 0.7);

      velocity = _dashDirection * (_baseSpeed * currentSpeedMult);
      position.add(velocity * dt);

      // Accumulate: `_dashTimer % 0.05 < dt` spawned zero or several trails
      // depending on where the frame boundary happened to land.
      _trailTimer -= dt;
      if (_trailTimer <= 0) {
        _trailTimer = _trailInterval;
        double dashAngle = 0;
        if (_dashDirection != Vector2.zero()) {
          dashAngle = atan2(_dashDirection.y, _dashDirection.x);
        }
        game.world.add(VisualEffects.createDashTrail(position, dashAngle));
      }
      if (_dashTimer <= 0) {
        isDashing = false;
        // Do not reset angle, Animator handles rotation now
      }
    } else if (moveDirection != null && moveDirection != Vector2.zero()) {
      velocity = moveDirection! * _baseSpeed;
      position.add(velocity * dt);
      
      // NEW: Update facing direction when moving
      if (velocity.length > 0) {
        _facingDirection = velocity.normalized();
      }
    }

    // Update Animator
    _animator.isAttacking = isSlashing;

    // Check if tap attack animation is actively playing based on our flag
    bool isTapAttackPlaying = _isTapAttacking;
    
    // Don't reset here - let the animation complete fully
    // The reset timer in tapAttack() will handle it

    // Determine Animation
    if (isDashing) {
      // The clip name is fixed for the whole dash. Alternating it here flipped
      // it every frame, which restarted the animation on every tick.
      _animator.play(_dashClipName);
    } else if (isSlashing) {
      _animator.play("magic");
    } else if (isTapAttackPlaying) {
      // Do nothing, let the punch play out.
      // The Reset logic in tapAttack() handles returning to state.
    } else if (velocity.length > 5) {
      _animator.play("running");
    } else {
      _animator.play("idle");
    }

    // SPEED UP PUNCH: If attacking, pass a faster DT to the animator
    // Note: Animation is already 2.5x faster in stickman_animator.dart (fps * 2.5)
    // So we apply a moderate additional boost for even faster completion
    double animDt = dt;
    if (isTapAttackPlaying) {
      animDt = dt * 2.0; // 2x additional speed (total ~5x faster than original)
    }

    // Pass velocity to animator for direction calculation (3D facing)
    _animator.update(animDt, velocity, isDashing);
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(center: (size / 2).toOffset() + const Offset(0, 20), width: width, height: width * 0.3),
      _shadowPaint,
    );
    // Render facing direction for debug if needed? No, just render animator.
    _animator.render(canvas, Vector2(size.x / 2, size.y / 2 + 10), size.y, isDashing: isDashing);
  }

  // ... Keep existing methods (dash, slash, shoot, gainXp, etc) ...
  void dash(Vector2 direction) {
    if (isDashing || _currentDashCooldown > 0) return;
    isDashing = true;
    isSlashing = false; // Reset slash if dashing
    _dashTimer = _dashDuration;
    _trailTimer = 0.0;
    _dashClipName = _useRoundKick ? "Round Kick" : "Roundhouse Kick";
    _useRoundKick = !_useRoundKick;
    // Frenzy halves cooldown
    _currentDashCooldown = dashCooldownMax / (isFrenzyActive ? 2.0 : 1.0);

    if (direction.length > 0) {
      _dashDirection = direction.safeNormalized();
      _facingDirection = _dashDirection; // Face dash direction
    } else {
      _dashDirection = Vector2(1, 0);
    }
    
    // Show dash impact effect
    final dashImpact = DashImpactEffect();
    dashImpact.position = size / 2;
    add(dashImpact);
  }

  void slash() {
    // Check if magic is unlocked
    if (!GameData().unlockMagic) return;
    
    if (isSlashing || isDashing) return;
    isSlashing = true;
    _animator.isAttacking = true;
    _animator.attackType = AttackType.kick; // Ensure it kicks

    // Use Hurricane Effect instead of Sword
    final hurricane = HurricaneKickEffect();
    // Match visual offset of stickman (centered horizontally, shifted down 10px vertically)
    hurricane.position = size / 2 + Vector2(0, 10);
    add(hurricane);

    // Play swoosh sound if available
    // SoundService.instance.playSwoosh();
  }

  // ... shoot, gainXp, _levelUp, takeDamage same as before ...
  // Be sure to verify takeDamage logic is preserved
  void shoot(Vector2 dir) {
    if (_shootCooldown > 0) return; // Prevent spam
    // Frenzy halves cooldown
    _shootCooldown = _shootCooldownTime / (isFrenzyActive ? 2.0 : 1.0);
    
    // Face shooting direction
    if (dir != Vector2.zero()) _facingDirection = dir.normalized();

    int sfxType = damageMult > 1.5 ? 1 : 0;
    SoundService.instance.playShoot(variant: sfxType);
    game.world.add(PlayerProjectile(position, dir, damageMult));
  }

  void tapAttack() {
    // 1. DISABLE PUNCH WHILE DASHING
    if (isDashing) return;

    // 2. Prevent Stacking: If already punching, ignore new taps
    if (_isTapAttacking) return;
    _isTapAttacking = true;
    
    // Play Animation
    final String animName = _useHook ? "Hook" : "Hook Punch";
    _animator.play(animName);
    _useHook = !_useHook;
    _animator.isAttacking = true;
    
    // 2. Directional Damage Logic
    for (final child in game.world.children) {
      if (child is Enemy) {
        final Vector2 toEnemy = child.position - position;
        final double dist = toEnemy.length;
        final double combinedRadius = (size.x / 2) + (child.size.x / 2);
        
        // Range check (Punch range ~40)
        if (dist < (combinedRadius + 40)) {
          // Direction Check: Dot Product
          // 1.0 = Directly in front, 0.0 = Side, -1.0 = Behind
          // > 0.3 is roughly a 140-degree cone in front
          Vector2 dirToEnemy = toEnemy.normalized();
          double dot = _facingDirection.dot(dirToEnemy);
          
          if (dot > 0.3) { // 0.3 is a generous frontal cone (~140 degrees)
             child.takeDamage((15 * damageMult).toInt(),
                 knockbackDir: toEnemy, invulnerability: 0.05);
          }
        }
      }
    }
    
    // Visual Effect
    // Offset impact effect slightly forward to indicate direction
    final punchImpact = PunchImpactEffect();
    punchImpact.position = (size / 2) + (_facingDirection * 20); 
    add(punchImpact);
    
    // 3. RESET: Wait for animation to complete fully
    // Animation is ~300ms at normal speed
    // With 2.5x fps boost in animator + 2.0x dt boost = ~60ms total
    // Wait 200ms to ensure it completes fully and shows the full animation
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!isRemoved && _isTapAttacking) {
        _animator.isAttacking = false;
        _isTapAttacking = false;
        
        // Force transition to idle/running if not already in another animation
        if (!isDashing && !isSlashing) {
          if (moveDirection != null && moveDirection!.length > 0.1) {
            _animator.play("running");
          } else {
            _animator.play("idle");
          }
        }
      }
    });
  }

  /// Resets per-run state so a restart does not inherit the previous run.
  void resetForNewRun() {
    health = maxHealth;
    level = 1;
    xp = 0;
    xpToNextLevel = 10;
    damageMult = 1.0;
    isDashing = false;
    isSlashing = false;
    _isTapAttacking = false;
    _dashTimer = 0.0;
    _currentDashCooldown = 0.0;
    _damageCooldown = 0.0;
    _frenzyTimer = 0.0;
    moveDirection = null;
    _animator.isAttacking = false;
    _animator.play("idle");
  }

  void gainXp(int amount) {
    xp += amount;
    if (xp >= xpToNextLevel) _levelUp();
  }

  void _levelUp() {
    xp -= xpToNextLevel;
    level++;
    xpToNextLevel = (xpToNextLevel * 1.5).toInt();
    damageMult += 0.1;
    health = maxHealth;
    game.hud.showStory("LEVEL UP!");
    SoundService.instance.playLevelUp();
    game.world.add(VisualEffects.createExplosion(position));
  }

  void takeDamage(int amount, {bool fromEnemyMelee = false}) {
    // Already dead: components keep ticking after game over, so without this
    // a trap or projectile would drive health negative and re-fire onGameOver.
    if (health <= 0) return;

    // Dash invincibility only works against enemy melee attacks
    // Not against traps, arrows, projectiles, or other sources
    if (_damageCooldown > 0) return;
    
    // Dash protects against enemy melee attacks only
    if (isDashing && fromEnemyMelee) {
      return; // Invincible to enemy melee while dashing
    }
    
    // Apply damage (either not dashing, or dashing but hit by non-melee source)
    SoundService.instance.playDamage();
    health -= amount;
    _damageCooldown = 1.0;
    game.cameraShake(2.0);
    game.world.add(DamageText(amount, position, isCrit: true));
    if (health <= 0) {
      health = 0;
      game.onGameOver();
    }
  }
}

class PlayerProjectile extends PositionComponent with HasGameReference<RpgGame> {
  final Vector2 velocity;
  final double damageMult;
  double _lifeTime = 0.0;

  PlayerProjectile(Vector2 pos, Vector2 dir, this.damageMult)
      : velocity = dir * 400,
        super(position: pos, size: Vector2.all(10), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    position += velocity * dt;
    _lifeTime += dt;
    if (_lifeTime > 2.0) removeFromParent();

    // Collision with Enemies
    for (final child in game.world.children) {
      if (child is Enemy) {
        if (child.position.distanceTo(position) < (child.size.x / 2 + 5)) {
          child.takeDamage((5 * damageMult).toInt(),
              knockbackDir: velocity, invulnerability: 0.05);
          removeFromParent();
          break; // Projectile destroyed
        }
      } else if (child is Barrel) {
          if (child.position.distanceTo(position) < (child.size.x / 2 + 5)) {
            child.takeDamage();
            removeFromParent();
            break;
          }
      }
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawCircle(Offset.zero, 5, Paint()..color = Colors.cyanAccent);
  }
}

class Enemy extends PositionComponent with HasGameReference<RpgGame> {
  // ... Stats ...
  int health = 2;
  static const double _speed = 100.0;
  Vector2? _roamTarget;
  double _roamTimer = 0.0;
  Vector2 _knockbackVelocity = Vector2.zero();
  double _invulnerableTimer = 0.0;
  bool isElite = false;
  final EnemyModifier modifier;
  double _regenTimer = 0.0;
  int _maxHealth = 2;
  
  // Summoner state
  double _summonTimer = 0.0;
  static const double _summonInterval = 4.0; // Spawn every 4 seconds
  
  // Kamikaze pulse timer
  double _pulseTimer = 0.0;

  // NEW: Animator
  late StickmanAnimator _animator;

  static final Paint _shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.3);
  static final Paint _flashPaint = Paint()..color = const Color(0x88FFFFFF);

  Enemy({this.isElite = false, this.modifier = EnemyModifier.none})
      : super(size: Vector2.all(isElite ? 100 : 50), anchor: Anchor.center) {
     if(isElite) {
       health = health * 50; // Increased from 30 to 50 (60 -> 100 HP)
     }
     _maxHealth = health;
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    // Choose color/scale based on type
    // Weapons are intentionally not rendered for any enemy, so only the
    // colour and scale are chosen here.
    Color c = Colors.redAccent;
    double s = 1.0;

    if (isElite) {
      c = Colors.deepPurpleAccent;
      s = 2.0;
    } else if (modifier == EnemyModifier.swift) {
      c = Colors.yellowAccent;
    } else if (modifier == EnemyModifier.ghostly) {
      c = Colors.white.withValues(alpha: 0.5);
    } else if (modifier == EnemyModifier.kamikaze) {
      c = Colors.red;
    } else if (modifier == EnemyModifier.shieldBearer) {
      c = Colors.blue;
    } else if (modifier == EnemyModifier.summoner) {
      c = Colors.green;
    }

    // Initialize Animator with shared data
    _animator = StickmanAnimator(
      color: c,
      scale: s,
      weaponType: WeaponType.none, // Remove weapon (sword) image for everyone per request
      data: game.animationData
    );

    // Set default animation
    _animator.play("idle");
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_invulnerableTimer > 0) _invulnerableTimer -= dt;
    if (modifier == EnemyModifier.kamikaze) _pulseTimer += dt;

    // ... Regen logic ...
    if (modifier == EnemyModifier.regen && health < _maxHealth && health > 0) {
        _regenTimer += dt;
        if (_regenTimer >= 1.0) {
            _regenTimer = 0;
            health++;
        }
    }

    Vector2 velocity = Vector2.zero();
    double distToPlayer = position.distanceTo(game.player.position);

    // Special behaviors for new enemy types
    if (modifier == EnemyModifier.kamikaze) {
      // Kamikaze: Move very fast directly at player
      if (distToPlayer > 5) {
        Vector2 dir = (game.player.position - position).safeNormalized();
        velocity = dir * (_speed * 2.0); // Double speed
        position.add(velocity * dt);
        
        // Explode on contact (enemy melee attack)
        if (distToPlayer < (size.x / 2 + game.player.size.x / 2)) {
          game.player.takeDamage(30, fromEnemyMelee: true);
          takeDamage(9999); // Kill self
          game.world.add(VisualEffects.createExplosion(position, scale: 2.0));
          return; // Exit early since we're dead
        }
      }
    } else if (modifier == EnemyModifier.summoner) {
      // Summoner: Maintain distance, spawn enemies
      _summonTimer += dt;
      if (_summonTimer >= _summonInterval) {
        _summonTimer = 0.0;
        // Spawn a basic enemy nearby
        final Random rng = _rng;
        Vector2 spawnPos = position + Vector2(
          (rng.nextDouble() - 0.5) * 100,
          (rng.nextDouble() - 0.5) * 100,
        );
        game.world.add(Enemy()..position = spawnPos);
      }
      
      // Flee if too close
      if (distToPlayer < 200) {
        Vector2 fleeDir = (position - game.player.position).safeNormalized();
        velocity = fleeDir * (_speed * 0.7); // Slower movement
        position.add(velocity * dt);
      } else {
        // Normal roaming
        _roamTimer -= dt;
        if (_roamTimer <= 0 || _roamTarget == null) _pickNewTarget();
        if (_roamTarget != null) {
          final Vector2 dir = _roamTarget! - position;
          if (dir.length < 5) {
            _pickNewTarget();
          } else {
            velocity = dir.safeNormalized() * (_speed * 0.7);
            position.add(velocity * dt);
          }
        }
      }
    } else {
      // Normal movement logic
      if (_knockbackVelocity.length > 5) {
        velocity = _knockbackVelocity;
        position.add(velocity * dt);
        _knockbackVelocity.scale(0.9);
      } else {
        _knockbackVelocity.setZero();
        
        // Elite enemies always chase player directly (no roaming)
        if (isElite) {
          Vector2 dirToPlayer = (game.player.position - position).safeNormalized();
          double currentSpeed = _speed * 1.2; // 20% faster than normal
          velocity = dirToPlayer * currentSpeed;
          position.add(velocity * dt);
        } else {
          // Normal enemies use roaming
          _roamTimer -= dt;
          if (_roamTimer <= 0 || _roamTarget == null) _pickNewTarget();

          if (_roamTarget != null) {
            final Vector2 dir = _roamTarget! - position;
            if (dir.length < 5) {
              _pickNewTarget();
            } else {
              double currentSpeed = _speed;
              if (modifier == EnemyModifier.swift) currentSpeed *= 1.5;
              if (modifier == EnemyModifier.shieldBearer) currentSpeed *= 0.7; // Slower
              velocity = dir.safeNormalized() * currentSpeed;
              position.add(velocity * dt);
            }
          }
        }
      }
    }

    // Attack Logic (Melee) - Skip for Kamikaze (they explode instead)
    // Elite enemies have larger attack range
    double attackRange = isElite ? size.x + 30 : size.x + 10;
    if (modifier != EnemyModifier.kamikaze && distToPlayer < attackRange) {
       _animator.isAttacking = true;
       _animator.play("Kicking"); // Use kicking animation
    } else {
       _animator.isAttacking = false;
       // Play animations based on movement
       if (velocity.length > 10) {
       _animator.play("running"); // Mapped to "Standard Run" intent but file uses "running"
       } else {
          _animator.play("idle");
       }
    }

    // Update Animator with velocity
    _animator.update(dt, velocity, false);
  }

  // ... keep _pickNewTarget and takeDamage ...
  void _pickNewTarget() {
     final Random rng = _rng;
     Vector2 playerPos = game.player.position;
     double dx = (rng.nextDouble() - 0.5) * 200;
     double dy = (rng.nextDouble() - 0.5) * 200;
     _roamTarget = playerPos + Vector2(dx, dy);
     _roamTimer = 1.0 + rng.nextDouble() * 2.0;
  }

  /// [invulnerability] is how long this enemy ignores further hits. Continuous
  /// sources (dash, slash) need the full window so they land once per swing;
  /// one-shot sources (projectiles, punches) pass a short one, otherwise a
  /// blanket 0.5s cap silently threw away most of the blaster's fire rate.
  void takeDamage(int amount,
      {Vector2? knockbackDir, double invulnerability = 0.5}) {
    if (health <= 0 || _invulnerableTimer > 0) return;
    
    // Shield Bearer: Block damage from the front. See isBlockedByShield --
    // the old test had the sign inverted and only ever blocked hits from
    // behind.
    if (modifier == EnemyModifier.shieldBearer && knockbackDir != null) {
      final Vector2 toPlayer = game.player.position - position;
      if (toPlayer.length > 1 && isBlockedByShield(toPlayer, knockbackDir)) {
        // Blocked! Play block effect
        game.world.add(DamageText(0, position.clone() + Vector2(0, -30)));
        SoundService.instance.playDamage(); // Reuse sound for block
        return; // No damage taken
      }
    }
    
    game.world.add(DamageText(amount, position.clone() + Vector2(0, -30)));
    health -= amount;
    // Elite enemies take less knockback and are harder to push away
    if (knockbackDir != null) {
      double knockbackForce = isElite ? 200.0 : 400.0; // Elite takes 50% less knockback
      _knockbackVelocity = knockbackDir.safeNormalized() * knockbackForce;
    }
    _invulnerableTimer = invulnerability;
    if (health <= 0) {
      health = 0;
      removeFromParent();
      game.killCount++;
      // ... drops ...
      game.world.add(XpGem(isElite ? 50 : 10)..position = position);
      
      // Spawn power-up with 3% chance
      final Random rng = _rng;
      if (rng.nextDouble() < 0.03) {
        final powerUpType = PowerUpType.values[rng.nextInt(PowerUpType.values.length)];
        game.world.add(PowerUp(powerUpType)..position = position + Vector2((rng.nextDouble() - 0.5) * 20, (rng.nextDouble() - 0.5) * 20));
      }
      
      SoundService.instance.playExplosion(isLarge: isElite);
      game.world.add(VisualEffects.createExplosion(position));
    }
  }

  @override
  void render(Canvas canvas) {
    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: (size / 2).toOffset() + const Offset(0, 15), width: width, height: width * 0.3),
      _shadowPaint,
    );

    // Kamikaze: Pulsing red glow
    if (modifier == EnemyModifier.kamikaze) {
      final double pulse = (sin(_pulseTimer * 10) + 1) / 2; // Pulse based on time
      final double scale = 1.0 + (pulse * 0.2); // Scale up slightly
      final double opacity = 0.3 + (pulse * 0.4);
      
      canvas.save();
      canvas.translate(size.x / 2, size.y / 2);
      canvas.scale(scale);
      canvas.drawCircle(
        Offset.zero,
        size.x / 2,
        Paint()..color = Colors.red.withValues(alpha: opacity)
      );
      canvas.restore();
    }

    // Render Procedural Enemy
    _animator.render(canvas, Vector2(size.x / 2, size.y / 2 + 5), size.y);

    // Shield Bearer: Draw shield in front
    if (modifier == EnemyModifier.shieldBearer) {
      // Calculate facing direction
      Vector2 toPlayer = game.player.position - position;
      if (toPlayer.length > 1) {
        Vector2 facingDir = toPlayer.safeNormalized();
        double angle = atan2(facingDir.y, facingDir.x);
        
        canvas.save();
        canvas.translate(size.x / 2, size.y / 2);
        canvas.rotate(angle);
        
        // Draw shield arc
        final shieldPaint = Paint()
          ..color = Colors.blue.withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4;
        canvas.drawArc(
          const Rect.fromLTWH(-15, -20, 30, 40),
          -pi / 3,
          2 * pi / 3,
          false,
          shieldPaint
        );
        
        // Shield fill
        final shieldFill = Paint()
          ..color = Colors.blue.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill;
        canvas.drawArc(
          const Rect.fromLTWH(-15, -20, 30, 40),
          -pi / 3,
          2 * pi / 3,
          false,
          shieldFill
        );
        
        canvas.restore();
      }
    }

    // Flash
    if (_invulnerableTimer > 0) {
       canvas.drawCircle((size/2).toOffset(), size.x/2, _flashPaint);
    }
  }
}

class DamageText extends PositionComponent {
  final int damage;
  double _lifeTime = 0.0;
  final bool isCrit;

  /// Laid out once: the text never changes, but this used to be rebuilt and
  /// re-laid-out on every frame for every floating number on screen.
  final TextPainter _painter;

  DamageText(this.damage, Vector2 pos, {this.isCrit = false})
      : _painter = TextPainter(
          text: TextSpan(
            text: damage.toString(),
            style: TextStyle(
              color: isCrit ? Colors.yellow : Colors.white,
              fontSize: isCrit ? 26 : 18,
              fontWeight: FontWeight.bold,
              shadows: const [
                Shadow(blurRadius: 2, color: Colors.black, offset: Offset(1, 1))
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout() {
    position = pos;
    anchor = Anchor.center;
    priority = 200;
  }

  @override
  void render(Canvas canvas) {
    _painter.paint(
        canvas, Offset(-_painter.width / 2, -_painter.height / 2));
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.y -= 50 * dt;
    _lifeTime += dt;
    if (_lifeTime > 0.8) removeFromParent();
  }
}

class XpGem extends PositionComponent {
  final int amount;
  double _lifeTime = 0.0;
  bool isMagnetized = false;

  static final Paint _bodyPaint = Paint()..color = const Color(0xFF00FF00);
  static final Paint _corePaint = Paint()..color = Colors.white;

  XpGem(this.amount) : super(size: Vector2.all(10), anchor: Anchor.center);

  @override
  void render(Canvas canvas) {
    // Bob at render time. Adding to position each frame permanently drifted the
    // gem and made the amplitude depend on the frame rate.
    final Offset centre =
        (size / 2).toOffset() + Offset(0, sin(_lifeTime * 5) * 3);
    canvas.drawCircle(centre, 4, _bodyPaint);
    canvas.drawCircle(centre, 2, _corePaint);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _lifeTime += dt;
  }
}

class PowerUp extends PositionComponent with HasGameReference<RpgGame> {
  final PowerUpType type;
  double _lifeTime = 0.0;
  double _hoverTime = 0.0;

  PowerUp(this.type) : super(size: Vector2.all(30), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    _lifeTime += dt;
    _hoverTime += dt;

    // Collection check
    if (game.player.position.distanceTo(position) < 30) {
      _applyEffect();
      removeFromParent();
    }
    
    // Despawn after 10 seconds
    if (_lifeTime > 10.0) {
      removeFromParent();
    }
  }

  void _applyEffect() {
    switch (type) {
      case PowerUpType.health:
        // Heal 20% of max HP
        final healAmount = (game.player.maxHealth * 0.2).toInt();
        game.player.health = (game.player.health + healAmount).clamp(0, game.player.maxHealth);
        game.world.add(DamageText(healAmount, position, isCrit: true));
        break;
        
      case PowerUpType.frenzy:
        // Activate frenzy for 5 seconds
        game.player._frenzyTimer = 5.0;
        game.hud.showStory("FRENZY MODE!");
        break;
        
      case PowerUpType.magnet:
        // Magnetize all XpGems
        for (final gem in game.world.children.whereType<XpGem>()) {
          gem.isMagnetized = true;
        }
        break;
        
      case PowerUpType.nuke:
        // Damage all non-elite enemies
        int killed = 0;
        for (final child in game.world.children) {
          if (child is Enemy && !child.isElite) {
            child.takeDamage(9999);
            killed++;
          }
        }
        game.cameraShake(5.0);
        // Flash effect
        game.world.add(VisualEffects.createExplosion(game.player.position, scale: 5.0));
        if (killed > 0) {
          game.hud.showStory("NUKE! $killed KILLED");
        }
        break;
    }
  }

  @override
  void render(Canvas canvas) {
    final Paint paint = Paint();
    final Offset center = (size / 2).toOffset();

    // Hover at render time rather than mutating position (see XpGem).
    canvas.save();
    canvas.translate(0, sin(_hoverTime * 3) * 4);
    
    switch (type) {
      case PowerUpType.health:
        paint.color = Colors.red;
        canvas.drawCircle(center, 12, paint);
        canvas.drawCircle(center, 8, Paint()..color = Colors.white);
        // Draw cross
        final crossPaint = Paint()..color = Colors.red..strokeWidth = 3;
        canvas.drawLine(center + const Offset(-6, 0), center + const Offset(6, 0), crossPaint);
        canvas.drawLine(center + const Offset(0, -6), center + const Offset(0, 6), crossPaint);
        break;
        
      case PowerUpType.frenzy:
        paint.color = Colors.orange;
        canvas.drawCircle(center, 12, paint);
        paint.color = Colors.yellow;
        canvas.drawCircle(center, 8, paint);
        // Draw lightning bolt
        final boltPaint = Paint()..color = Colors.white..strokeWidth = 2;
        canvas.drawLine(center + const Offset(-4, -6), center + const Offset(2, 0), boltPaint);
        canvas.drawLine(center + const Offset(2, 0), center + const Offset(-2, 6), boltPaint);
        break;
        
      case PowerUpType.magnet:
        paint.color = Colors.blue;
        canvas.drawCircle(center, 12, paint);
        // Draw magnet U-shape
        final magnetPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3;
        canvas.drawArc(Rect.fromLTWH(center.dx - 8, center.dy - 4, 16, 16), 0, -pi, false, magnetPaint);
        break;
        
      case PowerUpType.nuke:
        paint.color = Colors.purple;
        canvas.drawCircle(center, 12, paint);
        paint.color = Colors.yellow;
        canvas.drawCircle(center, 8, paint);
        // Draw explosion symbol
        final expPaint = Paint()..color = Colors.red..strokeWidth = 2;
        for (int i = 0; i < 8; i++) {
          final angle = (i * pi / 4);
          final start = center + Offset(cos(angle) * 4, sin(angle) * 4);
          final end = center + Offset(cos(angle) * 10, sin(angle) * 10);
          canvas.drawLine(start, end, expPaint);
        }
        break;
    }
    
    // Glow effect
    final glowPaint = Paint()
      ..color = paint.color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, 15, glowPaint);

    canvas.restore();
  }
}

class EnemyProjectile extends PositionComponent with HasGameReference<RpgGame> {
  final Vector2 velocity;
  double _lifeTime = 0.0;

  EnemyProjectile(Vector2 pos, Vector2 target)
      : velocity = (target - pos).safeNormalized() * 300,
        super(position: pos, size: Vector2.all(10), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    position += velocity * dt;
    _lifeTime += dt;
    if (_lifeTime > 3.0) removeFromParent();

    if (position.distanceTo(game.player.position) < game.player.size.x / 2) {
      game.player.takeDamage(10, fromEnemyMelee: false); // Projectile damage, not melee
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawCircle(Offset.zero, 4, Paint()..color = Colors.purpleAccent);
  }
}

class ArrowProjectile extends EnemyProjectile {
  // Procedural Arrow instead of SVG
  ArrowProjectile(super.pos, super.target);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size = Vector2(40, 10);
    angle = atan2(velocity.y, velocity.x);
  }

  @override
  void render(Canvas canvas) {
    // Draw Arrow
    final Paint p = Paint()..color = Colors.white ..strokeWidth = 2;
    // Local coords 0,0 is center of component? No, PositionComponent render is at local 0,0 (top left).
    // But we want to draw centered on position?
    // Wait, EnemyProjectile sets anchor to Center.
    // So 0,0 in local space is the top-left of the box (-width/2, -height/2 relative to center).
    // Let's draw relative to size.

    // Center is size/2
    Offset center = (size / 2).toOffset();
    // Arrow pointing right (0 radians)
    canvas.drawLine(Offset(0, center.dy), Offset(size.x, center.dy), p);
    // Head
    canvas.drawLine(Offset(size.x - 10, center.dy - 5), Offset(size.x, center.dy), p);
    canvas.drawLine(Offset(size.x - 10, center.dy + 5), Offset(size.x, center.dy), p);
  }
}

class ShooterEnemy extends Enemy {
  double _shootTimer = 0.0;
  bool _isShooting = false;
  double _shootingAnimationTimer = 0.0;
  bool _hasFired = false;
  String? _lastActiveClipName; // Track previous animation to detect completion

  ShooterEnemy() : super();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // Override color/scale for Shooter and set weapon to Bow
    // We need to re-initialize or modify properties. Since _animator is late, super.onLoad initialized it.
    // We can just create a new one with correct color/weapon and DATA.
    _animator = StickmanAnimator(
      color: Colors.purpleAccent,
      scale: 1.0,
      weaponType: WeaponType.none, // Remove bow image for Shooter per request (animation handles visual)
      data: game.animationData
    );
    _animator.play("idle");
  }

  @override
  void update(double dt) {
    // Custom movement logic first
    if (_invulnerableTimer > 0) {
      _invulnerableTimer -= dt;
    }

    Vector2 velocity = Vector2.zero();

    if (_isShooting) {
       _shootingAnimationTimer += dt;
       
       // Track the current animation
       String? currentClipName = _animator.controller.activeClip?.name;
       
       // Check if "Shooting Arrow" animation has completed
       bool animationFinished = false;
       
       // If we just started shooting and haven't tracked it yet
       if (_lastActiveClipName == null || _lastActiveClipName != "Shooting Arrow") {
         _lastActiveClipName = currentClipName;
       }
       
       // If animation changed from "Shooting Arrow" to something else, it finished
       if (_lastActiveClipName == "Shooting Arrow" && currentClipName != "Shooting Arrow") {
         animationFinished = true;
       }
       // If animation stopped playing (reached end)
       else if (!_animator.isPlaying && _lastActiveClipName == "Shooting Arrow") {
         animationFinished = true;
       }
       // Timeout fallback (animation is sped up 5x, so should complete in ~0.2s)
       else if (_shootingAnimationTimer > 0.4) {
         animationFinished = true;
       }
       
       // Fire arrow when animation completes
       if (animationFinished && !_hasFired) {
         game.world.add(ArrowProjectile(position, game.player.position));
         _hasFired = true;
       }
       
       if (animationFinished) {
         _isShooting = false;
         _shootingAnimationTimer = 0.0;
         _hasFired = false; // Reset for next shot
         _lastActiveClipName = null; // Reset tracking
       }
    } else {
      if (_knockbackVelocity.length > 5) {
        velocity = _knockbackVelocity;
        position.add(velocity * dt);
        _knockbackVelocity.scale(0.9);
      } else {
        _knockbackVelocity.setZero();

        // Custom movement: maintain distance
        double dist = position.distanceTo(game.player.position);
        Vector2 dir = (game.player.position - position).safeNormalized();

        if (dist < 300) {
           velocity = -dir * 80; // Retreat
        } else if (dist > 500) {
           velocity = dir * 100; // Chase
        }

        position.add(velocity * dt);
      }

      // Shoot Logic
      _shootTimer += dt;
      if (_shootTimer > 2.0) {
         _shootTimer = 0.0;
         _isShooting = true;
         _shootingAnimationTimer = 0.0;
         _hasFired = false;

         // Trigger attack anim
         // Correct name from file is "Shooting Arrow"
         _animator.play("Shooting Arrow");
      }
    }

    if (!_isShooting) {
        if (velocity.length > 10) {
           // Use walking animation for shooter enemy
           // The play() method will only play if the clip exists, so safe to try
           _animator.play("walking");
           // If walking doesn't exist, fallback to running (handled by checking active clip)
           if (_animator.controller.activeClip?.name != "walking") {
             _animator.play("running");
           }
        } else {
           _animator.play("idle");
        }
    }

    // Update Animator
    // If shooting, force facing towards player
    if (_isShooting) {
       Vector2 faceDir = (game.player.position - position).safeNormalized();
       // Pass a fake velocity so animator rotates to face player
       _animator.update(dt, faceDir * 100, false);
    } else {
       _animator.update(dt, velocity, false);
    }
  }
}

enum EnemyModifier { none, swift, ghostly, regen, kamikaze, shieldBearer, summoner }

enum PowerUpType { health, frenzy, magnet, nuke }

// --- MISSING CLASSES RESTORED ---

class OrbitalShield extends PositionComponent {
  final Player player;

  /// Purchased shield level. Drives orbit speed and damage, so levels past the
  /// first are no longer inert purchases.
  final int level;

  double _angle;
  static const double _orbitRadius = 80.0;

  double get _speed => 2.0 + 0.2 * (level - 1);
  int get _damage => 100 * level;

  OrbitalShield(this.player, {this.level = 1, double orbitOffset = 0.0})
      : _angle = orbitOffset,
        super(size: Vector2.all(20), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    if (player.isRemoved) {
      removeFromParent();
      return;
    }

    _angle += _speed * dt;
    position = player.position + Vector2(cos(_angle), sin(_angle)) * _orbitRadius;

    // Collision with enemies
    final game = findGame()! as RpgGame;
    for (final child in game.world.children) {
      if (child is Enemy) {
        if (child.position.distanceTo(position) < (child.size.x / 2 + size.x / 2)) {
           child.takeDamage(_damage,
               knockbackDir: child.position - player.position);
        }
      }
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawCircle(Offset(size.x/2, size.y/2), 8, Paint()..color = Colors.cyanAccent..style = PaintingStyle.stroke..strokeWidth = 2);
    canvas.drawCircle(Offset(size.x/2, size.y/2), 4, Paint()..color = Colors.white);
  }
}

class Barrel extends PositionComponent with HasGameReference<RpgGame> {
  double radius = 25;
  int health = 3;

  static final Paint _bodyPaint = Paint()..color = Colors.brown.shade700;
  static final Paint _bandPaint = Paint()
    ..color = Colors.black
    ..strokeWidth = 2;

  Barrel() : super(anchor: Anchor.center, size: Vector2.all(50));

  void takeDamage() {
    health--;
    if (health <= 0) {
      explode();
    }
  }

  void explode() {
    if (isRemoved) return;
    removeFromParent();
    game.world.add(VisualEffects.createExplosion(position, scale: 2.0));
    SoundService.instance.playExplosion(); // Re-using existing sound

    // Area Damage
    for (final child in game.world.children) {
      if (child is Enemy) {
        if (child.position.distanceTo(position) < 150) {
          child.takeDamage(50, knockbackDir: child.position - position);
        }
      }
    }
  }

  @override
  void render(Canvas canvas) {
    // Draw Barrel
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), _bodyPaint);
    canvas.drawLine(const Offset(0, 10), Offset(width, 10), _bandPaint);
    canvas.drawLine(Offset(0, height - 10), Offset(width, height - 10), _bandPaint);
  }
}

class SpikeTrap extends PositionComponent with HasGameReference<RpgGame> {
  static final Paint _basePaint = Paint()..color = Colors.grey.shade800;
  static final Paint _spikePaint = Paint()..color = Colors.grey.shade400;

  SpikeTrap() : super(anchor: Anchor.center, size: Vector2.all(40));

  @override
  void update(double dt) {
    super.update(dt);
    // Player collision
    if (game.player.position.distanceTo(position) < 30) {
       game.player.takeDamage(5, fromEnemyMelee: false); // Trap damage, not melee
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), _basePaint);
    // Spikes
    canvas.drawCircle(const Offset(10, 10), 5, _spikePaint);
    canvas.drawCircle(const Offset(30, 10), 5, _spikePaint);
    canvas.drawCircle(const Offset(10, 30), 5, _spikePaint);
    canvas.drawCircle(const Offset(30, 30), 5, _spikePaint);
  }
}

class HurricaneKickEffect extends PositionComponent {
  double _lifeTime = 0.0;
  static const double _duration = 0.5; // Increased duration
  final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.0
    ..strokeCap = StrokeCap.round;

  HurricaneKickEffect() : super(anchor: Anchor.center, size: Vector2.all(180)); // Matches 60-unit damage radius

  @override
  void update(double dt) {
    super.update(dt);
    _lifeTime += dt;
    if (_lifeTime >= _duration) {
      if (parent is Player) {
        (parent as Player).isSlashing = false;
      }
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    // Draw a spinning "hurricane" spiral
    double progress = _lifeTime / _duration;
    double opacity = (1.0 - progress).clamp(0.0, 1.0);
    _paint.color = Colors.cyanAccent.withValues(alpha: opacity);

    canvas.save();
    // Center logic: Move to center of component
    canvas.translate(size.x / 2, size.y / 2);
    canvas.rotate(progress * pi * 4); // Fast spin

    // Draw spiral lines for magic circle - scaled to match damage radius
    for(int i=0; i<3; i++) {
       canvas.drawArc(
         Rect.fromCircle(center: Offset.zero, radius: 45 + (i * 12) + (progress * 30)),
         (i * 1.5),
         2.0,
         false,
         _paint
       );
    }

    canvas.restore();
  }
}

class DashImpactEffect extends PositionComponent {
  double _lifeTime = 0.0;
  static const double _duration = 0.25; // Quick dash impact
  final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round;

  DashImpactEffect() : super(anchor: Anchor.center, size: Vector2.all(40)); // Dash radius + 10

  @override
  void update(double dt) {
    super.update(dt);
    _lifeTime += dt;
    if (_lifeTime >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    double progress = _lifeTime / _duration;
    double opacity = (1.0 - progress).clamp(0.0, 1.0);
    _paint.color = Colors.yellowAccent.withValues(alpha: opacity);

    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);

    // Draw expanding rings for dash impact
    for (int i = 0; i < 2; i++) {
      double radius = 10 + (i * 8) + (progress * 15);
      canvas.drawCircle(Offset.zero, radius, _paint);
    }

    canvas.restore();
  }
}

class PunchImpactEffect extends PositionComponent {
  double _lifeTime = 0.0;
  static const double _duration = 0.3; // Punch impact duration
  final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round;

  PunchImpactEffect() : super(anchor: Anchor.center, size: Vector2.all(160)); // Punch radius + 40

  @override
  void update(double dt) {
    super.update(dt);
    _lifeTime += dt;
    if (_lifeTime >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    double progress = _lifeTime / _duration;
    double opacity = (1.0 - progress).clamp(0.0, 1.0);
    _paint.color = Colors.orangeAccent.withValues(alpha: opacity);

    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);

    // Draw expanding circles for punch impact
    for (int i = 0; i < 2; i++) {
      double radius = 25 + (i * 15) + (progress * 30);
      canvas.drawCircle(Offset.zero, radius, _paint);
    }

    canvas.restore();
  }
}

class DashCooldownBar extends PositionComponent with HasVisibility {
  final Player player;
  final Paint _barPaint = Paint()..style = PaintingStyle.fill;
  final Paint _bgPaint = Paint()..color = Colors.black.withValues(alpha: 0.5)..style = PaintingStyle.fill;
  final Paint _borderPaint = Paint()..color = Colors.white.withValues(alpha: 0.5)..style = PaintingStyle.stroke..strokeWidth = 1;

  DashCooldownBar(this.player) : super(size: Vector2(40, 6), anchor: Anchor.center) {
    isVisible = false; // Start hidden
  }

  @override
  void update(double dt) {
    super.update(dt);
    // Only show when cooldown is active (charging)
    isVisible = player.currentDashCooldown > 0;
  }

  @override
  void render(Canvas canvas) {
     if (!isVisible) return;
     
     // Background
     canvas.drawRect(size.toRect(), _bgPaint);
     canvas.drawRect(size.toRect(), _borderPaint);

     double progress = 0.0;
     if (player.dashCooldownMax > 0) {
        progress = (1.0 - (player.currentDashCooldown / player.dashCooldownMax)).clamp(0.0, 1.0);
     }

     if (progress < 1.0) {
        _barPaint.color = Colors.yellow; // Charging
     } else {
        _barPaint.color = Colors.cyanAccent; // Ready
     }

     if (progress > 0) {
        canvas.drawRect(Rect.fromLTWH(0, 0, size.x * progress, size.y), _barPaint);
     }
  }
}
