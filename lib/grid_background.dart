import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart'; // Changed from main.dart to game.dart

/// Two-layer floor grid:
/// - a far layer with big, dim cells that scrolls slower than the camera
///   (parallax) and lags slightly behind camera velocity, and
/// - a near layer at world scale with subtle perspective (vertical lines fan
///   out toward the bottom of the screen, like a floor seen from above-front).
class GridBackground extends PositionComponent with HasGameRef<RpgGame>, HasVisibility {
  static const double cellSize = 50.0;
  static const double farCellSize = 150.0;
  static const double farParallax = 0.5; // Far layer moves at half camera speed
  static const double velocitySway = 0.04; // Seconds of camera velocity the far layer lags
  static const double maxSway = 16.0; // Pixels
  static const double perspective = 0.08; // Line spread at the screen's bottom edge

  final Paint _gridPaint = Paint()
    ..color = const Color(0xFF333333)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  final Paint _farPaint = Paint()
    ..color = const Color(0xFF1E2233)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  Vector2? _lastCameraPos;
  final Vector2 _smoothedVelocity = Vector2.zero();

  GridBackground() : super(priority: -100); // Render behind everything

  @override
  void update(double dt) {
    super.update(dt);
    final Vector2 cameraPos = gameRef.cameraComponent.viewfinder.position;
    if (_lastCameraPos != null && dt > 0) {
      final Vector2 velocity = (cameraPos - _lastCameraPos!).scaled(1 / dt);
      final double k = (dt * 6).clamp(0.0, 1.0); // Smooth out frame jitter
      _smoothedVelocity.add((velocity - _smoothedVelocity) * k);
    }
    _lastCameraPos = cameraPos.clone();
  }

  @override
  void render(Canvas canvas) {
    if (!isVisible) return;

    // Determine visible area from camera
    final Rect visibleRect = gameRef.cameraComponent.visibleWorldRect;
    final Vector2 cameraPos = gameRef.cameraComponent.viewfinder.position;

    _renderFarLayer(canvas, visibleRect, cameraPos);
    _renderNearLayer(canvas, visibleRect);
  }

  void _renderFarLayer(Canvas canvas, Rect rect, Vector2 cameraPos) {
    // Lines sit at origin + k * farCellSize; moving the origin with the camera
    // makes the layer scroll at (1 - (1 - farParallax)) = farParallax speed.
    final Vector2 sway = _smoothedVelocity * -velocitySway;
    if (sway.length > maxSway) sway.scaleTo(maxSway);
    final Vector2 origin = cameraPos * (1 - farParallax) + sway;

    final double left = rect.left - farCellSize;
    final double right = rect.right + farCellSize;
    final double top = rect.top - farCellSize;
    final double bottom = rect.bottom + farCellSize;

    final double startX = origin.x + ((left - origin.x) / farCellSize).floor() * farCellSize;
    for (double x = startX; x <= right; x += farCellSize) {
      canvas.drawLine(Offset(x, top), Offset(x, bottom), _farPaint);
    }
    final double startY = origin.y + ((top - origin.y) / farCellSize).floor() * farCellSize;
    for (double y = startY; y <= bottom; y += farCellSize) {
      canvas.drawLine(Offset(left, y), Offset(right, y), _farPaint);
    }
  }

  void _renderNearLayer(Canvas canvas, Rect rect) {
    final double cx = rect.center.dx;
    final double cy = rect.center.dy;
    final double halfH = rect.height / 2;
    if (halfH <= 0) return;

    // Horizontal spread at a given screen-relative height
    double spreadAt(double y) => 1 + perspective * ((y - cy) / halfH);

    // Widen the range so fanned-out lines still cover the screen corners
    final double pad = rect.width * perspective + cellSize;
    final double left = ((rect.left - pad) / cellSize).floor() * cellSize;
    final double right = rect.right + pad;
    final double top = (rect.top / cellSize).floor() * cellSize - cellSize;
    final double bottom = rect.bottom + cellSize;

    final double topSpread = spreadAt(top);
    final double bottomSpread = spreadAt(bottom);
    for (double x = left; x <= right; x += cellSize) {
      canvas.drawLine(
        Offset(cx + (x - cx) * topSpread, top),
        Offset(cx + (x - cx) * bottomSpread, bottom),
        _gridPaint,
      );
    }
    for (double y = top; y <= bottom; y += cellSize) {
      final double s = spreadAt(y);
      canvas.drawLine(Offset(cx + (left - cx) * s, y), Offset(cx + (right - cx) * s, y), _gridPaint);
    }
  }
}
