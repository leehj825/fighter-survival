import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart' hide Draggable;
import 'package:flame/effects.dart';

import 'grid_background.dart';
import 'hud.dart';
import 'visual_effects.dart';

/// The main Game class.
class RpgGame extends FlameGame with PanDetector {
  late Player player;

  // Game State
  int killCount = 0;
  int wave = 1;
  double _waveTimer = 0.0;
  bool gameOver = false;

  // --- Input State ---
  Vector2? _dragStartPos;
  Vector2? _lastFingerPosition;
  DateTime? _lastInputTime;

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

    // Initialize Player
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
    add(Hud());

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

  void _spawnWave() {
    final Random rng = Random();
    int enemyCount = 3 + wave * 2;

    for (int i = 0; i < enemyCount; i++) {
      Vector2 offset = Vector2(
        (rng.nextDouble() - 0.5) * 800 + (rng.nextBool() ? 400 : -400),
        (rng.nextDouble() - 0.5) * 800 + (rng.nextBool() ? 400 : -400),
      );

      world.add(Enemy()
        ..position = player.position + offset
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (gameOver) return;

    // Wave Management
    bool enemiesAlive = world.children.whereType<Enemy>().isNotEmpty;
    if (!enemiesAlive) {
      _waveTimer += dt;
      if (_waveTimer > 2.0) {
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

    // --- COLLISION LOGIC ---
    for (final child in world.children) {
      // 1. Obstacle Collision
      if (child is Obstacle) {
        // Player vs Obstacle
        double distP = player.position.distanceTo(child.position);
        double radiusP = (player.size.x / 2) + child.radius;
        if (distP < radiusP) {
          Vector2 push = (player.position - child.position).normalized() * (radiusP - distP);
          player.position += push;
        }

        // Enemy vs Obstacle
        for (final other in world.children) {
          if (other is Enemy) {
             double distE = other.position.distanceTo(child.position);
             double radiusE = (other.size.x / 2) + child.radius;
             if (distE < radiusE) {
               Vector2 push = (other.position - child.position).normalized() * (radiusE - distE);
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
        if (player.isDashing && dist < combinedRadius) {
           enemy.takeDamage(2); // Dash deals 2 damage, no knockback
        }

        // Check SLASH Hit
        if (player.isSlashing && dist < (combinedRadius + 60)) {
           enemy.takeDamage(1, knockbackDir: enemy.position - player.position);
        }

        // Check PLAYER DAMAGE Hit
        if (!player.isDashing && dist < combinedRadius) {
          player.takeDamage(10);
        }
      }
    }
  }

  @override
  void onPanStart(DragStartInfo info) {
    if (gameOver) {
       // Reset Game
       gameOver = false;
       killCount = 0;
       wave = 1;
       player.health = 100;
       player.position = Vector2.zero();
       world.children.whereType<Enemy>().forEach((e) => e.removeFromParent());
       world.children.whereType<ParticleSystemComponent>().forEach((e) => e.removeFromParent());
       _spawnWave();
       return;
    }

    final Vector2 startPos = info.eventPosition.widget;
    _dragStartPos = startPos;
    _resetGestureLogic(startPos);
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    final Vector2 currentPos = info.eventPosition.widget;
    final DateTime now = DateTime.now();

    // 1. Calculate Velocity for DASH (Flick detection)
    if (_lastInputTime != null && _lastFingerPosition != null) {
      final double dtSeconds = now.difference(_lastInputTime!).inMicroseconds / 1000000.0;
      if (dtSeconds > 0) {
        final double dist = currentPos.distanceTo(_lastFingerPosition!);
        final double velocity = dist / dtSeconds;

        if (velocity > dashVelocityThreshold) {
          player.dash(currentPos - _lastFingerPosition!);
        }
      }
    }

    // 2. Calculate Angle for SLASH (Circular motion)
    if (!player.isSlashing && _dragStartPos != null) {
      final Vector2 center = _dragStartPos!;
      final Vector2 toFinger = currentPos - center;
      final Vector2 prevToFinger = (_lastFingerPosition ?? currentPos) - center;

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

    // 3. Normal Movement (Virtual Joystick Style)
    if (_dragStartPos != null) {
      final Vector2 offset = currentPos - _dragStartPos!;
      if (offset.length > 10) {
        _handleInput(offset.normalized());
      } else {
        _handleInput(Vector2.zero());
      }
    }

    _lastFingerPosition = currentPos;
    _lastInputTime = now;
  }

  @override
  void onPanEnd(DragEndInfo info) {
    player.moveDirection = null;
    _accumulatedRotation = 0.0;
    _dragStartPos = null;
  }

  void _handleInput(Vector2 dir) {
    player.moveDirection = dir;
  }

  void _resetGestureLogic(Vector2 pos) {
    _lastFingerPosition = pos;
    _lastInputTime = DateTime.now();
    _accumulatedRotation = 0.0;
    _slashWindowTimer = _slashTimeWindow;
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
  static const double _dashSpeedMult = 3.0;

  int health = 100;
  double _damageCooldown = 0.0;

  bool isDashing = false;
  double _dashTimer = 0.0;
  static const double _dashDuration = 0.2;
  Vector2 _dashDirection = Vector2.zero();

  bool isSlashing = false;

  final Paint _cyanPaint = Paint()..color = const Color(0xFF00FFFF);
  final Paint _yellowPaint = Paint()..color = const Color(0xFFFFFF00);

  Player() : super(size: Vector2.all(40));

  @override
  void update(double dt) {
    super.update(dt);

    if (_damageCooldown > 0) {
      _damageCooldown -= dt;
    }

    if (isDashing) {
      _dashTimer -= dt;
      position.add(_dashDirection * (_baseSpeed * _dashSpeedMult) * dt);

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
    if (isDashing) return;

    isDashing = true;
    _dashTimer = _dashDuration;

    if (direction.length > 0) {
      _dashDirection = direction.normalized();
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

  void takeDamage(int amount) {
    if (_damageCooldown > 0 || isDashing) return;

    health -= amount;
    _damageCooldown = 1.0;

    if (health <= 0) {
      health = 0;
      gameRef.gameOver = true;
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

class Enemy extends PositionComponent with HasGameRef<RpgGame> {
  int health = 2;
  static const double _speed = 100.0;
  Vector2? _roamTarget;
  double _roamTimer = 0.0;
  Vector2 _knockbackVelocity = Vector2.zero();
  double _invulnerableTimer = 0.0;

  final Paint _redPaint = Paint()..color = const Color(0xFFFF0000);

  Enemy() : super(size: Vector2.all(40), anchor: Anchor.center);

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
          position.add(dir.normalized() * _speed * dt);
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

    health -= amount;
    if (knockbackDir != null) {
       _knockbackVelocity = knockbackDir.normalized() * 400.0;
    }
    _invulnerableTimer = 0.5;

    if (health <= 0) {
      removeFromParent();
      gameRef.killCount++;
      gameRef.world.add(VisualEffects.createExplosion(position));
      gameRef.cameraComponent.viewfinder.add(
        MoveEffect.by(
          Vector2(5, 5),
          EffectController(duration: 0.1, alternate: true, repeatCount: 3)
        )
      );
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
