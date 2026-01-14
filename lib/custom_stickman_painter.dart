import 'dart:math';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'package:stickman_3d/stickman_3d.dart';

// Axis Mode Enum (Used in Editor too)
enum AxisMode { none, x, y, z }

// Camera View Enum
enum CameraView { front, side, top, free }

/// A modified version of StickmanPainter that does NOT draw a grid.
class CustomStickmanPainter extends CustomPainter {
  final StickmanController controller;
  final Color color;

  // View Parameters
  final CameraView cameraView;
  final double viewRotationX; // Pitch (only used in Free mode)
  final double viewRotationY; // Yaw (only used in Free mode)
  final double viewZoom;
  final Offset viewPan;
  final double cameraHeightOffset;

  // Editor State
  final String? selectedNodeId;
  final AxisMode axisMode;

  CustomStickmanPainter({
    required this.controller,
    this.color = Colors.white,
    this.cameraView = CameraView.free,
    this.viewRotationX = 0.0,
    this.viewRotationY = 0.0,
    this.viewZoom = 1.0,
    this.viewPan = Offset.zero,
    this.cameraHeightOffset = 0.0,
    this.selectedNodeId,
    this.axisMode = AxisMode.none,
  });

  // Public helper so Editor can use exact same projection
  static Offset project(
      v.Vector3 point,
      Size size,
      CameraView view,
      double rotX,
      double rotY,
      double zoom,
      Offset pan,
      double heightOffset)
  {
    double x = 0;
    double y = 0;

    switch (view) {
      case CameraView.front: // Z-Axis: Project (x, y). Ignore z.
        x = point.x;
        y = point.y;
        break;
      case CameraView.side: // X-Axis: Project (z, y). Ignore x.
        x = point.z;
        y = point.y;
        break;
      case CameraView.top: // Y-Axis: Project (x, z). Ignore y.
        x = point.x;
        y = point.z;
        break;
      case CameraView.free: // Perspective/Free: 3D Rotation
        // Rotate Y (Yaw)
        double x1 = point.x * cos(rotY) - point.z * sin(rotY);
        double z1 = point.x * sin(rotY) + point.z * cos(rotY);
        double y1 = point.y;
        // Rotate X (Pitch)
        double y2 = y1 * cos(rotX) - z1 * sin(rotX);
        double z2 = y1 * sin(rotX) + z1 * cos(rotX);
        double x2 = x1;

        x = x2;
        y = y2;
        break;
    }

    // Apply Zoom
    double sx = x * zoom;
    double sy = y * zoom;

    // Apply Camera Height Offset
    sy += heightOffset;

    // Center and Pan
    double cx = size.width / 2;
    double cy = size.height / 2;

    return Offset(cx + pan.dx + sx, cy + pan.dy + sy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final skel = controller.skeleton;

    // Use dynamic visual properties from skeleton
    final strokeWidth = skel.strokeWidth * viewZoom * controller.scale;
    final headRadius = skel.headRadius * viewZoom * controller.scale;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()..color = color ..style = PaintingStyle.fill;

    // Draw Grid -- REMOVED
    // _drawGrid(canvas, size);

    // 3D Projection Helper instance
    Offset toScreen(v.Vector3 vec) => project(
      vec * controller.scale,
      size,
      cameraView,
      viewRotationX,
      viewRotationY,
      viewZoom,
      viewPan,
      cameraHeightOffset
    );

    // Recursive Drawing
    void drawNode(StickmanNode node) {
      final start = toScreen(node.position);

      // Special Draw for Head Node
      if (node.id == 'head') {
        canvas.drawCircle(start, headRadius, fillPaint);
      }

      for (var child in node.children) {
         final end = toScreen(child.position);
         canvas.drawLine(start, end, paint);
         drawNode(child);
      }
    }

    // Draw Bones
    drawNode(skel.root);

    // Legacy Support (if head node missing)
    if (!skel.nodes.containsKey('head') && skel.nodes.containsKey('neck')) {
      Offset headCenter = toScreen(skel.neck + v.Vector3(0, -8, 0));
      canvas.drawCircle(headCenter, headRadius, fillPaint);
    }

    // --- NEW: Draw Face Direction Indicator ---
    if (skel.nodes.containsKey('head')) {
      final headPos = skel.nodes['head']!.position;

      // Calculate a point in front of the head (+Z axis)
      // We make the line length proportional to the head radius so it looks good at any scale
      double indLength = skel.headRadius * 2.5;
      if (indLength < 15.0) indLength = 15.0; // Minimum length

      final frontPos = headPos + v.Vector3(0, 0, indLength);

      final start = toScreen(headPos);
      final end = toScreen(frontPos);

      final indPaint = Paint()
        ..color = Colors.cyanAccent.withOpacity(0.8)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      canvas.drawLine(start, end, indPaint);
      // Draw a small dot at the tip
      canvas.drawCircle(end, 2.0, Paint()..color = Colors.cyanAccent);
    }

    // Draw Axis Constraints
    if (selectedNodeId != null && axisMode != AxisMode.none) {
      final node = skel.nodes[selectedNodeId];
      if (node != null) {
        _drawAxisLine(canvas, size, node.position, axisMode, toScreen);
      }
    }
  }

  void _drawAxisLine(Canvas canvas, Size size, v.Vector3 pos, AxisMode mode, Offset Function(v.Vector3) projectFunc) {
     final p = Paint()
       ..style = PaintingStyle.stroke
       ..strokeWidth = 2.0;

     v.Vector3 axisDir;
     if (mode == AxisMode.x) {
       p.color = Colors.red;
       axisDir = v.Vector3(1, 0, 0);
     } else if (mode == AxisMode.y) {
       p.color = Colors.green;
       axisDir = v.Vector3(0, 1, 0);
     } else { // Z
       p.color = Colors.blue;
       axisDir = v.Vector3(0, 0, 1);
     }

     final length = 1000.0;
     final start3D = pos - axisDir * length;
     final end3D = pos + axisDir * length;

     final start2D = projectFunc(start3D);
     final end2D = projectFunc(end3D);

     _drawDottedLine(canvas, start2D, end2D, p);
  }

  void _drawDottedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const double dashWidth = 5;
    const double dashSpace = 5;
    double distance = (p2 - p1).distance;
    double dx = (p2.dx - p1.dx) / distance;
    double dy = (p2.dy - p1.dy) / distance;

    if (distance == 0) return;

    double currentX = p1.dx;
    double currentY = p1.dy;

    double drawn = 0;
    while (drawn < distance) {
       canvas.drawLine(
         Offset(currentX, currentY),
         Offset(currentX + dx * dashWidth, currentY + dy * dashWidth),
         paint
       );
       currentX += dx * (dashWidth + dashSpace);
       currentY += dy * (dashWidth + dashSpace);
       drawn += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomStickmanPainter oldDelegate) {
    return oldDelegate.cameraView != cameraView ||
           oldDelegate.viewRotationX != viewRotationX ||
           oldDelegate.viewRotationY != viewRotationY ||
           oldDelegate.viewZoom != viewZoom ||
           oldDelegate.viewPan != viewPan ||
           oldDelegate.cameraHeightOffset != cameraHeightOffset ||
           oldDelegate.controller != controller ||
           oldDelegate.selectedNodeId != selectedNodeId ||
           oldDelegate.axisMode != axisMode;
  }
}
