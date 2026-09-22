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

  /// Blurred stroke (or fill) paint for a neon glow layer. Draw it beneath
  /// the crisp shape; the wider stroke gives the blur a bright core to bleed.
  static Paint neonGlowPaint(Color color, {
    required double strokeWidth,
    double sigma = 6.0,
    double opacity = 0.85,
    bool fill = false,
  }) {
    return Paint()
      ..color = color.withOpacity(opacity)
      ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2.5
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
  }

  /// Dust puff kicked up at the feet. [sprayDirection] is where the dust
  /// flies (e.g. the old movement direction when the player reverses).
  static ParticleSystemComponent createDustKick(Vector2 position, Vector2 sprayDirection, {int count = 12}) {
    final Random rng = Random();
    final Vector2 base = sprayDirection.isZero() ? Vector2(1, 0) : sprayDirection.normalized();
    final double baseAngle = atan2(base.y, base.x);
    const double lifespan = 0.45;

    return ParticleSystemComponent(
      position: position.clone(),
      particle: Particle.generate(
        count: count,
        lifespan: lifespan,
        generator: (i) {
          // Fan out +/- ~35 degrees around the spray direction
          final double angle = baseAngle + (rng.nextDouble() - 0.5) * 1.2;
          final double speed = 60 + rng.nextDouble() * 90;
          final Vector2 travel = Vector2(cos(angle), sin(angle)) * (speed * lifespan);
          final double startRadius = 2.0 + rng.nextDouble() * 2.5;
          final double lift = 6 + rng.nextDouble() * 10; // Puffs rise a little
          final Color tint = Color.lerp(
            const Color(0xFFB8A58C), // Tan
            const Color(0xFF9E9E9E), // Grey
            rng.nextDouble(),
          )!;
          final Paint paint = Paint();

          return ComputedParticle(
            renderer: (canvas, particle) {
              final double t = particle.progress;
              final double ease = 1 - (1 - t) * (1 - t); // Fast out, drag to a stop
              paint.color = tint.withOpacity(0.55 * (1 - t));
              canvas.drawCircle(
                Offset(travel.x * ease, travel.y * ease - lift * ease),
                startRadius * (1 + t * 1.5), // Puffs expand as they thin out
                paint,
              );
            },
          );
        },
      ),
    );
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
