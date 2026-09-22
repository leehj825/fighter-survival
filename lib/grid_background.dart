import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart'; // Changed from main.dart to game.dart

/// World-anchored floor grid, drawn behind everything (excluded from the
/// game's y-sorting so its priority stays at the back).
class GridBackground extends PositionComponent with HasGameRef<RpgGame>, HasVisibility {
  static const double cellSize = 50.0;

  final Paint _gridPaint = Paint()
    ..color = const Color(0xFF333333)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;

  GridBackground() : super(priority: -100000); // Render behind everything

  @override
  void render(Canvas canvas) {
    if (!isVisible) return;

    // Determine visible area from camera
    final Rect visibleRect = gameRef.cameraComponent.visibleWorldRect;

    // Expand slightly to avoid flickering at edges
    final double left = (visibleRect.left / cellSize).floor() * cellSize - cellSize;
    final double right = visibleRect.right + cellSize;
    final double top = (visibleRect.top / cellSize).floor() * cellSize - cellSize;
    final double bottom = visibleRect.bottom + cellSize;

    for (double x = left; x <= right; x += cellSize) {
      canvas.drawLine(Offset(x, top), Offset(x, bottom), _gridPaint);
    }
    for (double y = top; y <= bottom; y += cellSize) {
      canvas.drawLine(Offset(left, y), Offset(right, y), _gridPaint);
    }
  }
}
