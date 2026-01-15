import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart'; // Changed from main.dart to game.dart

class GridBackground extends PositionComponent with HasGameRef<RpgGame>, HasVisibility {
  final Paint _gridPaint = Paint()
    ..color = const Color(0xFF333333)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  GridBackground() : super(priority: -100); // Render behind everything

  @override
  void render(Canvas canvas) {
    if (!isVisible) return;

    // Determine visible area from camera
    final Rect visibleRect = gameRef.cameraComponent.visibleWorldRect;

    // Expand slightly to avoid flickering at edges
    final double left = (visibleRect.left ~/ 50) * 50.0 - 50;
    final double right = visibleRect.right + 50;
    final double top = (visibleRect.top ~/ 50) * 50.0 - 50;
    final double bottom = visibleRect.bottom + 50;

    for (double x = left; x <= right; x += 50) {
      canvas.drawLine(Offset(x, top), Offset(x, bottom), _gridPaint);
    }
    for (double y = top; y <= bottom; y += 50) {
      canvas.drawLine(Offset(left, y), Offset(right, y), _gridPaint);
    }
  }
}
