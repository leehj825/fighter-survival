import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/particles.dart';
import 'package:flutter/material.dart';

class VisualEffects {
  static final Random _rng = Random();

  static ParticleSystemComponent createExplosion(Vector2 position, {double scale = 1.0}) {
    final Random rng = _rng;
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

}

class _DashTrailComponent extends PositionComponent {
  final double _lifespan = 0.3;
  double _timer = 0.0;
  final Paint _paint = Paint()..color = Colors.yellow.withValues(alpha: 0.5);

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
      _paint.color = Colors.yellow.withValues(alpha: 0.5 * (1 - _timer / _lifespan));
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
