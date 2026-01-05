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

  // --- Input State (Slingshot) ---
  Vector2? _dragStartPos;
  Vector2? _dragCurrentPos;
  bool _isAiming = false;
  static const double _maxDragDistance = 200.0; // Max power limit

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

    // Sync Aiming state to Player for rendering
    player.isAiming = _isAiming;
    if (_isAiming && _dragStartPos != null && _dragCurrentPos != null) {
      player.aimEnd = player.position + (_dragCurrentPos! - _dragStartPos!);
    } else {
      player.aimEnd = null;
    }

    // --- COLLISION LOGIC ---
    for (final child in world.children) {
      if (child is Enemy) {
        final Enemy enemy = child;
        final double dist = player.position.distanceTo(enemy.position);
        final double combinedRadius = (player.size.x / 2) + (enemy.size.x / 2);

        if (dist < combinedRadius) {
           final double speed = player.velocity.length;

           // High Speed = Attack
           if (speed > 300) {
             enemy.takeDamage(1, knockbackDir: player.velocity);
             // Bounce Player
             final Vector2 normal = (player.position - enemy.position).normalized();
             player.velocity.reflect(normal);
             player.velocity.scale(0.8); // Lose some energy
           }
           // Low Speed = Vulnerable
           else if (speed < 50) {
             player.takeDamage(10);
             // Slight push back
             final Vector2 push = (player.position - enemy.position).normalized() * 100;
             player.velocity = push;
           }
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
       player.velocity = Vector2.zero();
       world.children.whereType<Enemy>().forEach((e) => e.removeFromParent());
       world.children.whereType<ParticleSystemComponent>().forEach((e) => e.removeFromParent());
       _spawnWave();
       return;
    }

    // Slingshot Start: Anchor Point
    // Can only aim if moving slowly
    if (player.velocity.length < 50) {
      _dragStartPos = info.eventPosition.widget;
      _dragCurrentPos = _dragStartPos;
      _isAiming = true;
    }
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    if (_isAiming) {
      _dragCurrentPos = info.eventPosition.widget;
    }
  }

  @override
  void onPanEnd(DragEndInfo info) {
    if (_isAiming && _dragStartPos != null && _dragCurrentPos != null) {
      final Vector2 dragVector = _dragCurrentPos! - _dragStartPos!;

      // Calculate Launch Vector (Opposite to Drag)
      // Clamp power
      if (dragVector.length > 0) {
        final double power = min(dragVector.length, _maxDragDistance);
        final Vector2 dir = -dragVector.normalized(); // Shoot opposite

        // Impulse multiplier
        const double launchMultiplier = 5.0;
        player.velocity = dir * power * launchMultiplier;
      }

      _isAiming = false;
      _dragStartPos = null;
      _dragCurrentPos = null;
    }
  }
}

class Player extends PositionComponent with HasGameRef<RpgGame> {
  Vector2 velocity = Vector2.zero();

  // Stats
  int health = 100;
  double _damageCooldown = 0.0;

  // Visual State
  bool isAiming = false;
  Vector2? aimEnd; // Where the drag is pointing (relative to world or player)

  final Paint _cyanPaint = Paint()..color = const Color(0xFF00FFFF);
  final Paint _aimPaint = Paint()
    ..color = Colors.white.withOpacity(0.5)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  // Bounds for Pinball Physics
  static const double _worldBound = 1000.0;

  Player() : super(size: Vector2.all(40));

  @override
  void update(double dt) {
    super.update(dt);

    if (_damageCooldown > 0) {
      _damageCooldown -= dt;
    }

    // Physics Integration
    position.add(velocity * dt);

    // Friction
    velocity.scale(0.98); // Slow down over time
    if (velocity.length < 10) velocity.setZero();

    // Spawn Trail if fast
    if (velocity.length > 300) {
      // Create trail effect periodically
      // We can use a timer or just chance per frame
      if (dt > 0 && DateTime.now().millisecond % 50 < 20) {
         gameRef.world.add(VisualEffects.createDashTrail(position, angle));
      }
      // Rotate based on velocity
      angle = atan2(velocity.y, velocity.x);
    } else {
      angle = 0;
    }

    // Bounce off World Bounds
    if (position.x < -_worldBound) {
      position.x = -_worldBound;
      velocity.x = -velocity.x;
    } else if (position.x > _worldBound) {
      position.x = _worldBound;
      velocity.x = -velocity.x;
    }

    if (position.y < -_worldBound) {
      position.y = -_worldBound;
      velocity.y = -velocity.y;
    } else if (position.y > _worldBound) {
      position.y = _worldBound;
      velocity.y = -velocity.y;
    }
  }

  @override
  void render(Canvas canvas) {
    // Draw Aiming Line
    if (isAiming && aimEnd != null) {
      // Draw line from center to aimEnd (BUT aimEnd is absolute world pos calculated in game)
      // Actually, in RpgGame we set aimEnd = player.position + dragVector
      // So relative to player (0,0), the end point is (aimEnd - position)

      final Vector2 localEnd = (aimEnd! - position);

      // We want to show launch direction (Opposite to drag)
      // So draw line opposite to localEnd
      // localEnd represents the FINGER drag.
      // Launch will be -localEnd.

      canvas.drawLine(Offset(width/2, height/2), (-(localEnd)).toOffset(), _aimPaint);
    }

    canvas.drawCircle((size / 2).toOffset(), width / 2, _cyanPaint);
  }

  void takeDamage(int amount) {
    if (_damageCooldown > 0) return;

    health -= amount;
    _damageCooldown = 1.0;

    if (health <= 0) {
      health = 0;
      gameRef.gameOver = true;
    }
  }
}

// Enemy class kept mostly the same, removed obsolete Slash/Dash logic references if any
// But actually Enemy logic in Game class handles damage now.
// We just need to ensure Enemy still functions.

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
    Vector2 playerPos = gameRef.player.position;

    double dx = (rng.nextDouble() - 0.5) * 200;
    double dy = (rng.nextDouble() - 0.5) * 200;

    _roamTarget = playerPos + Vector2(dx, dy);
    _roamTimer = 1.0 + rng.nextDouble() * 2.0;
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
    canvas.drawCircle((size / 2).toOffset(), width / 2, _redPaint);

    if (_invulnerableTimer > 0) {
       final Paint flashPaint = Paint()..color = const Color(0x88FFFFFF);
       canvas.drawCircle((size / 2).toOffset(), width / 2, flashPaint);
    }
  }
}
