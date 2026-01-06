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

/// Extension for safe vector normalization
extension SafeVector2 on Vector2 {
  Vector2 safeNormalized() {
    if (length2 == 0) {
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

    // Draw Base
    canvas.drawCircle(Offset.zero, baseRadius, _basePaint);
    canvas.drawCircle(Offset.zero, baseRadius, _baseStroke);

    // Draw Knob
    canvas.drawCircle(_knobPos.toOffset(), knobRadius, _knobPaint);
  }
}

/// The main Game class.
class RpgGame extends FlameGame with MultiTouchDragDetector, TapDetector {
  late Player player;
  late Hud hud;
  late VirtualJoystick joystick;

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
  Vector2? _actionStartPos;
  Vector2? _lastActionPos;
  DateTime? _lastActionTime;

  // Slash Detection State
  double _accumulatedRotation = 0.0;
  static const double _slashTimeWindow = 1.0;
  double _slashWindowTimer = 0.0;
  static const double _slashThreshold = 250.0 * (pi / 180.0);

  // Tweakable Variable for Dash Sensitivity
  static const double dashVelocityThreshold = 2500.0;

  late World world;
  late CameraComponent cameraComponent;

  @override
  Future<void> onLoad() async {
    // Create World
    world = World();

    // Initialize Player with Stats from GameData
    player = Player()..anchor = Anchor.center;
    world.add(player);

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
    cameraComponent.viewport.add(joystick); // Add to viewport so it stays on screen

    // Initial Wave
    _spawnWave();
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
  }

  void cameraShake(double intensity) {
     cameraComponent.viewfinder.add(
        MoveEffect.by(Vector2(5, 5), EffectController(duration: 0.1, alternate: true, repeatCount: 3))
     );
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
      world.add(Enemy(isElite: true)..position = player.position + Vector2(600, 0));
    }
  }

  @override
  void update(double dt) {
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

    // Slash Timer Logic
    if (_slashWindowTimer > 0) {
      _slashWindowTimer -= dt;
      if (_slashWindowTimer <= 0) {
        _accumulatedRotation = 0.0;
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
      if (player.position.distanceTo(gem.position) < 100) {
        // Magnet
        gem.position.add((player.position - gem.position).safeNormalized() * 300 * dt);
        if (player.position.distanceTo(gem.position) < 10) {
          // In new logic, gems are also currency.
          // We treat "XP Gems" as the currency source for now.
          runGems += gem.amount;
          player.gainXp(gem.amount);
          gem.removeFromParent();
        }
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
          Vector2 push = (player.position - child.position).safeNormalized() * (radiusP - distP);
          player.position += push;
        }

        // Enemy vs Obstacle
        for (final other in world.children) {
          if (other is Enemy) {
             double distE = other.position.distanceTo(child.position);
             double radiusE = (other.size.x / 2) + child.radius;
             if (distE < radiusE) {
               Vector2 push = (other.position - child.position).safeNormalized() * (radiusE - distE);
               other.position += push;
             }
          }
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

    // Check if blaster is unlocked
    if (GameData().unlockBlaster) {
       // Fire towards tap position
       Vector2 tapPos = info.eventPosition.widget;
       Vector2 screenCenter = size / 2;
       Vector2 dir = (tapPos - screenCenter).safeNormalized();

       player.shoot(dir);
    }
  }

  // --- MULTI-TOUCH INPUT HANDLING ---

  @override
  void onDragStart(int pointerId, DragStartInfo info) {
    if (gameOver) {
       // Reset Game Logic if needed, or simple restart
       _resetGame();
       return;
    }

    final Vector2 startPos = info.eventPosition.widget;

    // 1. Assign Movement Pointer (First Touch)
    if (_movePointerId == null) {
      _movePointerId = pointerId;
      _moveStartPos = startPos;

      // Show Joystick
      joystick.position = startPos;
      joystick.isVisible = true;
      joystick.reset();
    }
    // 2. Assign Action Pointer (Second Touch)
    else if (_actionPointerId == null) {
      _actionPointerId = pointerId;
      _actionStartPos = startPos;
      _lastActionPos = startPos;
      _lastActionTime = DateTime.now();
      _resetGestureLogic();
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

    // Handle Actions (Dash/Slash)
    if (pointerId == _actionPointerId && _lastActionPos != null) {
      final DateTime now = DateTime.now();

      // 1. Dash (Flick)
      if (_lastActionTime != null) {
        final double dtSeconds = now.difference(_lastActionTime!).inMicroseconds / 1000000.0;
        if (dtSeconds > 0) {
          final double dist = currentPos.distanceTo(_lastActionPos!);
          final double velocity = dist / dtSeconds;

          if (velocity > dashVelocityThreshold) {
            player.dash(currentPos - _lastActionPos!);
          }
        }
      }

      // 2. Slash (Circular)
      if (!player.isSlashing && _actionStartPos != null) {
        final Vector2 center = _actionStartPos!;
        final Vector2 toFinger = currentPos - center;
        final Vector2 prevToFinger = (_lastActionPos ?? currentPos) - center;

        if (toFinger.length > 20 && prevToFinger.length > 20) {
          final double currentAngle = atan2(toFinger.y, toFinger.x);
          final double prevAngle = atan2(prevToFinger.y, prevToFinger.x);

          double diff = currentAngle - prevAngle;
          while (diff < -pi) diff += 2 * pi;
          while (diff > pi) diff -= 2 * pi;

          _accumulatedRotation += diff;
          _slashWindowTimer = _slashTimeWindow;

          if (_accumulatedRotation.abs() > _slashThreshold) {
            player.slash();
            _accumulatedRotation = 0.0;
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
      _actionStartPos = null;
      _lastActionPos = null;
      _accumulatedRotation = 0.0;
    }
  }

  void _resetGestureLogic() {
    _accumulatedRotation = 0.0;
    _slashWindowTimer = _slashTimeWindow;
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

       hud.storyText.text = "";
       _spawnWave();
       overlays.remove('GameOver');
  }

  void onGameOver() {
    gameOver = true;
    GameData().addGems(runGems);
    overlays.add('GameOver');
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
  Vector2? moveDirection;
  static const double _baseSpeed = 200.0;
  static const double _dashSpeedMult = 3.5;

  late int health;
  late int maxHealth;
  double _damageCooldown = 0.0;

  // Progression Fields
  int level = 1;
  int xp = 0;
  int xpToNextLevel = 10;
  double damageMult = 1.0;

  // Meta-Progression Stats
  late double dashCooldownMax;

  bool isDashing = false;
  double _dashTimer = 0.0;
  static const double _dashDuration = 0.32;
  double _currentDashCooldown = 0.0;
  Vector2 _dashDirection = Vector2.zero();

  bool isSlashing = false;

  final Paint _cyanPaint = Paint()..color = const Color(0xFF00FFFF);
  final Paint _yellowPaint = Paint()..color = const Color(0xFFFFFF00);

  Player() : super(size: Vector2.all(40));

  @override
  Future<void> onLoad() async {
    super.onLoad();
    // Initialize Stats from GameData
    final data = GameData();
    maxHealth = 100 + (data.levelHp * 20);
    health = maxHealth;

    // Base dash cooldown 0.8s, reduced by 10% per level
    dashCooldownMax = 0.8 * pow(0.9, data.levelDash);
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (_damageCooldown > 0) {
      _damageCooldown -= dt;
    }

    if (_currentDashCooldown > 0) {
      _currentDashCooldown -= dt;
    }

    if (isDashing) {
      _dashTimer -= dt;

      // Ease-out movement
      double progress = (1.0 - (_dashTimer / _dashDuration)).clamp(0.0, 1.0); // Clamp to prevent <0 or >1
      // Use easeOutCubic for a sharper drop-off to prevent "bouncy" feeling at end
      double currentSpeedMult = _dashSpeedMult * (1.0 - Curves.easeOutCubic.transform(progress) * 0.7);

      position.add(_dashDirection * (_baseSpeed * currentSpeedMult) * dt);

      // Spawn Trail
      if (_dashTimer % 0.05 < dt) {
         gameRef.world.add(VisualEffects.createDashTrail(position, angle));
      }

      if (_dashTimer <= 0) {
        isDashing = false;
        angle = 0;
      }
    } else if (moveDirection != null && moveDirection != Vector2.zero()) {
      position.add(moveDirection! * _baseSpeed * dt);
    }
  }

  @override
  void render(Canvas canvas) {
    // 2.5D Rendering Constants
    const double h = 15.0; // Height of the cylinder
    final double r = width / 2;
    final Offset center = (size / 2).toOffset();

    // Shadow (Base)
    canvas.drawOval(
      Rect.fromCenter(center: center, width: width, height: width * 0.6),
      Paint()..color = Colors.black.withOpacity(0.3)
    );

    if (isDashing) {
      // Dash Visual: Triangle "Flying" low
      final Path path = Path();
      // Adjust points to account for height/offset
      path.moveTo(width, (height / 2) - h/2);
      path.lineTo(0, 0 - h/2);
      path.lineTo(0, height - h/2);
      path.close();
      canvas.drawPath(path, _yellowPaint);
    } else {
      // Cylinder Body (Darker)
      final Paint bodyPaint = Paint()..color = const Color(0xFF00AAAA); // Darker Cyan

      final Offset topCenter = center + Offset(0, -h);

      // Draw Body
      final Path bodyPath = Path();
      bodyPath.moveTo(center.dx - r, center.dy); // Bottom Left
      bodyPath.lineTo(center.dx + r, center.dy); // Bottom Right
      bodyPath.lineTo(topCenter.dx + r, topCenter.dy); // Top Right
      bodyPath.lineTo(topCenter.dx - r, topCenter.dy); // Top Left
      bodyPath.close();
      canvas.drawPath(bodyPath, bodyPaint);

      // Draw Top (Main Circle)
      canvas.drawCircle(topCenter, r, _cyanPaint);

      // Highlight/Rim (Optional)
      canvas.drawCircle(topCenter, r, Paint()..style = PaintingStyle.stroke ..color = Colors.white.withOpacity(0.5) ..strokeWidth = 2);
    }
  }

  void dash(Vector2 direction) {
    if (isDashing || _currentDashCooldown > 0) return;

    isDashing = true;
    _dashTimer = _dashDuration;
    _currentDashCooldown = dashCooldownMax;

    if (direction.length > 0) {
      _dashDirection = direction.safeNormalized();
      angle = atan2(_dashDirection.y, _dashDirection.x);
    } else {
      _dashDirection = Vector2(1, 0);
      angle = 0;
    }
  }

  void slash() {
    if (isSlashing) return;

    isSlashing = true;
    final sword = SwordEffect();
    sword.position = size / 2;
    add(sword);
  }

  void shoot(Vector2 dir) {
    // Basic cooldown for shooting? Let's say 0.3s
    // For now, no strict cooldown was requested, but let's add a small one to prevent spam lag
    gameRef.world.add(PlayerProjectile(position, dir, damageMult));
  }

  void gainXp(int amount) {
    xp += amount;
    if (xp >= xpToNextLevel) {
      _levelUp();
    }
  }

  void _levelUp() {
    xp -= xpToNextLevel;
    level++;
    xpToNextLevel = (xpToNextLevel * 1.5).toInt();

    // Stats Up: Streamlined
    damageMult += 0.1;
    // Heal to Full
    health = maxHealth;

    gameRef.hud.showStory("LEVEL UP! SYSTEMS RESTORED.");
    gameRef.world.add(VisualEffects.createExplosion(position));
    gameRef.cameraShake(1.0);
  }

  @override
  void takeDamage(int amount) {
    if (_damageCooldown > 0 || isDashing) return;

    health -= amount;
    _damageCooldown = 1.0;
    gameRef.cameraShake(2.0); // Shake Screen
    gameRef.world.add(DamageText(amount, position, isCrit: true)); // Show red text

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
  int health = 2;
  static const double _speed = 100.0;
  Vector2? _roamTarget;
  double _roamTimer = 0.0;
  Vector2 _knockbackVelocity = Vector2.zero();
  double _invulnerableTimer = 0.0;
  bool isElite = false;

  final Paint _redPaint = Paint()..color = const Color(0xFFFF0000);

  Enemy({this.isElite = false}) : super(size: Vector2.all(isElite ? 80 : 40), anchor: Anchor.center) {
     if(isElite) health = health * 5;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (_invulnerableTimer > 0) {
      _invulnerableTimer -= dt;
    }

    if (_knockbackVelocity.length > 5) {
      position.add(_knockbackVelocity * dt);
      _knockbackVelocity.scale(0.9);
    } else {
      _knockbackVelocity.setZero();

      _roamTimer -= dt;
      if (_roamTimer <= 0 || _roamTarget == null) {
        _pickNewTarget();
      }

      if (_roamTarget != null) {
        final Vector2 dir = _roamTarget! - position;
        if (dir.length < 5) {
          _pickNewTarget();
        } else {
          position.add(dir.safeNormalized() * _speed * dt);
        }
      }
    }
  }

  void _pickNewTarget() {
    final Random rng = Random();
    // Move towards player with some randomness to avoid stacking perfectly
    Vector2 playerPos = gameRef.player.position;

    double dx = (rng.nextDouble() - 0.5) * 200;
    double dy = (rng.nextDouble() - 0.5) * 200;

    _roamTarget = playerPos + Vector2(dx, dy);
    _roamTimer = 1.0 + rng.nextDouble() * 2.0; // Update target every 1-3 seconds
  }

  void takeDamage(int amount, {Vector2? knockbackDir}) {
    if (_invulnerableTimer > 0) return;

    // Show Damage Number
    gameRef.world.add(DamageText(amount, position.clone() + Vector2(0, -30)));

    health -= amount;
    if (knockbackDir != null) {
       _knockbackVelocity = knockbackDir.safeNormalized() * 400.0;
    }
    _invulnerableTimer = 0.5;

    if (health <= 0) {
      removeFromParent();
      gameRef.killCount++;

      // Drop XP Gem
      gameRef.world.add(XpGem(isElite ? 50 : 10)..position = position);

      gameRef.world.add(VisualEffects.createExplosion(position));
      gameRef.cameraShake(1.0); // Slight shake on kill
    }
  }

  @override
  void render(Canvas canvas) {
    // 2.5D Rendering
    const double h = 15.0;
    final double r = width / 2;
    final Offset center = (size / 2).toOffset();

    // Shadow
    canvas.drawOval(
      Rect.fromCenter(center: center, width: width, height: width * 0.6),
      Paint()..color = Colors.black.withOpacity(0.3)
    );

    // Cylinder Body
    final Paint bodyPaint = Paint()..color = const Color(0xFFAA0000); // Darker Red
    final Offset topCenter = center + Offset(0, -h);

    final Path bodyPath = Path();
    bodyPath.moveTo(center.dx - r, center.dy);
    bodyPath.lineTo(center.dx + r, center.dy);
    bodyPath.lineTo(topCenter.dx + r, topCenter.dy);
    bodyPath.lineTo(topCenter.dx - r, topCenter.dy);
    bodyPath.close();
    canvas.drawPath(bodyPath, bodyPaint);

    // Top
    canvas.drawCircle(topCenter, r, _redPaint);

    // Flash
    if (_invulnerableTimer > 0) {
       final Paint flashPaint = Paint()..color = const Color(0x88FFFFFF);
       canvas.drawCircle(topCenter, r, flashPaint);
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

class ShooterEnemy extends Enemy {
  double _shootTimer = 0.0;

  ShooterEnemy() : super();

  @override
  void render(Canvas canvas) {
     final Path path = Path();
     path.moveTo(0, -20);
     path.lineTo(20, 20);
     path.lineTo(-20, 20);
     path.close();
     canvas.drawPath(path, Paint()..color = Colors.purpleAccent);

     // Add a shadow or highlight to match style
     canvas.drawPath(path, Paint()..style=PaintingStyle.stroke..color=Colors.white.withOpacity(0.5));

     // Flash
    if (_invulnerableTimer > 0) {
       final Paint flashPaint = Paint()..color = const Color(0x88FFFFFF);
       canvas.drawCircle(Offset.zero, 20, flashPaint); // Simple circle flash for shooter
    }
  }

  @override
  void update(double dt) {
    // Handle invulnerability and knockback manually since we are overriding Enemy.update
    if (_invulnerableTimer > 0) {
      _invulnerableTimer -= dt;
    }

    if (_knockbackVelocity.length > 5) {
      position.add(_knockbackVelocity * dt);
      _knockbackVelocity.scale(0.9);
    }

    // Custom movement: maintain distance
    double dist = position.distanceTo(gameRef.player.position);
    Vector2 dir = (gameRef.player.position - position).safeNormalized();

    if (dist < 300) {
       position -= dir * 80 * dt; // Retreat
    } else if (dist > 500) {
       position += dir * 100 * dt; // Chase
    }

    // Shoot Logic
    _shootTimer += dt;
    if (_shootTimer > 2.0) {
       _shootTimer = 0.0;
       gameRef.world.add(EnemyProjectile(position, gameRef.player.position));
    }
  }
}
