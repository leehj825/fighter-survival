import 'dart:math';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame/input.dart';
import 'package:flutter/material.dart' hide Draggable;
import 'package:flame/effects.dart';

import 'grid_background.dart';
import 'hud.dart';
import 'managers.dart';
import 'visual_effects.dart';
import 'sound_service.dart';
// Changed import to the external package
import 'package:stickman_animator/stickman_animator.dart';

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

    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);

    canvas.drawCircle(Offset.zero, baseRadius, _basePaint);
    canvas.drawCircle(Offset.zero, baseRadius, _baseStroke);
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
class RpgGame extends FlameGame with MultiTouchDragDetector {
  final bool resumeGame;
  late Player player;
  late Hud hud;
  late VirtualJoystick joystick;
  late ActionButton slashButton;

  RpgGame({this.resumeGame = false});

  int killCount = 0;
  int wave = 1;
  double _waveTimer = 0.0;
  bool gameOver = false;
  int runGems = 0;

  final Map<int, String> storyLog = {
    1: "SIMULATION INITIALIZED.\nSURVIVE THE SWARM.",
    3: "THREAT LEVEL RISING.\nHOSTILES ADAPTING.",
    5: "WARNING: HEAVY SIGNAL.\nELITE UNIT DETECTED.",
    10: "SYSTEM OVERLOAD.\nTHEY ARE EVERYWHERE.",
  };

  int? _movePointerId;
  int? _actionPointerId;
  Vector2? _moveStartPos;
  Vector2? _lastActionPos;
  DateTime? _lastActionTime;

  static const double dashVelocityThreshold = 1000.0;
  double _shakeTimer = 0.0;
  double _shakeIntensity = 0.0;

  late World world;
  late CameraComponent cameraComponent;

  @override
  Future<void> onLoad() async {
    SoundService.instance.playBackgroundMusic('audio/main2.mp3');

    world = World();

    player = Player()..anchor = Anchor.center;

    if (resumeGame && GameData().hasSavedRun) {
      final data = GameData();
      wave = data.savedWave;
      player.level = data.savedLevel;
      player.xp = data.savedXp;
      player.damageMult = data.savedDamageMult;
      player.xpToNextLevel = (10 * pow(1.5, player.level - 1)).toInt();
    }

    world.add(player);

    if (GameData().levelShield > 0) {
      world.add(OrbitalShield(player));
    }

    world.add(GridBackground());
    _spawnObstacles();

    cameraComponent = CameraComponent(world: world);
    cameraComponent.viewfinder.anchor = Anchor.center;
    cameraComponent.follow(player);
    add(cameraComponent);
    add(world);

    hud = Hud();
    add(hud);

    joystick = VirtualJoystick()..priority = 200;
    hud.add(joystick);

    slashButton = ActionButton(label: "SLASH", color: Colors.redAccent)
      ..priority = 200
      ..position = Vector2(size.x - 100, size.y - 80);
    hud.add(slashButton);

    _spawnWave();
  }

  @override
  void onRemove() {
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
    for (int i = 0; i < 20; i++) {
      bool isBig = rng.nextBool();
      Vector2 pos = Vector2(
        (rng.nextDouble() - 0.5) * 2000,
        (rng.nextDouble() - 0.5) * 2000,
      );
      if (pos.length > 200) {
        world.add(Obstacle(radius: isBig ? 40 : 20, height: isBig ? 60 : 30)..position = pos);
      }
    }

    for (int i = 0; i < 8; i++) {
      Vector2 pos = Vector2(
        (rng.nextDouble() - 0.5) * 1800,
        (rng.nextDouble() - 0.5) * 1800,
      );
      if (pos.length > 200) {
        world.add(Barrel()..position = pos);
      }
    }

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

      bool isShooter = rng.nextDouble() < 0.2 || (isEliteWave && i % 2 == 0);

      if (isShooter) {
        world.add(ShooterEnemy()..position = pos);
      } else {
        world.add(Enemy()..position = pos);
      }
    }

    if (isEliteWave) {
      final modifier = EnemyModifier.values[rng.nextInt(EnemyModifier.values.length)];
      world.add(Enemy(isElite: true, modifier: modifier)..position = player.position + Vector2(600, 0));
      hud.showBossWarning();
    }
  }

  @override
  void update(double dt) {
    if (player.position.x.isNaN || player.position.y.isNaN) {
      player.position = Vector2(0, 0);
    }

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

    bool enemiesAlive = world.children.whereType<Enemy>().isNotEmpty;

    if (!enemiesAlive) {
      _waveTimer += dt;
      if (_waveTimer > 3.0) {
        wave++;
        _spawnWave();
        _waveTimer = 0.0;
      }
    }

    for (final child in world.children) {
      if (child is PositionComponent) {
        child.priority = child.position.y.toInt();
      }
    }

    for (final gem in world.children.whereType<XpGem>()) {
      bool collected = false;
      if (gem.isMagnetized) {
          gem.position.add((player.position - gem.position).safeNormalized() * 800 * dt);
          if (player.position.distanceTo(gem.position) < 20) {
             collected = true;
          }
      } else {
        if (player.position.distanceTo(gem.position) < 100) {
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

    for (final magnet in world.children.whereType<MagnetItem>()) {
        if (player.position.distanceTo(magnet.position) < (player.size.x / 2 + magnet.size.x / 2)) {
            for (final gem in world.children.whereType<XpGem>()) {
                gem.isMagnetized = true;
            }
            magnet.removeFromParent();
        }
    }

    for (final child in world.children) {
      if (child is Obstacle) {
        double distP = player.position.distanceTo(child.position);
        double radiusP = (player.size.x / 2) + child.radius;
        if (distP < radiusP) {
          Vector2 dir = player.position - child.position;
          if (!dir.x.isNaN && !dir.y.isNaN) {
             if (dir.length2 < 0.001) dir = Vector2(1, 0);
             Vector2 push = dir.safeNormalized() * (radiusP - distP);
             if (!push.x.isNaN && !push.y.isNaN) {
                player.position += push;
             }
          }
        }

        for (final other in world.children) {
          if (other is Enemy && other.modifier != EnemyModifier.ghostly) {
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

      if (child is Barrel) {
          double distP = player.position.distanceTo(child.position);
          double radiusP = (player.size.x / 2) + child.radius;
          if (distP < radiusP) {
             child.takeDamage();
          }
      }

      if (child is Enemy) {
        final Enemy enemy = child;
        final double dist = player.position.distanceTo(enemy.position);
        final double combinedRadius = (player.size.x / 2) + (enemy.size.x / 2);

        if (player.isDashing && dist < (combinedRadius + 10)) {
           enemy.takeDamage((20 * player.damageMult).toInt());
        }

        if (player.isSlashing && dist < (combinedRadius + 60)) {
           enemy.takeDamage((10 * player.damageMult).toInt(), knockbackDir: enemy.position - player.position);
        }

        if (!player.isDashing && dist < combinedRadius) {
          player.takeDamage(10);
        }
      }
    }
  }

  @override
  void onDragStart(int pointerId, DragStartInfo info) {
    if (gameOver) {
       return;
    }

    final Vector2 startPos = info.eventPosition.widget;

    if (slashButton.containsPoint(startPos - hud.position)) {
        player.slash();
        return;
    }

    if (_movePointerId == null && startPos.x < size.x / 2) {
      _movePointerId = pointerId;
      _moveStartPos = startPos;

      joystick.position = startPos;
      joystick.isVisible = true;
      joystick.reset();
    }
    else if (_actionPointerId == null) {
      _actionPointerId = pointerId;
      _lastActionPos = startPos;
      _lastActionTime = DateTime.now();

      if (GameData().unlockBlaster) {
         Vector2 screenCenter = size / 2;
         Vector2 dir = (startPos - screenCenter).safeNormalized();
         player.shoot(dir);
      }
    }
  }

  @override
  void onDragUpdate(int pointerId, DragUpdateInfo info) {
    if (gameOver) return;

    final Vector2 currentPos = info.eventPosition.widget;

    if (pointerId == _movePointerId && _moveStartPos != null) {
      final Vector2 offset = currentPos - _moveStartPos!;
      joystick.updateKnob(offset);

      if (offset.length > 5) {
        player.moveDirection = offset.safeNormalized();
      } else {
        player.moveDirection = Vector2.zero();
      }
    }

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
       _spawnObstacles();

       if (GameData().levelShield > 0) {
         world.add(OrbitalShield(player));
       }

       overlays.remove('GameOver');
  }

  void onGameOver() {
    gameOver = true;
    GameData().addGems(runGems);
    GameData().clearRunState();
    overlays.add('GameOver');
  }

  void exitRun() {
    GameData().addGems(runGems);
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

  Obstacle({required this.radius, required this.height}) : super(anchor: Anchor.center, size: Vector2.all(radius * 2));

  @override
  void render(Canvas canvas) {
    final Offset center = (size / 2).toOffset();
    final double r = radius;
    final double h = height;

    canvas.drawOval(
      Rect.fromCenter(center: center, width: width, height: width * 0.6),
      Paint()..color = Colors.black.withOpacity(0.3)
    );

    final Offset topCenter = center + Offset(0, -h);
    final Path bodyPath = Path();
    bodyPath.moveTo(center.dx - r, center.dy);
    bodyPath.lineTo(center.dx + r, center.dy);
    bodyPath.lineTo(topCenter.dx + r, topCenter.dy);
    bodyPath.lineTo(topCenter.dx - r, topCenter.dy);
    bodyPath.close();
    canvas.drawPath(bodyPath, Paint()..color = Colors.grey.shade700);

    canvas.drawCircle(topCenter, r, Paint()..color = Colors.grey.shade400);
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

  late StickmanAnimator _animator;

  Player() : super(size: Vector2.all(60), anchor: Anchor.center);

  @override
  Future<void> onLoad() async {
    super.onLoad();
    final data = GameData();
    maxHealth = 100 + (data.levelHp * 20);
    health = maxHealth;
    dashCooldownMax = 0.8 * pow(0.9, data.levelDash);

    // Initialized from imported library using simplified constructor
    _animator = StickmanAnimator(color: Colors.cyanAccent, scale: 1.2);
  }

  @override
  void update(double dt) {
    super.update(dt);

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
      }
    } else if (moveDirection != null && moveDirection != Vector2.zero()) {
      velocity = moveDirection! * _baseSpeed;
      position.add(velocity * dt);
    }

    // UPDATED: Use the specific named animations from the library
    String anim = "Standard Idle";
    if (isSlashing) {
      anim = "Hurricane Kick";
    } else if (isDashing || velocity.length > 10) {
      anim = "Standard Running";
    }

    _animator.play(anim);
    _animator.update(dt, velocity);
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(center: (size / 2).toOffset() + const Offset(0, 20), width: width, height: width * 0.3),
      Paint()..color = Colors.black.withOpacity(0.3)
    );

    _animator.render(canvas, Vector2(size.x / 2, size.y / 2 + 10), size.y);
  }

  void dash(Vector2 direction) {
    if (isDashing || _currentDashCooldown > 0) return;
    isDashing = true;
    isSlashing = false;
    _dashTimer = _dashDuration;
    _currentDashCooldown = dashCooldownMax;

    if (direction.length > 0) {
      _dashDirection = direction.safeNormalized();
    } else {
      _dashDirection = Vector2(1, 0);
    }
  }

  void slash() {
    if (isSlashing || isDashing) return;
    isSlashing = true;

    // Trigger "Hurricane Kick" animation via update loop (isSlashing = true)

    final hurricane = HurricaneKickEffect();
    hurricane.position = size / 2 + Vector2(0, 10);
    add(hurricane);
  }

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

    for (final child in gameRef.world.children) {
      if (child is Enemy) {
        if (child.position.distanceTo(position) < (child.size.x / 2 + 5)) {
          child.takeDamage((5 * damageMult).toInt());
          removeFromParent();
          break;
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

  late StickmanAnimator _animator;

  Enemy({this.isElite = false, this.modifier = EnemyModifier.none})
      : super(size: Vector2.all(isElite ? 100 : 50), anchor: Anchor.center) {
     if(isElite) health = health * 30;
     _maxHealth = health;
  }

  @override
  Future<void> onLoad() async {
    super.onLoad();
    Color c = Colors.redAccent;
    double s = 1.0;

    if (isElite) {
      c = Colors.deepPurpleAccent;
      s = 2.0;
    } else if (modifier == EnemyModifier.swift) {
      c = Colors.yellowAccent;
    } else if (modifier == EnemyModifier.ghostly) {
      c = Colors.white.withOpacity(0.5);
    }

    _animator = StickmanAnimator(color: c, scale: s);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_invulnerableTimer > 0) _invulnerableTimer -= dt;

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

    // UPDATED: Use named animations
    String anim = "Standard Idle";
    if (velocity.length > 5) {
      anim = "Standard Running";
    }
    // Basic enemies default to Punch if they had an attack phase, but logic only moves them.
    // We keep them as Running/Idle.

    _animator.play(anim);
    _animator.update(dt, velocity);
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
    if (health <= 0 || _invulnerableTimer > 0) return;
    gameRef.world.add(DamageText(amount, position.clone() + Vector2(0, -30)));
    health -= amount;
    if (knockbackDir != null) _knockbackVelocity = knockbackDir.safeNormalized() * 400.0;
    _invulnerableTimer = 0.5;
    if (health <= 0) {
      health = 0;
      removeFromParent();
      gameRef.killCount++;
      gameRef.world.add(XpGem(isElite ? 50 : 10)..position = position);
      SoundService.instance.playExplosion(isLarge: isElite);
      gameRef.world.add(VisualEffects.createExplosion(position));
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(center: (size / 2).toOffset() + const Offset(0, 15), width: width, height: width * 0.3),
      Paint()..color = Colors.black.withOpacity(0.3)
    );

    _animator.render(canvas, Vector2(size.x / 2, size.y / 2 + 5), size.y);

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
  ArrowProjectile(Vector2 pos, Vector2 target) : super(pos, target);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size = Vector2(40, 10);
    angle = atan2(velocity.y, velocity.x);
  }

  @override
  void render(Canvas canvas) {
    final Paint p = Paint()..color = Colors.white ..strokeWidth = 2;
    Offset center = (size / 2).toOffset();
    canvas.drawLine(Offset(0, center.dy), Offset(size.x, center.dy), p);
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
    _animator = StickmanAnimator(color: Colors.purpleAccent, scale: 1.0);
  }

  @override
  void update(double dt) {
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

      double dist = position.distanceTo(gameRef.player.position);
      Vector2 dir = (gameRef.player.position - position).safeNormalized();

      if (dist < 300) {
         velocity = -dir * 80;
      } else if (dist > 500) {
         velocity = dir * 100;
      }

      position.add(velocity * dt);
    }

    _shootTimer += dt;
    String anim = "Standard Running";

    // UPDATED: Use "Shooting Arrow" animation
    if (_shootTimer > 2.0) {
       _shootTimer = 0.0;
       anim = "Shooting Arrow";
       gameRef.world.add(ArrowProjectile(position, gameRef.player.position));
    } else if (velocity.length < 5) {
       anim = "Standard Idle";
    }

    _animator.play(anim);
    _animator.update(dt, velocity);
  }
}

enum EnemyModifier { none, swift, ghostly, regen }

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
    SoundService.instance.playExplosion();

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
    if (gameRef.player.position.distanceTo(position) < 30) {
       gameRef.player.takeDamage(5);
    }
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.grey.shade800);
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
    final double offset = sin(_hoverTime * 3) * 5;
  }

  @override
  void render(Canvas canvas) {
     Paint p = Paint()..color = Colors.red..style = PaintingStyle.stroke..strokeWidth = 6..strokeCap = StrokeCap.round;
     canvas.drawArc(Rect.fromLTWH(5, 5, 20, 20), 0, -pi, false, p);
     Paint tip = Paint()..color = Colors.grey.shade300;
     canvas.drawRect(Rect.fromLTWH(5, 15, 6, 6), tip);
     canvas.drawRect(Rect.fromLTWH(19, 15, 6, 6), tip);
  }
}

class HurricaneKickEffect extends PositionComponent {
  double _lifeTime = 0.0;
  static const double _duration = 0.3;
  final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.0
    ..strokeCap = StrokeCap.round;

  HurricaneKickEffect() : super(anchor: Anchor.center, size: Vector2.all(100));

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
    double progress = _lifeTime / _duration;
    double opacity = (1.0 - progress).clamp(0.0, 1.0);
    _paint.color = Colors.cyanAccent.withOpacity(opacity);

    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.rotate(progress * pi * 4);

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
