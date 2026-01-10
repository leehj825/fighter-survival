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
    _textPainter.paint(
      canvas,
      Offset((size.x - _textPainter.width) / 2, (size.y - _textPainter.height) / 2),
    );
  }
}

/// The main Game class.
class RpgGame extends FlameGame with MultiTouchDragDetector, TapDetector {
  final bool resumeGame;
  late Player player;
  late Hud hud;
  late VirtualJoystick joystick;
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

  // Movement State
  Vector2? _moveStartPos;

  // Action Gesture State
  Vector2? _lastActionPos;
  DateTime? _lastActionTime;

  // Tweakable Variable for Dash Sensitivity
  static const double dashVelocityThreshold = 2500.0;

  // Camera Shake State
  double _shakeTimer = 0.0;
  double _shakeIntensity = 0.0;

  late World world;
  late CameraComponent cameraComponent;

  @override
  Future<void> onLoad() async {
    // Ensure music is playing (but don't restart if it is)
    SoundService.instance.playBackgroundMusic('audio/main2.mp3');

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

    // Add Infinite Background (Grid)
    world.add(GridBackground());

    // Spawn Obstacles (Rough background elements)
    _spawnObstacles();

    // Setup Camera
    cameraComponent = CameraComponent(world: world);
    cameraComponent.viewfinder.anchor = Anchor.center;
    cameraComponent.follow(player);
    add(cameraComponent);
    add(world);

    // Add HUD
    hud = Hud();
    add(hud);

    // Add Joystick (On top of HUD or World? HUD is Priority 100. Joystick on top of everything)
    joystick = VirtualJoystick()..priority = 200;
    hud.add(joystick); // Add to HUD (Root Component) to ensure screen-space alignment

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

  // --- TAP TO SHOOT (If Blaster Unlocked) ---
  @override
  void onTapDown(TapDownInfo info) {
    if (gameOver) return;

    final Vector2 tapPos = info.eventPosition.widget;

    // Check Button Taps
    if (slashButton.containsPoint(tapPos - hud.position)) {
      player.slash();
      return;
    }

    // Check if blaster is unlocked
    if (GameData().unlockBlaster) {
       // Fire towards tap position
       Vector2 screenCenter = size / 2;
       Vector2 dir = (tapPos - screenCenter).safeNormalized();

       player.shoot(dir);
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
        // Handled by onTapDown usually, but if drag starts here, ignore it for dash/move
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
    // 3. Assign Action Pointer (Right side, Swipe for Dash)
    else if (_actionPointerId == null) {
      _actionPointerId = pointerId;
      _lastActionPos = startPos;
      _lastActionTime = DateTime.now();
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
  Vector2 _dashDirection = Vector2.zero();
  bool isSlashing = false;

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

    // Initialize Animator instead of SVGs
    _animator = StickmanAnimator(color: Colors.cyanAccent, scale: 1.2);
  }

  @override
  void update(double dt) {
    super.update(dt);

    // ... Keep existing cooldown logic ...
    if (_damageCooldown > 0) _damageCooldown -= dt;
    if (_currentDashCooldown > 0) _currentDashCooldown -= dt;

    Vector2 velocity = Vector2.zero();

    if (isDashing) {
      _dashTimer -= dt;
      double progress = (1.0 - (_dashTimer / _dashDuration)).clamp(0.0, 1.0);
      double currentSpeedMult = _dashSpeedMult * (1.0 - Curves.easeOutCubic.transform(progress) * 0.7);

      velocity = _dashDirection * (_baseSpeed * currentSpeedMult);
      position.add(velocity * dt);

      if (_dashTimer % 0.05 < dt) {
         gameRef.world.add(VisualEffects.createDashTrail(position, angle));
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
    _animator.render(canvas, Vector2(size.x / 2, size.y / 2 + 10), size.y);
  }

  // ... Keep existing methods (dash, slash, shoot, gainXp, etc) ...
  void dash(Vector2 direction) {
    if (isDashing || _currentDashCooldown > 0) return;
    isDashing = true;
    isSlashing = false; // Reset slash if dashing
    _dashTimer = _dashDuration;
    _currentDashCooldown = dashCooldownMax;

    if (direction.length > 0) {
      _dashDirection = direction.safeNormalized();
    } else {
      _dashDirection = Vector2(1, 0);
    }
  }

  void slash() {
    if (isSlashing) return;
    isSlashing = true;
    _animator.isAttacking = true; // Trigger animator punch/slash
    final sword = SwordEffect();
    sword.position = size / 2;
    add(sword);
  }

  // ... shoot, gainXp, _levelUp, takeDamage same as before ...
  // Be sure to verify takeDamage logic is preserved
  void shoot(Vector2 dir) {
    int sfxType = damageMult > 1.5 ? 1 : 0;
    SoundService.instance.playShoot(variant: sfxType);
    gameRef.world.add(PlayerProjectile(position, dir, damageMult));
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

  // NEW: Animator
  late StickmanAnimator _animator;

  Enemy({this.isElite = false, this.modifier = EnemyModifier.none})
      : super(size: Vector2.all(isElite ? 100 : 50), anchor: Anchor.center) {
     if(isElite) health = health * 5;
     _maxHealth = health;
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    // Choose color/scale based on type
    Color c = Colors.redAccent;
    double s = 1.0;
    WeaponType w = WeaponType.sword; // Default enemy has sword

    if (isElite) {
      c = Colors.deepPurpleAccent;
      s = 2.0;
      w = WeaponType.axe;
    } else if (modifier == EnemyModifier.swift) {
      c = Colors.yellowAccent;
    } else if (modifier == EnemyModifier.ghostly) {
      c = Colors.white.withOpacity(0.5);
    }

    _animator = StickmanAnimator(color: c, scale: s, weaponType: w);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_invulnerableTimer > 0) _invulnerableTimer -= dt;

    // ... Regen logic ...
    if (modifier == EnemyModifier.regen && health < _maxHealth && health > 0) {
        _regenTimer += dt;
        if (_regenTimer >= 1.0) {
            _regenTimer = 0;
            health++;
        }
    }

    Vector2 velocity = Vector2.zero();

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
          velocity = dir.safeNormalized() * currentSpeed;
          position.add(velocity * dt);
        }
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

    // Render Procedural Enemy
    _animator.render(canvas, Vector2(size.x / 2, size.y / 2 + 5), size.y);

    // Flash
    if (_invulnerableTimer > 0) {
       canvas.drawCircle((size/2).toOffset(), size.x/2, Paint()..color = const Color(0x88FFFFFF));
    }
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

  ShooterEnemy() : super();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    // Override color/scale for Shooter and set weapon to Bow
    _animator = StickmanAnimator(color: Colors.purpleAccent, scale: 1.0, weaponType: WeaponType.bow);
  }

  @override
  void update(double dt) {
    // Custom movement logic first
    if (_invulnerableTimer > 0) {
      _invulnerableTimer -= dt;
    }

    Vector2 velocity = Vector2.zero();

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
       // Trigger attack anim
       _animator.isAttacking = true;
       gameRef.world.add(ArrowProjectile(position, gameRef.player.position));
    }

    // Update Animator
    _animator.update(dt, velocity, false);
  }
}

enum EnemyModifier { none, swift, ghostly, regen }

class Barrel extends PositionComponent with HasGameRef<RpgGame> {
  int hp = 1;
  final double radius = 25;
  final double height = 40;

  Barrel() : super(anchor: Anchor.center, size: Vector2.all(50));

  @override
  void render(Canvas canvas) {
    // Red cylinder with danger marking
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
    canvas.drawPath(bodyPath, Paint()..color = Colors.red.shade900);

    // Top
    canvas.drawCircle(topCenter, r, Paint()..color = Colors.red.shade700);

    // Danger Marking (Yellow X on top)
    final Paint markPaint = Paint()..color = Colors.yellow..strokeWidth = 4.0..style = PaintingStyle.stroke;
    canvas.drawLine(topCenter + Offset(-10, -10), topCenter + Offset(10, 10), markPaint);
    canvas.drawLine(topCenter + Offset(10, -10), topCenter + Offset(-10, 10), markPaint);

    // Rim
    canvas.drawCircle(topCenter, r, Paint()..style = PaintingStyle.stroke ..color = Colors.white.withOpacity(0.3));
  }

  void takeDamage() {
     if (hp <= 0) return;
     hp--;
     if (hp <= 0) _explode();
  }

  void _explode() {
    removeFromParent();
    gameRef.world.add(VisualEffects.createExplosion(position, scale: 3.0));

    // Deal damage
    // Find entities in radius 150
    for(final child in gameRef.world.children) {
         if (child is Enemy) {
             if (child.position.distanceTo(position) < 150) {
                 child.takeDamage(500, knockbackDir: child.position - position);
             }
         } else if (child is Player) {
              if (child.position.distanceTo(position) < 150) {
                  child.takeDamage(500); // Massive damage
              }
         }
    }
    gameRef.cameraShake(5.0);
  }
}

class MagnetItem extends PositionComponent with HasGameRef<RpgGame> {
  late TextPainter _tp;

  MagnetItem() : super(anchor: Anchor.center, size: Vector2.all(30));

  @override
  Future<void> onLoad() async {
    const TextSpan span = TextSpan(
        text: "M",
        style: TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold));
    _tp = TextPainter(text: span, textDirection: TextDirection.ltr);
    _tp.layout();
  }

  @override
  void render(Canvas canvas) {
    final double w = width;
    final double h = height;

    // Simple Square Icon with 'M'
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
    canvas.drawRect(
        Rect.fromLTWH(2, 2, w - 4, h - 4), Paint()..color = Colors.blue);

    _tp.paint(canvas, Offset((w - _tp.width) / 2, (h - _tp.height) / 2));
  }
}

class OrbitalShield extends PositionComponent with HasGameRef<RpgGame> {
  final Player _player;
  double _angle = 0.0;
  final double _orbitRadius = 80.0;
  late double _orbitSpeed;
  late int _damage;

  OrbitalShield(this._player) : super(size: Vector2.all(20), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
     super.onLoad();
     final int level = GameData().levelShield;
     // Base speed 2.0, +0.5 per level beyond 1
     _orbitSpeed = 2.0 + (level - 1) * 0.5;
     // Base damage 10, +5 per level beyond 1
     _damage = 10 + (level - 1) * 5;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_player.isRemoved) {
      removeFromParent();
      return;
    }

    _angle += _orbitSpeed * dt;
    position = _player.position + Vector2(cos(_angle), sin(_angle)) * _orbitRadius;

    // Collision Logic
    for (final child in gameRef.world.children) {
      if (child is Enemy) {
        if (child.position.distanceTo(position) < (child.size.x / 2 + size.x / 2)) {
           child.takeDamage(_damage, knockbackDir: child.position - _player.position);
        }
      } else if (child is EnemyProjectile) {
        if (child.position.distanceTo(position) < (child.size.x / 2 + size.x / 2)) {
           child.removeFromParent(); // Block projectile
        }
      }
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawCircle(Offset.zero, 8, Paint()..color = Colors.cyanAccent.withOpacity(0.8));
    canvas.drawCircle(Offset.zero, 10, Paint()..style=PaintingStyle.stroke ..color = Colors.white.withOpacity(0.5) ..strokeWidth=2);
  }
}

class SpikeTrap extends PositionComponent with HasGameRef<RpgGame> {
  double _timer = 0.0;
  int _state = 0; // 0: Safe, 1: Warning, 2: Active

  SpikeTrap() : super(anchor: Anchor.center, size: Vector2.all(60));

  @override
  void update(double dt) {
    super.update(dt);
    _timer += dt;

    // Cycle: 2s Safe -> 1s Warning -> 1s Active
    if (_state == 0 && _timer > 2.0) {
      _state = 1;
      _timer = 0;
    } else if (_state == 1 && _timer > 1.0) {
      _state = 2;
      _timer = 0;
    } else if (_state == 2 && _timer > 1.0) {
      _state = 0;
      _timer = 0;
    }

    if (_state == 2) {
       // Damage Player
       if (gameRef.player.position.distanceTo(position) < 30) {
          gameRef.player.takeDamage(20);
       }
    }
  }

  @override
  void render(Canvas canvas) {
    // Base
    canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: 50, height: 50), Paint()..color = Colors.black.withOpacity(0.3));

    if (_state == 0) {
       // Safe (Dark Grey)
       canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: 40, height: 40), Paint()..color = Colors.grey.shade800);
    } else if (_state == 1) {
       // Warning (Flashing Red)
       double flash = (sin(_timer * 20) + 1) / 2;
       canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: 40, height: 40), Paint()..color = Color.lerp(Colors.grey.shade800, Colors.red, flash)!);
    } else {
       // Active (Spikes)
       canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: 40, height: 40), Paint()..color = Colors.grey.shade600);
       // Spikes
       final Paint spikePaint = Paint()..color = Colors.white;
       canvas.drawCircle(Offset(-10, -10), 5, spikePaint);
       canvas.drawCircle(Offset(10, -10), 5, spikePaint);
       canvas.drawCircle(Offset(-10, 10), 5, spikePaint);
       canvas.drawCircle(Offset(10, 10), 5, spikePaint);
       canvas.drawCircle(Offset(0, 0), 5, spikePaint);
    }
  }
}
