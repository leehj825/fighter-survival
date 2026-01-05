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

    // --- COLLISION LOGIC ---
    for (final child in world.children) {
      if (child is Enemy) {
        final Enemy enemy = child;
        final double dist = player.position.distanceTo(enemy.position);
        final double combinedRadius = (player.size.x / 2) + (enemy.size.x / 2);

        // 1. Check DASH Hit
        if (player.isDashing && dist < combinedRadius) {
           enemy.takeDamage(enemy.position - player.position);
        }

        // 2. Check SLASH Hit
        if (player.isSlashing && dist < (combinedRadius + 60)) {
           enemy.takeDamage(enemy.position - player.position);
        }

        // 3. Check PLAYER DAMAGE Hit
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
       world.children.whereType<VisualEffects>().forEach((e) => e.removeFromParent()); // Removed VisualEffects just in case
       // Note: VisualEffects are components but checking type might fail if generic.
       // Better to just let them expire or explicit remove.
       _spawnWave();
       return;
    }

    final Vector2 startPos = info.eventPosition.global;
    _dragStartPos = startPos;
    _resetGestureLogic(startPos);
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    final Vector2 currentPos = info.eventPosition.global;
    final DateTime now = DateTime.now();

    // 1. Calculate Velocity for DASH
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

    // 2. Calculate Angle for SLASH
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

    // 3. Normal Movement
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
    if (isDashing) {
      final Path path = Path();
      path.moveTo(width, height / 2);
      path.lineTo(0, 0);
      path.lineTo(0, height);
      path.close();
      canvas.drawPath(path, _yellowPaint);
    } else {
      canvas.drawCircle((size / 2).toOffset(), width / 2, _cyanPaint);
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
    double dx = (rng.nextDouble() - 0.5) * 300;
    double dy = (rng.nextDouble() - 0.5) * 300;
    _roamTarget = position + Vector2(dx, dy);
    _roamTimer = 2.0 + rng.nextDouble() * 2.0;
  }

  void takeDamage(Vector2 knockbackDir) {
    if (_invulnerableTimer > 0) return;

    health--;
    _knockbackVelocity = knockbackDir.normalized() * 400.0;
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
    canvas.drawCircle((size / 2).toOffset(), width / 2, _redPaint);

    if (_invulnerableTimer > 0) {
       final Paint flashPaint = Paint()..color = const Color(0x88FFFFFF);
       canvas.drawCircle((size / 2).toOffset(), width / 2, flashPaint);
    }
  }
}
