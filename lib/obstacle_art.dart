import 'dart:math';
import 'package:flutter/material.dart';

/// Procedural 2.5D art for world obstacles (rocks, tech pillars, barrels,
/// spike traps). Geometry and paints are built once; render calls only draw.
///
/// All art is drawn in the owning component's local space, with the ground
/// contact point at [center]. "Height" extrudes upward (negative y), and
/// ground-plane depth is squashed by [_squash] to match the bird's-eye view.
const double _squash = 0.55;

// Light comes from the upper-left of the screen (ground-plane direction).
final Offset _lightDir = const Offset(-0.8, -0.6);

Color _shade(Color dark, Color light, double normalAngle) {
  final double dot = cos(normalAngle) * _lightDir.dx + sin(normalAngle) * _lightDir.dy;
  return Color.lerp(dark, light, ((dot + 1) / 2).clamp(0.0, 1.0))!;
}

class _Face {
  final Path path;
  final Paint paint;
  _Face(this.path, this.paint);
}

/// Extruded polygon ("prism") shared by rocks and pillars.
class _Prism {
  final List<_Face> sideFaces = [];
  final Path top = Path();
  final List<Offset> topPoints = [];
  final List<Offset> frontBandPoints = []; // Front-facing ring at band height

  _Prism({
    required Offset center,
    required List<double> angles,
    required List<double> radii,
    required double height,
    required Color dark,
    required Color light,
    double bandHeight = 0.5,
    double topScale = 1.0, // < 1 tapers the prism toward the top
  }) {
    final int n = angles.length;
    Offset ground(int i, double lift) {
      final double r = radii[i] * (1 - (1 - topScale) * (lift / height));
      return Offset(
        center.dx + cos(angles[i]) * r,
        center.dy + sin(angles[i]) * r * _squash - lift,
      );
    }

    for (int i = 0; i < n; i++) {
      topPoints.add(ground(i, height));
    }
    top.addPolygon(topPoints, true);

    // Side faces facing the viewer (outward normal points down-screen),
    // drawn back to front
    final faces = <MapEntry<double, _Face>>[];
    for (int i = 0; i < n; i++) {
      final int j = (i + 1) % n;
      double mid = (angles[i] + angles[j]) / 2;
      if (angles[j] < angles[i]) mid += pi; // Wrapped edge
      if (sin(mid) <= 0) continue; // Back face, hidden under the top
      final Path face = Path()
        ..moveTo(ground(i, 0).dx, ground(i, 0).dy)
        ..lineTo(ground(j, 0).dx, ground(j, 0).dy)
        ..lineTo(ground(j, height).dx, ground(j, height).dy)
        ..lineTo(ground(i, height).dx, ground(i, height).dy)
        ..close();
      faces.add(MapEntry(sin(mid), _Face(face, Paint()..color = _shade(dark, light, mid))));
    }
    faces.sort((a, b) => a.key.compareTo(b.key));
    sideFaces.addAll(faces.map((e) => e.value));

    // Band ring across the visible side (sorted left to right)
    final front = <int>[for (int i = 0; i < n; i++) if (sin(angles[i]) >= -0.05) i]
      ..sort((a, b) => ground(a, 0).dx.compareTo(ground(b, 0).dx));
    for (final i in front) {
      frontBandPoints.add(ground(i, height * bandHeight));
    }
  }

  void drawBody(Canvas canvas) {
    for (final face in sideFaces) {
      canvas.drawPath(face.path, face.paint);
    }
  }
}

/// Jagged boulder with shaded facets, a lit top and a couple of cracks.
class RockArt {
  late final _Prism _prism;
  final Paint _topPaint;
  final Paint _edgePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..color = Colors.white.withOpacity(0.18);
  final Paint _crackPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..strokeCap = StrokeCap.round
    ..color = Colors.black.withOpacity(0.35);
  final Path _cracks = Path();
  final Paint _shadowPaint = Paint()..color = Colors.black.withOpacity(0.35);
  final Rect _shadowRect;

  RockArt({required Offset center, required double radius, required double height, required Random rng})
      : _topPaint = Paint()..color = Color.lerp(const Color(0xFF7D8699), const Color(0xFF8E8676), rng.nextDouble())!,
        _shadowRect = Rect.fromCenter(center: center + Offset(radius * 0.25, radius * 0.1), width: radius * 2.4, height: radius * 1.3) {
    final int n = 7 + rng.nextInt(3);
    final angles = <double>[];
    final radii = <double>[];
    for (int i = 0; i < n; i++) {
      angles.add((i + rng.nextDouble() * 0.5) / n * 2 * pi);
      radii.add(radius * (0.8 + rng.nextDouble() * 0.2));
    }
    // Squat, tapered boulders; height varies a little per rock
    final double h = height * (0.45 + rng.nextDouble() * 0.25);
    _prism = _Prism(
      center: center,
      angles: angles,
      radii: radii,
      height: h,
      dark: const Color(0xFF262A33),
      light: const Color(0xFF626B7D),
      topScale: 0.6 + rng.nextDouble() * 0.15,
    );

    // Cracks: short jagged lines from a random top vertex toward the middle
    final Offset topCenter = center - Offset(0, h);
    for (int c = 0; c < 2; c++) {
      final Offset start = _prism.topPoints[rng.nextInt(n)];
      final Offset toMid = topCenter - start;
      _cracks.moveTo(start.dx, start.dy);
      final Offset kink = start + toMid * 0.35 + Offset(rng.nextDouble() * 6 - 3, rng.nextDouble() * 4 - 2);
      _cracks.lineTo(kink.dx, kink.dy);
      final Offset end = start + toMid * (0.55 + rng.nextDouble() * 0.2);
      _cracks.lineTo(end.dx, end.dy);
    }
  }

  void render(Canvas canvas) {
    canvas.drawOval(_shadowRect, _shadowPaint);
    _prism.drawBody(canvas);
    canvas.drawPath(_prism.top, _topPaint);
    canvas.drawPath(_cracks, _crackPaint);
    canvas.drawPath(_prism.top, _edgePaint);
  }
}

/// Hexagonal sci-fi pillar with a pulsing neon band and a glowing top core.
class PillarArt {
  late final _Prism _prism;
  final Color glow;
  final Paint _topPaint = Paint()..color = const Color(0xFF465170);
  final Paint _rimPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.white.withOpacity(0.25);
  final Paint _bandGlow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  final Paint _bandLine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round;
  final Paint _coreGlow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
  final Paint _corePaint = Paint();
  final Paint _shadowPaint = Paint()..color = Colors.black.withOpacity(0.35);
  final Rect _shadowRect;
  final Path _band = Path();
  final Rect _coreRect;

  PillarArt({required Offset center, required double radius, required double height, required this.glow})
      : _shadowRect = Rect.fromCenter(center: center + Offset(radius * 0.25, radius * 0.1), width: radius * 2.4, height: radius * 1.3),
        _coreRect = Rect.fromCenter(center: center - Offset(0, height), width: radius * 0.7, height: radius * 0.7 * _squash) {
    final double r = radius * 0.85;
    _prism = _Prism(
      center: center,
      angles: [for (int i = 0; i < 6; i++) i / 6 * 2 * pi + pi / 6],
      radii: List.filled(6, r),
      height: height,
      dark: const Color(0xFF161B26),
      light: const Color(0xFF3A4560),
      bandHeight: 0.62,
    );
    _band.addPolygon(_prism.frontBandPoints, false);
  }

  /// [pulse] in 0..1 drives the glow intensity.
  void render(Canvas canvas, double pulse) {
    canvas.drawOval(_shadowRect, _shadowPaint);
    _prism.drawBody(canvas);

    _bandGlow.color = glow.withOpacity(0.35 + 0.35 * pulse);
    _bandLine.color = Color.lerp(glow, Colors.white, 0.3)!;
    canvas.drawPath(_band, _bandGlow);
    canvas.drawPath(_band, _bandLine);

    canvas.drawPath(_prism.top, _topPaint);
    canvas.drawPath(_prism.top, _rimPaint);
    _coreGlow.color = glow.withOpacity(0.4 + 0.4 * pulse);
    canvas.drawOval(_coreRect.inflate(3), _coreGlow);
    _corePaint.color = Color.lerp(glow, Colors.white, 0.5)!;
    canvas.drawOval(_coreRect.deflate(_coreRect.width * 0.25), _corePaint);
  }
}

/// Explosive barrel: shaded steel drum, hoops, lid, hazard label and an
/// orange warning glow. [damage01] (0 = intact, 1 = about to blow) heats the
/// color; [flash] (0..1) is a white hit flash.
class BarrelArt {
  final Offset _base; // Ground contact center
  final double _rx;
  final double _ry;
  final double _h;
  late final Rect _top = Rect.fromCenter(center: _base - Offset(0, _h), width: _rx * 2, height: _ry * 2);
  late final Rect _bottom = Rect.fromCenter(center: _base, width: _rx * 2, height: _ry * 2);
  late final Rect _side = Rect.fromLTRB(_base.dx - _rx, _base.dy - _h, _base.dx + _rx, _base.dy);
  final Path _body = Path();
  final Path _label = Path();
  final Paint _shadowPaint = Paint()..color = Colors.black.withOpacity(0.35);
  final Paint _glowPaint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
  final Paint _bodyPaint = Paint();
  final Paint _hoopPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5
    ..color = const Color(0xFF3A2A20);
  final Paint _topPaint = Paint();
  final Paint _lidPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.black.withOpacity(0.35);
  final Paint _labelPaint = Paint()..color = const Color(0xFFFFD54F);
  final Paint _markPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round
    ..color = Colors.black87;
  final Paint _flashPaint = Paint();

  BarrelArt(Size size)
      : _base = Offset(size.width / 2, size.height * 0.82),
        _rx = size.width * 0.36,
        _ry = size.width * 0.36 * _squash * 0.6,
        _h = size.height * 0.6 {
    _body
      ..addRect(_side)
      ..addOval(_bottom);
    // Hazard label: small diamond on the front
    final Offset c = _base - Offset(0, _h * 0.5);
    final double s = _rx * 0.45;
    _label
      ..moveTo(c.dx, c.dy - s)
      ..lineTo(c.dx + s, c.dy)
      ..lineTo(c.dx, c.dy + s)
      ..lineTo(c.dx - s, c.dy)
      ..close();
  }

  void render(Canvas canvas, {double damage01 = 0.0, double flash = 0.0, double pulse = 0.0}) {
    final Color hot = Color.lerp(const Color(0xFFB2472C), const Color(0xFFE53935), damage01)!;

    // Ground shadow and warning glow
    canvas.drawOval(_bottom.inflate(4).shift(const Offset(4, 2)), _shadowPaint);
    _glowPaint.color = Colors.deepOrangeAccent.withOpacity(0.15 + 0.2 * pulse + 0.25 * damage01);
    canvas.drawOval(_bottom.inflate(10), _glowPaint);

    // Drum with cylindrical shading (dark edges, lit left-center)
    _bodyPaint.shader = LinearGradient(
      colors: [
        Color.lerp(hot, Colors.black, 0.55)!,
        Color.lerp(hot, Colors.white, 0.25)!,
        hot,
        Color.lerp(hot, Colors.black, 0.6)!,
      ],
      stops: const [0.0, 0.3, 0.55, 1.0],
    ).createShader(_side);
    canvas.drawPath(_body, _bodyPaint);

    // Hoops follow the front curve of the drum
    for (final double t in const [0.2, 0.8]) {
      final Rect hoop = _bottom.shift(Offset(0, -_h * t));
      canvas.drawArc(hoop, 0, pi, false, _hoopPaint);
    }

    // Hazard label
    canvas.drawPath(_label, _labelPaint);
    final Offset c = _base - Offset(0, _h * 0.5);
    canvas.drawLine(c - Offset(0, _rx * 0.22), c + Offset(0, _rx * 0.06), _markPaint);
    canvas.drawCircle(c + Offset(0, _rx * 0.2), 1.2, _markPaint);

    // Lid
    _topPaint.color = Color.lerp(hot, Colors.white, 0.15)!;
    canvas.drawOval(_top, _topPaint);
    canvas.drawOval(_top.deflate(3), _lidPaint);
    canvas.drawCircle(_top.center + Offset(_rx * 0.4, 0), 2, _lidPaint); // Bung cap

    if (flash > 0) {
      _flashPaint.color = Colors.white.withOpacity(0.7 * flash);
      canvas.drawPath(_body, _flashPaint);
      canvas.drawOval(_top, _flashPaint);
    }
  }
}

/// Floor spike trap: bevelled steel plate, 3x3 shaded cone spikes and a
/// pulsing red warning outline.
class SpikeTrapArt {
  final Size size;
  late final RRect _plate = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(5));
  final Paint _platePaint = Paint();
  final Paint _bevelLight = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.white.withOpacity(0.15);
  final Paint _warnGlow = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
  final Paint _warnLine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final Paint _holePaint = Paint()..color = Colors.black.withOpacity(0.5);
  final Paint _spikeLight = Paint()..color = const Color(0xFFCFD8DC);
  final Paint _spikeDark = Paint()..color = const Color(0xFF78909C);
  final Paint _tipPaint = Paint()..color = const Color(0xFFFF5252);
  final List<Offset> _spikeBases = [];

  SpikeTrapArt(this.size) {
    _platePaint.shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF4A4F57), Color(0xFF23262B)],
    ).createShader(Offset.zero & size);
    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        _spikeBases.add(Offset(size.width * (0.22 + col * 0.28), size.height * (0.3 + row * 0.26)));
      }
    }
  }

  void render(Canvas canvas, double pulse) {
    canvas.drawRRect(_plate, _platePaint);
    canvas.drawRRect(_plate.deflate(1), _bevelLight);

    _warnGlow.color = Colors.redAccent.withOpacity(0.25 + 0.45 * pulse);
    _warnLine.color = Colors.redAccent.withOpacity(0.5 + 0.4 * pulse);
    canvas.drawRRect(_plate, _warnGlow);
    canvas.drawRRect(_plate.deflate(2), _warnLine);

    // Spikes back row first; each is a cone split into lit/shadow halves
    const double w = 4.5;
    const double h = 11;
    for (final Offset b in _spikeBases) {
      canvas.drawOval(Rect.fromCenter(center: b, width: w * 2.2, height: w), _holePaint);
      final Offset tip = b - const Offset(0, h);
      canvas.drawPath(
        Path()
          ..moveTo(b.dx - w, b.dy)
          ..lineTo(b.dx, b.dy + 1)
          ..lineTo(tip.dx, tip.dy)
          ..close(),
        _spikeLight,
      );
      canvas.drawPath(
        Path()
          ..moveTo(b.dx, b.dy + 1)
          ..lineTo(b.dx + w, b.dy)
          ..lineTo(tip.dx, tip.dy)
          ..close(),
        _spikeDark,
      );
      canvas.drawCircle(tip + const Offset(0, 1.5), 1.2, _tipPaint);
    }
  }
}
