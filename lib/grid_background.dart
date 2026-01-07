import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart'; // Changed from main.dart to game.dart

class GridBackground extends PositionComponent with HasGameRef<RpgGame> {
  final Paint _gridPaint = Paint()
    ..color = const Color(0xFF333333)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  GridBackground() : super(priority: -100); // Render behind everything

  @override
  void render(Canvas canvas) {
    // Determine visible area from camera
    final Rect visibleRect = gameRef.cameraComponent.visibleWorldRect;

    // Expand slightly to avoid flickering at edges
    final double left = (visibleRect.left ~/ 50) * 50.0 - 50;
    final double right = visibleRect.right + 50;
    final double top = (visibleRect.top ~/ 50) * 50.0 - 50;
    final double bottom = visibleRect.bottom + 50;

    // Calculate warp direction (opposite to movement)
    // Scale it to make the effect visible but not overwhelming
    final Vector2 warpDir = (gameRef.player.moveDirection ?? Vector2.zero()) * -30.0;

    // Vertical Lines (Warped)
    for (double x = left; x <= right; x += 50) {
      final Path path = Path();
      path.moveTo(x, top);
      // Control point offset by warpDir
      path.quadraticBezierTo(x + warpDir.x, (top + bottom) / 2 + warpDir.y, x, bottom);
      canvas.drawPath(path, _gridPaint);
    }

    // Horizontal Lines (Warped)
    for (double y = top; y <= bottom; y += 50) {
      final Path path = Path();
      path.moveTo(left, y);
      path.quadraticBezierTo((left + right) / 2 + warpDir.x, y + warpDir.y, right, y);
      canvas.drawPath(path, _gridPaint);
    }
  }
}
