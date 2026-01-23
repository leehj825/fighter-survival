import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame/input.dart'; // Added to fix TapDetector not found
import 'package:flutter/material.dart' hide Draggable;
import 'package:flame/effects.dart';

import 'grid_background.dart';
import 'hud.dart';
import 'managers.dart';
import 'visual_effects.dart';
import 'sound_service.dart';
import 'stickman_animator.dart'; // Import the new file

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
  final double knobRadius = 20;
  final double baseRadius = 50;

  Vector2 _knobPos = Vector2.zero();

  final Paint _basePaint = Paint()..color = Colors.white.withOpacity(0.2)..style = PaintingStyle.fill;
  final Paint _baseStroke = Paint()..color = Colors.white.withOpacity(0.4)..style = PaintingStyle.stroke..strokeWidth = 2;
  final Paint _knobPaint = Paint()..color = Colors.cyanAccent.withOpacity(0.8);

  VirtualJoystick() : super(anchor: Anchor.center, size: Vector2.all(100)) {
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

class ActionButton extends PositionComponent {
  final String label;
  final Color color;
  final Paint _bgPaint;
  final Paint _strokePaint;
  late TextPainter _textPainter;

  ActionButton({required this.label, required this.color})
      : _bgPaint = Paint()..color = color.withOpacity(0.5),
        _strokePaint = Paint()
          ..color = Colors.white.withOpacity(0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
        super(anchor: Anchor.center, size: Vector2.all(80));

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
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), size.x / 2, _bgPaint);
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), size.x / 2, _strokePaint);

    // Draw Whirlwind Icon instead of Text
    if (label == "SLASH") {
       final Paint iconPaint = Paint()
         ..color = Colors.white.withOpacity(0.9)
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
  
  // Shoot direction from right joystick
  Vector2? _shootDirection;
  double _lastShootTime = 0.0;
  static const double _autoShootInterval = 0.2; // Auto-shoot interval when joystick is held

  // Tweakable Variable for Dash Sensitivity
  static const double dashVelocityThreshold = 1000.0; // Lowered from 2500.0

  // Camera Shake State
  double _shakeTimer = 0.0;
  double _shakeIntensity = 0.0;

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

    // Initialize Player with Stats from GameData
    player = Player()..anchor = Anchor.center;

    // Load Resume State
    if (resumeGame && GameData().hasSavedRun) {
      final data = GameData();
      wave = data.savedWave;
      player.level = data.savedLevel;
      player.xp = data.savedXp;
      player.damageMult = data.savedDamageMult;
      player.xpToNextLevel = (10 * pow(1.5, player.level - 1)).toInt(); // Recalculate xpToNext
      // We set health in onLoad of Player usually, let's override it after add or pass it.
      // Since Player.onLoad runs when added, we should set these stats *after* adding?
      // Or modify Player to accept them.
      // Player is a PositionComponent.
    }

    world.add(player);

    // Add Orbital Shield (If Unlocked/Leveled)
    if (GameData().levelShield > 0) {
      world.add(OrbitalShield(player));
    }

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
    rightJoystick.position = Vector2(size.x - 150, size.y - 150); // Right side, fixed position
    rightJoystick.isVisible = GameData().unlockBlaster; // Only visible when blaster is unlocked
    hud.add(rightJoystick);

    // Add Action Buttons
    slashButton = ActionButton(label: "SLASH", color: Colors.redAccent)
      ..priority = 200
      ..position = Vector2(size.x - 100, size.y - 80);
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
      slashButton.position = Vector2(size.x - 100, size.y - 80);
      if (rightJoystick.isLoaded) {
        rightJoystick.position = Vector2(size.x - 150, size.y - 150);
        rightJoystick.isVisible = GameData().unlockBlaster;
      }
    }
  }

  void _spawnObstacles() {
    final Random rng = Random();
    // Spawn 20 random obstacles near start
    for (int i = 0; i < 20; i++) {
      bool isBig = rng.nextBool();
      Vector2 pos = Vector2(
        (rng.nextDouble() - 0.5) * 2000,
        (rng.nextDouble() - 0.5) * 2000,
      );
      // Don't spawn on top of player
      if (pos.length > 200) {
        world.add(Obstacle(radius: isBig ? 40 : 20, height: isBig ? 60 : 30)..position = pos);
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

    final Random rng = Random();
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
      final Random rng = Random();
      final double offX = (rng.nextDouble() - 0.5) * 0.025 * _shakeIntensity;
      final double offY = (rng.nextDouble() - 0.5) * 0.025 * _shakeIntensity;
      cameraComponent.viewfinder.anchor = Anchor(0.5 + offX, 0.5 + offY);
    } else {
      cameraComponent.viewfinder.anchor = Anchor.center;
    }

    super.update(dt);
    if (gameOver) return;

    // Check if ALL enemies are dead (Base Enemy + ShooterEnemy)
    bool enemiesAlive = world.children.whereType<Enemy>().isNotEmpty;

    if (!enemiesAlive) {
      _waveTimer += dt;
      if (_waveTimer > 3.0) {
        wave++;
        _spawnWave();
        _waveTimer = 0.0;
      }
    }

    // --- Y-SORTING ---
    // Sort components by Y position for depth (2.5D view)
    for (final child in world.children) {
      if (child is PositionComponent) {
        child.priority = child.position.y.toInt();
      }
    }

    // NEW: XP Collection Loop
    for (final gem in world.children.whereType<XpGem>()) {
      bool collected = false;
      if (gem.isMagnetized) {
          // Fast magnetic pull
          gem.position.add((player.position - gem.position).safeNormalized() * 800 * dt);
          if (player.position.distanceTo(gem.position) < 20) {
             collected = true;
          }
      } else {
        if (player.position.distanceTo(gem.position) < 100) {
          // Normal magnetic pull
          gem.position.add((player.position - gem.position).safeNormalized() * 300 * dt);
          if (player.position.distanceTo(gem.position) < 10) {
             collected = true;
          }
        }
      }

      if (collected) {
          runGems += gem.amount;
          player.gainXp(gem.amount);
          gem.removeFromParent();
      }
    }

    // Magnet Item Collection Loop
    for (final magnet in world.children.whereType<MagnetItem>()) {
        if (player.position.distanceTo(magnet.position) < (player.size.x / 2 + magnet.size.x / 2)) {
            // Activate Magnet
            for (final gem in world.children.whereType<XpGem>()) {
                gem.isMagnetized = true;
            }
            magnet.removeFromParent();
        }
    }

    // --- COLLISION LOGIC ---
    for (final child in world.children) {
      // 1. Obstacle Collision
      if (child is Obstacle) {
        // Player vs Obstacle
        double distP = player.position.distanceTo(child.position);
        double radiusP = (player.size.x / 2) + child.radius;
        if (distP < radiusP) {
          Vector2 dir = player.position - child.position;

          if (!dir.x.isNaN && !dir.y.isNaN) {
             // Prevent getting stuck if center positions overlap exactly
             if (dir.length2 < 0.001) dir = Vector2(1, 0);

             Vector2 push = dir.safeNormalized() * (radiusP - distP);
             if (!push.x.isNaN && !push.y.isNaN) {
                player.position += push;
             }
          }
        }

        // Enemy vs Obstacle
        for (final other in world.children) {
          if (other is Enemy && other.modifier != EnemyModifier.ghostly) { // Ghostly enemies can pass through obstacles
             double distE = other.position.distanceTo(child.position);
             double radiusE = (other.size.x / 2) + child.radius;
             if (distE < radiusE) {
               Vector2 dir = other.position - child.position;

               if (!dir.x.isNaN && !dir.y.isNaN) {
                  if (dir.length2 < 0.001) dir = Vector2(1, 0);

                  Vector2 push = dir.safeNormalized() * (radiusE - distE);
                  if (!push.x.isNaN && !push.y.isNaN) {
                     other.position += push;
                  }
               }
             }
          }
        }
      }

      // Barrel Collision
      if (child is Barrel) {
          // Player Body vs Barrel
          double distP = player.position.distanceTo(child.position);
          double radiusP = (player.size.x / 2) + child.radius;
          if (distP < radiusP) {
             child.takeDamage(); // Explode on contact
          }
      }

      // 2. Combat
      if (child is Enemy) {
        final Enemy enemy = child;
        final double dist = player.position.distanceTo(enemy.position);
        final double combinedRadius = (player.size.x / 2) + (enemy.size.x / 2);

        // Check DASH Hit
        if (player.isDashing && dist < (combinedRadius + 10)) {
           enemy.takeDamage((20 * player.damageMult).toInt());
        }

        // Check SLASH Hit
        if (player.isSlashing && dist < (combinedRadius + 60)) {
           enemy.takeDamage((10 * player.damageMult).toInt(), knockbackDir: enemy.position - player.position);
        }

        // Check PLAYER DAMAGE Hit
        if (!player.isDashing && dist < combinedRadius) {
          player.takeDamage(10);
        }
      }
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
    if (slashButton.containsPoint(startPos - hud.position)) {
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

      // Tap to attack (damage enemies with alternating Hook/Hook Punch)
      // Only if blaster is NOT unlocked (when unlocked, use joystick for shooting)
      if (!GameData().unlockBlaster) {
        player.tapAttack();
      }
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
        _shootDirection = offset.safeNormalized();
        // Shoot when joystick is first moved, then auto-shoot at intervals
        final double currentTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
        if (currentTime - _lastShootTime >= _autoShootInterval) {
          player.shoot(_shootDirection!);
          _lastShootTime = currentTime;
        }
      } else {
        _shootDirection = null;
      }
    }

    // Handle Dash Swipe
    if (pointerId == _actionPointerId && _lastActionPos != null) {
      final DateTime now = DateTime.now();
      if (_lastActionTime != null) {
        final double dtSeconds = now.difference(_lastActionTime!).inMicroseconds / 1000000.0;
        if (dtSeconds > 0) {
          final double dist = currentPos.distanceTo(_lastActionPos!);
          final double velocity = dist / dtSeconds;

          if (velocity > dashVelocityThreshold && dist > 10) {
             Vector2 dashDir = currentPos - _lastActionPos!;
             if (!dashDir.isNaN) {
                player.dash(dashDir);
             }
          }
        }
      }
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
      _lastShootTime = 0.0;
      rightJoystick.reset();
    }

    if (pointerId == _actionPointerId) {
      _actionPointerId = null;
      _lastActionPos = null;
    }
  }

  void _resetGame() {
       gameOver = false;
       killCount = 0;
       wave = 1;
       runGems = 0;

       player.health = player.maxHealth;
       player.level = 1;
       player.xp = 0;
       player.xpToNextLevel = 10;
       player.damageMult = 1.0;

       player.position = Vector2.zero();
       world.children.whereType<Enemy>().forEach((e) => e.removeFromParent());
       world.children.whereType<ParticleSystemComponent>().forEach((e) => e.removeFromParent());
       world.children.whereType<XpGem>().forEach((e) => e.removeFromParent());
       world.children.whereType<EnemyProjectile>().forEach((e) => e.removeFromParent());
       world.children.whereType<Barrel>().forEach((e) => e.removeFromParent());
       world.children.whereType<MagnetItem>().forEach((e) => e.removeFromParent());
       world.children.whereType<Obstacle>().forEach((e) => e.removeFromParent());
       world.children.whereType<SpikeTrap>().forEach((e) => e.removeFromParent());
       world.children.whereType<OrbitalShield>().forEach((e) => e.removeFromParent());

       hud.storyText.text = "";
       _spawnWave();
       _spawnObstacles(); // Respawn obstacles and barrels

       // Respawn Shield with current stats
       if (GameData().levelShield > 0) {
         world.add(OrbitalShield(player));
       }

       overlays.remove('GameOver');
  }

  void onGameOver() {
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
  final double height;
  final Paint _paint = Paint()..color = Colors.grey;

  Obstacle({required this.radius, required this.height}) : super(anchor: Anchor.center, size: Vector2.all(radius * 2));

  @override
  void render(Canvas canvas) {
    // 2.5D Cylinder Render
    final Offset center = (size / 2).toOffset();
    final double r = radius;
    final double h = height;

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: center, width: width, height: width * 0.6),
      Paint()..color = Colors.black.withOpacity(0.3)
    );

    // Body
    final Offset topCenter = center + Offset(0, -h);
    final Path bodyPath = Path();
    bodyPath.moveTo(center.dx - r, center.dy);
    bodyPath.lineTo(center.dx + r, center.dy);
    bodyPath.lineTo(topCenter.dx + r, topCenter.dy);
    bodyPath.lineTo(topCenter.dx - r, topCenter.dy);
    bodyPath.close();
    canvas.drawPath(bodyPath, Paint()..color = Colors.grey.shade700);

    // Top
    canvas.drawCircle(topCenter, r, Paint()..color = Colors.grey.shade400);
    // Rim
    canvas.drawCircle(topCenter, r, Paint()..style = PaintingStyle.stroke ..color = Colors.white.withOpacity(0.3));
  }
}

class Player extends PositionComponent with HasGameRef<RpgGame> {
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
  bool isSlashing = false;
  double _shootCooldown = 0.0;
  static const double _shootCooldownTime = 0.15; // Time between shots
  
  // Frenzy power-up state
  double _frenzyTimer = 0.0;
  bool get isFrenzyActive => _frenzyTimer > 0.0;
  double get frenzySpeedMult => isFrenzyActive ? 2.0 : 1.0; // Double animation speed

  // Animation alternation state
  bool _useRoundKick = true; // Alternate between Round Kick and Roundhouse Kick
  bool _useHook = true; // Alternate between Hook and Hook Punch
  
  // Attack state to prevent stacking
  bool _isTapAttacking = false;

  // NEW: Animator
  late StickmanAnimator _animator;

  Player() : super(size: Vector2.all(60), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    super.onLoad();
    // ... Keep existing stat initialization ...
    final data = GameData();
    maxHealth = 100 + (data.levelHp * 20);
    health = maxHealth;
    dashCooldownMax = 0.8 * pow(0.9, data.levelDash);

    // Initialize the animator with the loaded data from GameRef
    _animator = StickmanAnimator(
      color: Colors.cyanAccent,
      scale: 1.2,
      attackType: AttackType.kick,
      weaponType: WeaponType.none,
      data: gameRef.animationData // Pass the loaded data here
    );

    // Set default animation
    _animator.play("Standard Idle");

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

      if (_dashTimer % 0.05 < dt) {
         double dashAngle = 0;
         if (_dashDirection != Vector2.zero()) {
             dashAngle = atan2(_dashDirection.y, _dashDirection.x);
         }
         gameRef.world.add(VisualEffects.createDashTrail(position, dashAngle));
      }
      if (_dashTimer <= 0) {
        isDashing = false;
        // Do not reset angle, Animator handles rotation now
      }
    } else if (moveDirection != null && moveDirection != Vector2.zero()) {
      velocity = moveDirection! * _baseSpeed;
      position.add(velocity * dt);
    }

    // Update Animator
    _animator.isAttacking = isSlashing;

    // Check if tap attack animation is still actively playing
    String? currentClipName = _animator.controller.activeClip?.name;
    bool isTapAttackPlaying = _isTapAttacking && 
        (currentClipName == "Hook" || currentClipName == "Hook Punch") &&
        _animator.isPlaying;

    // Check if actually moving (both velocity and moveDirection checks)
    bool isActuallyMoving = velocity.length > 5 || 
        (moveDirection != null && moveDirection!.length > 0.1);

    // Animation Logic
    // Priority: Dash > Slash > Tap Attack (if playing) > Movement > Idle
    if (isDashing) {
      // Alternate between Round Kick and Roundhouse Kick
      _animator.play(_useRoundKick ? "Round Kick" : "Roundhouse Kick");
      _useRoundKick = !_useRoundKick;
    } else if (isSlashing) {
      _animator.play("magic");
    } else if (isTapAttackPlaying) {
      // Let tap attack animation finish - don't override with movement or idle
      // Do nothing, let the animation continue playing until it finishes
    } else if (isActuallyMoving) {
      // Play "running" only if actually moving
      if (currentClipName != "running") {
        _animator.play("running");
      }
    } else {
      // Not moving and not attacking - play idle
      // Force idle if not moving and not in any attack animation
      if (currentClipName != "Standard Idle") {
        _animator.play("Standard Idle");
      }
    }

    // Pass velocity to animator for direction calculation (3D facing)
    _animator.update(dt, velocity, isDashing);
  }

  @override
  void render(Canvas canvas) {
    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: (size / 2).toOffset() + const Offset(0, 20), width: width, height: width * 0.3),
      Paint()..color = Colors.black.withOpacity(0.3)
    );

    // Render Procedural Stickman
    // We pass (size/2) + offset so feet align with shadow
    // Pass isDashing to render for the Punch pose
    _animator.render(canvas, Vector2(size.x / 2, size.y / 2 + 10), size.y, isDashing: isDashing);
  }

  // ... Keep existing methods (dash, slash, shoot, gainXp, etc) ...
  void dash(Vector2 direction) {
    if (isDashing || _currentDashCooldown > 0) return;
    isDashing = true;
    isSlashing = false; // Reset slash if dashing
    _dashTimer = _dashDuration;
    // Frenzy halves cooldown
    _currentDashCooldown = dashCooldownMax / (isFrenzyActive ? 2.0 : 1.0);

    if (direction.length > 0) {
      _dashDirection = direction.safeNormalized();
    } else {
      _dashDirection = Vector2(1, 0);
    }
  }

  void slash() {
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
    int sfxType = damageMult > 1.5 ? 1 : 0;
    SoundService.instance.playShoot(variant: sfxType);
    gameRef.world.add(PlayerProjectile(position, dir, damageMult));
  }

  void tapAttack() {
    // Prevent stacking attacks
    if (_isTapAttacking) return;
    _isTapAttacking = true;
    
    // Play alternating Hook/Hook Punch animation with faster speed
    final String animName = _useHook ? "Hook" : "Hook Punch";
    _animator.play(animName);
    _useHook = !_useHook;
    _animator.isAttacking = true;
    
    // Speed up the animation by modifying the animator's clip speed
    // This will be handled in stickman_animator.dart
    
    // Damage nearby enemies
    for (final child in gameRef.world.children) {
      if (child is Enemy) {
        final double dist = position.distanceTo(child.position);
        final double combinedRadius = (size.x / 2) + (child.size.x / 2);
        if (dist < (combinedRadius + 40)) {
          child.takeDamage((15 * damageMult).toInt(), knockbackDir: child.position - position);
        }
      }
    }
    
    // Reset attacking state after animation completes
    // Hook/Hook Punch animations are sped up 2.5x, so they should complete faster
    // Wait for animation to actually finish playing
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!isRemoved) {
        // Only reset if animation has finished or is no longer the active clip
        String? currentClip = _animator.controller.activeClip?.name;
        if (currentClip != "Hook" && currentClip != "Hook Punch") {
          _animator.isAttacking = false;
          _isTapAttacking = false;
        } else {
          // Check again after a bit more time
          Future.delayed(const Duration(milliseconds: 200), () {
            if (!isRemoved) {
              _animator.isAttacking = false;
              _isTapAttacking = false;
            }
          });
        }
      }
    });
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
    gameRef.hud.showStory("LEVEL UP!");
    SoundService.instance.playLevelUp();
    gameRef.world.add(VisualEffects.createExplosion(position));
  }

  @override
  void takeDamage(int amount) {
    if (_damageCooldown > 0 || isDashing) return;
    SoundService.instance.playDamage();
    health -= amount;
    _damageCooldown = 1.0;
    gameRef.cameraShake(2.0);
    gameRef.world.add(DamageText(amount, position, isCrit: true));
    if (health <= 0) {
      health = 0;
      gameRef.onGameOver();
    }
  }
}

class SwordEffect extends PositionComponent {
  double _lifeTime = 0.0;
  static const double _duration = 0.3;

  final Paint _whitePaint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.0;

  SwordEffect() : super(anchor: Anchor.centerLeft);

  @override
  void onLoad() {
    size = Vector2(60, 10);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _lifeTime += dt;
    angle += (4 * pi / _duration) * dt;

    if (_lifeTime >= _duration) {
      if (parent is Player) {
        (parent as Player).isSlashing = false;
        // Also reset animator attacking state if needed, but animator has internal timer 0.3s
      }
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawLine(const Offset(20, 0), Offset(width + 20, 0), _whitePaint);
  }
}

class PlayerProjectile extends PositionComponent with HasGameRef<RpgGame> {
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
    for (final child in gameRef.world.children) {
      if (child is Enemy) {
        if (child.position.distanceTo(position) < (child.size.x / 2 + 5)) {
          child.takeDamage((5 * damageMult).toInt());
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

class Enemy extends PositionComponent with HasGameRef<RpgGame> {
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

  Enemy({this.isElite = false, this.modifier = EnemyModifier.none})
      : super(size: Vector2.all(isElite ? 100 : 50), anchor: Anchor.center) {
     if(isElite) health = health * 30;
     _maxHealth = health;
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    // Choose color/scale based on type
    Color c = Colors.redAccent;
    double s = 1.0;
    WeaponType w = WeaponType.none; // Default Red Enemy uses Fist

    if (isElite) {
      c = Colors.deepPurpleAccent;
      s = 2.0;
      w = WeaponType.axe;
    } else if (modifier == EnemyModifier.swift) {
      c = Colors.yellowAccent;
    } else if (modifier == EnemyModifier.ghostly) {
      c = Colors.white.withOpacity(0.5);
    } else if (modifier == EnemyModifier.kamikaze) {
      c = Colors.red;
    } else if (modifier == EnemyModifier.shieldBearer) {
      c = Colors.blue;
    } else if (modifier == EnemyModifier.summoner) {
      c = Colors.green;
      w = WeaponType.axe; // Staff-like weapon
    }

    // Initialize Animator with shared data
    _animator = StickmanAnimator(
      color: c,
      scale: s,
      weaponType: WeaponType.none, // Remove weapon (sword) image for everyone per request
      data: gameRef.animationData
    );

    // Set default animation
    _animator.play("Standard Idle");
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
    double distToPlayer = position.distanceTo(gameRef.player.position);

    // Special behaviors for new enemy types
    if (modifier == EnemyModifier.kamikaze) {
      // Kamikaze: Move very fast directly at player
      if (distToPlayer > 5) {
        Vector2 dir = (gameRef.player.position - position).safeNormalized();
        velocity = dir * (_speed * 2.0); // Double speed
        position.add(velocity * dt);
        
        // Explode on contact
        if (distToPlayer < (size.x / 2 + gameRef.player.size.x / 2)) {
          gameRef.player.takeDamage(30);
          takeDamage(9999); // Kill self
          gameRef.world.add(VisualEffects.createExplosion(position, scale: 2.0));
          return; // Exit early since we're dead
        }
      }
    } else if (modifier == EnemyModifier.summoner) {
      // Summoner: Maintain distance, spawn enemies
      _summonTimer += dt;
      if (_summonTimer >= _summonInterval) {
        _summonTimer = 0.0;
        // Spawn a basic enemy nearby
        final Random rng = Random();
        Vector2 spawnPos = position + Vector2(
          (rng.nextDouble() - 0.5) * 100,
          (rng.nextDouble() - 0.5) * 100,
        );
        gameRef.world.add(Enemy()..position = spawnPos);
      }
      
      // Flee if too close
      if (distToPlayer < 200) {
        Vector2 fleeDir = (position - gameRef.player.position).safeNormalized();
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

    // Attack Logic (Melee) - Skip for Kamikaze (they explode instead)
    if (modifier != EnemyModifier.kamikaze && distToPlayer < size.x + 10) {
       _animator.isAttacking = true;
       _animator.play("Kicking"); // Use kicking animation
    } else {
       _animator.isAttacking = false;
       // Play animations based on movement
       if (velocity.length > 10) {
       _animator.play("running"); // Mapped to "Standard Run" intent but file uses "running"
       } else {
          _animator.play("Standard Idle");
       }
    }

    // Update Animator with velocity
    _animator.update(dt, velocity, false);
  }

  // ... keep _pickNewTarget and takeDamage ...
  void _pickNewTarget() {
     final Random rng = Random();
     Vector2 playerPos = gameRef.player.position;
     double dx = (rng.nextDouble() - 0.5) * 200;
     double dy = (rng.nextDouble() - 0.5) * 200;
     _roamTarget = playerPos + Vector2(dx, dy);
     _roamTimer = 1.0 + rng.nextDouble() * 2.0;
  }

  void takeDamage(int amount, {Vector2? knockbackDir}) {
    if (health <= 0 || _invulnerableTimer > 0) return;
    
    // Shield Bearer: Block damage from front
    if (modifier == EnemyModifier.shieldBearer && knockbackDir != null) {
      // Calculate if damage is from front (within 90 degrees of facing direction)
      Vector2 facingDir = Vector2.zero();
      if (_animator.controller.skeleton.allPoints.isNotEmpty) {
        // Estimate facing direction from velocity or position relative to player
        Vector2 toPlayer = gameRef.player.position - position;
        if (toPlayer.length > 1) {
          facingDir = toPlayer.safeNormalized();
        }
      }
      
      Vector2 damageDir = knockbackDir.safeNormalized();
      double dot = facingDir.dot(damageDir);
      
      // If damage comes from front (dot > 0 means same direction), block it
      if (dot > 0) {
        // Blocked! Play block effect
        gameRef.world.add(DamageText(0, position.clone() + Vector2(0, -30)));
        SoundService.instance.playDamage(); // Reuse sound for block
        return; // No damage taken
      }
    }
    
    gameRef.world.add(DamageText(amount, position.clone() + Vector2(0, -30)));
    health -= amount;
    if (knockbackDir != null) _knockbackVelocity = knockbackDir.safeNormalized() * 400.0;
    _invulnerableTimer = 0.5;
    if (health <= 0) {
      health = 0;
      removeFromParent();
      gameRef.killCount++;
      // ... drops ...
      gameRef.world.add(XpGem(isElite ? 50 : 10)..position = position);
      
      // Spawn power-up with 3% chance
      final Random rng = Random();
      if (rng.nextDouble() < 0.03) {
        final powerUpType = PowerUpType.values[rng.nextInt(PowerUpType.values.length)];
        gameRef.world.add(PowerUp(powerUpType)..position = position + Vector2((rng.nextDouble() - 0.5) * 20, (rng.nextDouble() - 0.5) * 20));
      }
      
      SoundService.instance.playExplosion(isLarge: isElite);
      gameRef.world.add(VisualEffects.createExplosion(position));
    }
  }

  @override
  void render(Canvas canvas) {
    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: (size / 2).toOffset() + const Offset(0, 15), width: width, height: width * 0.3),
      Paint()..color = Colors.black.withOpacity(0.3)
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
        Paint()..color = Colors.red.withOpacity(opacity)
      );
      canvas.restore();
    }

    // Render Procedural Enemy
    _animator.render(canvas, Vector2(size.x / 2, size.y / 2 + 5), size.y);

    // Shield Bearer: Draw shield in front
    if (modifier == EnemyModifier.shieldBearer) {
      // Calculate facing direction
      Vector2 toPlayer = gameRef.player.position - position;
      if (toPlayer.length > 1) {
        Vector2 facingDir = toPlayer.safeNormalized();
        double angle = atan2(facingDir.y, facingDir.x);
        
        canvas.save();
        canvas.translate(size.x / 2, size.y / 2);
        canvas.rotate(angle);
        
        // Draw shield arc
        final shieldPaint = Paint()
          ..color = Colors.blue.withOpacity(0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4;
        canvas.drawArc(
          Rect.fromLTWH(-15, -20, 30, 40),
          -pi / 3,
          2 * pi / 3,
          false,
          shieldPaint
        );
        
        // Shield fill
        final shieldFill = Paint()
          ..color = Colors.blue.withOpacity(0.2)
          ..style = PaintingStyle.fill;
        canvas.drawArc(
          Rect.fromLTWH(-15, -20, 30, 40),
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
       canvas.drawCircle((size/2).toOffset(), size.x/2, Paint()..color = const Color(0x88FFFFFF));
    }
  }
}

class DamageText extends PositionComponent {
  final int damage;
  double _lifeTime = 0.0;
  final bool isCrit;

  DamageText(this.damage, Vector2 pos, {this.isCrit = false}) {
    position = pos;
    anchor = Anchor.center;
    priority = 200;
  }

  @override
  void render(Canvas canvas) {
    final textSpan = TextSpan(
      text: damage.toString(),
      style: TextStyle(
        color: isCrit ? Colors.yellow : Colors.white,
        fontSize: isCrit ? 26 : 18,
        fontWeight: FontWeight.bold,
        shadows: const [Shadow(blurRadius: 2, color: Colors.black, offset: Offset(1, 1))],
      ),
    );
    final tp = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
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

  XpGem(this.amount) : super(size: Vector2.all(10), anchor: Anchor.center);

  @override
  void render(Canvas canvas) {
    canvas.drawCircle((size / 2).toOffset(), 4, Paint()..color = const Color(0xFF00FF00));
    canvas.drawCircle((size / 2).toOffset(), 2, Paint()..color = Colors.white);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _lifeTime += dt;
    position.y += sin(_lifeTime * 5) * 0.5;
  }
}

class PowerUp extends PositionComponent with HasGameRef<RpgGame> {
  final PowerUpType type;
  double _lifeTime = 0.0;
  double _hoverTime = 0.0;

  PowerUp(this.type) : super(size: Vector2.all(30), anchor: Anchor.center);

  @override
  void update(double dt) {
    super.update(dt);
    _lifeTime += dt;
    _hoverTime += dt;
    
    // Hover effect
    position.y += sin(_hoverTime * 3) * 0.5;
    
    // Collection check
    if (gameRef.player.position.distanceTo(position) < 30) {
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
        final healAmount = (gameRef.player.maxHealth * 0.2).toInt();
        gameRef.player.health = (gameRef.player.health + healAmount).clamp(0, gameRef.player.maxHealth);
        gameRef.world.add(DamageText(healAmount, position, isCrit: true));
        break;
        
      case PowerUpType.frenzy:
        // Activate frenzy for 5 seconds
        gameRef.player._frenzyTimer = 5.0;
        gameRef.hud.showStory("FRENZY MODE!");
        break;
        
      case PowerUpType.magnet:
        // Magnetize all XpGems
        for (final gem in gameRef.world.children.whereType<XpGem>()) {
          gem.isMagnetized = true;
        }
        break;
        
      case PowerUpType.nuke:
        // Damage all non-elite enemies
        int killed = 0;
        for (final child in gameRef.world.children) {
          if (child is Enemy && !child.isElite) {
            child.takeDamage(9999);
            killed++;
          }
        }
        gameRef.cameraShake(5.0);
        // Flash effect
        gameRef.world.add(VisualEffects.createExplosion(gameRef.player.position, scale: 5.0));
        if (killed > 0) {
          gameRef.hud.showStory("NUKE! $killed KILLED");
        }
        break;
    }
  }

  @override
  void render(Canvas canvas) {
    final Paint paint = Paint();
    final Offset center = (size / 2).toOffset();
    
    switch (type) {
      case PowerUpType.health:
        paint.color = Colors.red;
        canvas.drawCircle(center, 12, paint);
        canvas.drawCircle(center, 8, Paint()..color = Colors.white);
        // Draw cross
        final crossPaint = Paint()..color = Colors.red..strokeWidth = 3;
        canvas.drawLine(center + Offset(-6, 0), center + Offset(6, 0), crossPaint);
        canvas.drawLine(center + Offset(0, -6), center + Offset(0, 6), crossPaint);
        break;
        
      case PowerUpType.frenzy:
        paint.color = Colors.orange;
        canvas.drawCircle(center, 12, paint);
        paint.color = Colors.yellow;
        canvas.drawCircle(center, 8, paint);
        // Draw lightning bolt
        final boltPaint = Paint()..color = Colors.white..strokeWidth = 2;
        canvas.drawLine(center + Offset(-4, -6), center + Offset(2, 0), boltPaint);
        canvas.drawLine(center + Offset(2, 0), center + Offset(-2, 6), boltPaint);
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
      ..color = paint.color.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, 15, glowPaint);
  }
}

class EnemyProjectile extends PositionComponent with HasGameRef<RpgGame> {
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

    if (position.distanceTo(gameRef.player.position) < gameRef.player.size.x / 2) {
      gameRef.player.takeDamage(10);
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
  ArrowProjectile(Vector2 pos, Vector2 target) : super(pos, target);

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
      data: gameRef.animationData
    );
    _animator.play("Standard Idle");
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
       
       // Check if "Shooting Arrow" animation has completed
       String? currentClipName = _animator.controller.activeClip?.name;
       bool animationFinished = false;
       
       // If animation changed from "Shooting Arrow" to something else, it finished
       if (_lastActiveClipName == "Shooting Arrow" && currentClipName != "Shooting Arrow") {
         animationFinished = true;
       }
       // If animation stopped playing (reached end)
       else if (!_animator.isPlaying && _lastActiveClipName == "Shooting Arrow") {
         animationFinished = true;
       }
       // Timeout fallback (animation is sped up 5x, so should complete in ~0.2s)
       else if (_shootingAnimationTimer > 0.3) {
         animationFinished = true;
       }
       
       // Fire arrow when animation completes
       if (animationFinished && !_hasFired) {
         gameRef.world.add(ArrowProjectile(position, gameRef.player.position));
         _hasFired = true;
       }
       
       if (animationFinished) {
         _isShooting = false;
         _shootingAnimationTimer = 0.0;
         _hasFired = false; // Reset for next shot
       }
       
       _lastActiveClipName = currentClipName;
    } else {
      if (_knockbackVelocity.length > 5) {
        velocity = _knockbackVelocity;
        position.add(velocity * dt);
        _knockbackVelocity.scale(0.9);
      } else {
        _knockbackVelocity.setZero();

        // Custom movement: maintain distance
        double dist = position.distanceTo(gameRef.player.position);
        Vector2 dir = (gameRef.player.position - position).safeNormalized();

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
           _animator.play("Standard Idle");
        }
    }

    // Update Animator
    // If shooting, force facing towards player
    if (_isShooting) {
       Vector2 faceDir = (gameRef.player.position - position).safeNormalized();
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
  double _angle = 0.0;
  static const double _orbitRadius = 80.0;
  static const double _speed = 2.0;

  OrbitalShield(this.player) : super(size: Vector2.all(20), anchor: Anchor.center);

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
           child.takeDamage(100, knockbackDir: child.position - player.position);
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

class Barrel extends PositionComponent with HasGameRef<RpgGame> {
  double radius = 25;
  int health = 3;

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
    gameRef.world.add(VisualEffects.createExplosion(position, scale: 2.0));
    SoundService.instance.playExplosion(); // Re-using existing sound

    // Area Damage
    for (final child in gameRef.world.children) {
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
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.brown.shade700);
    canvas.drawLine(Offset(0, 10), Offset(width, 10), Paint()..color = Colors.black..strokeWidth = 2);
    canvas.drawLine(Offset(0, height - 10), Offset(width, height - 10), Paint()..color = Colors.black..strokeWidth = 2);
  }
}

class SpikeTrap extends PositionComponent with HasGameRef<RpgGame> {
  SpikeTrap() : super(anchor: Anchor.center, size: Vector2.all(40));

  @override
  void update(double dt) {
    super.update(dt);
    // Player collision
    if (gameRef.player.position.distanceTo(position) < 30) {
       gameRef.player.takeDamage(5);
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.grey.shade800);
    // Spikes
    Paint p = Paint()..color = Colors.grey.shade400;
    canvas.drawCircle(Offset(10, 10), 5, p);
    canvas.drawCircle(Offset(30, 10), 5, p);
    canvas.drawCircle(Offset(10, 30), 5, p);
    canvas.drawCircle(Offset(30, 30), 5, p);
  }
}

class MagnetItem extends PositionComponent {
  double _hoverTime = 0.0;

  MagnetItem() : super(anchor: Anchor.center, size: Vector2.all(30));

  @override
  void update(double dt) {
    super.update(dt);
    _hoverTime += dt;
    // Hover effect
    final double offset = sin(_hoverTime * 3) * 5;
    // Visual only offset, actual position stays
  }

  @override
  void render(Canvas canvas) {
     // Draw Magnet U-shape
     Paint p = Paint()..color = Colors.red..style = PaintingStyle.stroke..strokeWidth = 6..strokeCap = StrokeCap.round;
     canvas.drawArc(Rect.fromLTWH(5, 5, 20, 20), 0, -pi, false, p);
     // Tips
     Paint tip = Paint()..color = Colors.grey.shade300;
     canvas.drawRect(Rect.fromLTWH(5, 15, 6, 6), tip);
     canvas.drawRect(Rect.fromLTWH(19, 15, 6, 6), tip);
  }
}

class HurricaneKickEffect extends PositionComponent {
  double _lifeTime = 0.0;
  static const double _duration = 0.5; // Increased duration
  final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.0
    ..strokeCap = StrokeCap.round;

  HurricaneKickEffect() : super(anchor: Anchor.center, size: Vector2.all(100)); // Larger area

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
    _paint.color = Colors.cyanAccent.withOpacity(opacity);

    canvas.save();
    // Center logic: Move to center of component (50, 50) since size is 100
    canvas.translate(size.x / 2, size.y / 2);
    canvas.rotate(progress * pi * 4); // Fast spin

    // Draw spiral lines
    for(int i=0; i<3; i++) {
       canvas.drawArc(
         Rect.fromCircle(center: Offset.zero, radius: 40 + (i * 5) + (progress * 20)),
         (i * 2.0),
         2.0,
         false,
         _paint
       );
    }

    canvas.restore();
  }
}

class DashCooldownBar extends PositionComponent with HasVisibility {
  final Player player;
  final Paint _barPaint = Paint()..style = PaintingStyle.fill;
  final Paint _bgPaint = Paint()..color = Colors.black.withOpacity(0.5)..style = PaintingStyle.fill;
  final Paint _borderPaint = Paint()..color = Colors.white.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 1;

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
