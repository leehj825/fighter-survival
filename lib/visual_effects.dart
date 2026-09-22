import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flame/particles.dart';
import 'package:flutter/material.dart';

class VisualEffects {
  static ParticleSystemComponent createExplosion(Vector2 position, {double scale = 1.0}) {
    final Random rng = Random();
    return ParticleSystemComponent(
      particle: Particle.generate(
        count: (20 * scale).toInt(),
        lifespan: 0.5 * scale,
        generator: (i) => AcceleratedParticle(
          position: position.clone(),
          speed: Vector2(
            (rng.nextDouble() - 0.5) * 200 * scale,
            (rng.nextDouble() - 0.5) * 200 * scale,
          ),
          child: CircleParticle(
            radius: 2.0 * scale,
            paint: Paint()..color = Colors.redAccent,
          ),
        ),
      ),
    );
  }

  static PositionComponent createDashTrail(Vector2 position, double angle) {
    // Simple fading triangle trail
    return _DashTrailComponent(position, angle);
  }

  static PositionComponent createShockwave(Vector2 position) {
    return _ShockwaveComponent(position);
  }
}

class _ShockwaveComponent extends PositionComponent {
  final double _lifespan = 0.5;
  double _timer = 0.0;
  final Paint _paint = Paint()
    ..color = Colors.cyanAccent
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.0;

  _ShockwaveComponent(Vector2 pos) {
    position = pos;
    size = Vector2.all(300); // Max radius approx 150
    anchor = Anchor.center;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _timer += dt;
    if (_timer >= _lifespan) {
      removeFromParent();
    } else {
      double opacity = (1.0 - (_timer / _lifespan)).clamp(0.0, 1.0);
      _paint.color = Colors.cyanAccent.withOpacity(opacity);
    }
  }

  @override
  void render(Canvas canvas) {
    double progress = _timer / _lifespan;
    double currentRadius = (size.x / 2) * progress;
    canvas.drawCircle(Offset(size.x / 2, size.y / 2), currentRadius, _paint);
  }
}

class _DashTrailComponent extends PositionComponent {
  final double _lifespan = 0.3;
  double _timer = 0.0;
  final Paint _paint = Paint()..color = Colors.yellow.withOpacity(0.5);

  _DashTrailComponent(Vector2 pos, double angle) {
    position = pos;
    this.angle = angle;
    size = Vector2.all(40);
    anchor = Anchor.center;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _timer += dt;
    if (_timer >= _lifespan) {
      removeFromParent();
    } else {
      // Fade out
      _paint.color = Colors.yellow.withOpacity(0.5 * (1 - _timer / _lifespan));
    }
  }

  @override
  void render(Canvas canvas) {
    final Path path = Path();
    path.moveTo(width, height / 2);
    path.lineTo(0, 0);
    path.lineTo(0, height);
    path.close();
    canvas.drawPath(path, _paint);
  }
}

/// Hit-stop: briefly freezes gameplay updates to sell the weight of an impact.
/// The game loop calls [tick] every frame and skips its world update while it
/// returns true.
class HitStop {
  static const double defaultDuration = 0.06; // 60ms
  // Minimum unfrozen time between freezes, so rapid-fire hits can't
  // stutter-lock the game.
  static const double retriggerCooldown = 0.1;

  double _remaining = 0.0;
  double _cooldown = 0.0;

  bool get isActive => _remaining > 0;

  /// Starts (or extends) a freeze. Overlapping hits in the same frame don't
  /// stack; the longest requested freeze wins.
  void trigger([double duration = defaultDuration]) {
    if (_remaining <= 0 && _cooldown > 0) return;
    _remaining = max(_remaining, duration);
  }

  /// Advances the freeze timer by real time. Returns true if this frame
  /// should be frozen.
  bool tick(double dt) {
    if (_remaining > 0) {
      _remaining -= dt;
      if (_remaining <= 0) _cooldown = retriggerCooldown;
      return true;
    }
    if (_cooldown > 0) _cooldown -= dt;
    return false;
  }
}

/// Trauma-based camera shake. Impacts add trauma (0..1), which decays
/// linearly over time; the shake magnitude is trauma squared, so big hits
/// punch hard and then settle smoothly instead of cutting off abruptly.
class CameraShake {
  final double maxOffset; // Pixels at full trauma
  final double decayPerSecond;
  final Random _rng = Random();

  double _trauma = 0.0;

  CameraShake({this.maxOffset = 24.0, this.decayPerSecond = 1.6});

  double get trauma => _trauma;

  void addTrauma(double amount) {
    _trauma = (_trauma + amount).clamp(0.0, 1.0);
  }

  /// Decays trauma and returns this frame's camera offset in pixels.
  Vector2 update(double dt) {
    if (_trauma <= 0) return Vector2.zero();
    _trauma = max(0.0, _trauma - decayPerSecond * dt);
    final double magnitude = maxOffset * _trauma * _trauma;
    return Vector2(
      (_rng.nextDouble() * 2 - 1) * magnitude,
      (_rng.nextDouble() * 2 - 1) * magnitude,
    );
  }
}
