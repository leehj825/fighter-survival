import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

enum WeaponType { none, sword, axe, bow }

/// A class that procedurally animates a stickman in pseudo-3D
class StickmanAnimator {
  final Color color;
  final double scale;
  final WeaponType weaponType;

  // Animation State
  double _time = 0.0;
  double _runWeight = 0.0; // 0.0 = Idle, 1.0 = Running

  // 3D Rotation State (Facing Direction)
  double _facingAngle = 0.0;

  // Actions
  bool isAttacking = false;
  double _attackTimer = 0.0;

  StickmanAnimator({this.color = Colors.white, this.scale = 1.0, this.weaponType = WeaponType.none});

  void update(double dt, Vector2 velocity, bool isDashing) {
    _time += dt * 10; // Animation Speed

    // Determine Run Weight based on speed
    double speed = velocity.length;
    double targetWeight = speed > 10 ? 1.0 : 0.0;
    _runWeight += (targetWeight - _runWeight) * dt * 5; // Smooth transition

    // Determine Facing Angle (in radians) based on velocity
    if (speed > 10) {
      // Calculate target angle (math.atan2 handles full 360)
      double targetAngle = atan2(velocity.y, velocity.x) + pi / 2;

      // Smooth rotation (Lerp angle)
      double diff = targetAngle - _facingAngle;
      // Normalize angle to -pi to pi
      while (diff < -pi) diff += 2 * pi;
      while (diff > pi) diff -= 2 * pi;

      _facingAngle += diff * dt * 10;
    }

    if (isAttacking) {
      _attackTimer += dt;
      if (_attackTimer > 0.3) { // Attack duration
        isAttacking = false;
        _attackTimer = 0.0;
      }
    }
  }

  void render(Canvas canvas, Vector2 position, double height) {
    canvas.save();
    canvas.translate(position.x, position.y);

    // Scale everything
    canvas.scale(scale);

    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final Paint fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // --- 1. CALCULATE 3D BONE POSITIONS (Local Space) ---
    // Y is Up/Down (inverted in screen), Z is Depth (Forward/Back), X is Left/Right

    // Spine
    Vector3 hip = Vector3(0, 0, 0);
    Vector3 neck = Vector3(0, -25, 0);

    // Idle Animation (Breathing)
    double breath = sin(_time * 0.5) * 1.0;
    neck.y += breath * (1 - _runWeight);

    // Run Animation (Bobbing)
    double runBob = abs(sin(_time)) * 3.0;
    neck.y += runBob * _runWeight;

    // Shoulders
    Vector3 lShoulder = Vector3(-8, -25, 0);
    Vector3 rShoulder = Vector3(8, -25, 0);

    // Hips
    Vector3 lHip = Vector3(-4, 0, 0);
    Vector3 rHip = Vector3(4, 0, 0);

    // Limbs Angles
    double legSwing = sin(_time) * 0.8 * _runWeight;
    double armSwing = cos(_time) * 0.8 * _runWeight;

    // Legs (Simple Rotation)
    Vector3 lKnee = _rotateX(Vector3(0, 12, 0), legSwing) + lHip;
    Vector3 rKnee = _rotateX(Vector3(0, 12, 0), -legSwing) + rHip;

    Vector3 lFoot = _rotateX(Vector3(0, 12, 0), legSwing + 0.2 * _runWeight) + lKnee;
    Vector3 rFoot = _rotateX(Vector3(0, 12, 0), -legSwing + 0.2 * _runWeight) + rKnee;

    // Arms
    double lArmAngle = -armSwing;
    double rArmAngle = armSwing;

    // Attack Override (Right arm punches)
    if (isAttacking) {
       rArmAngle = -1.5; // Raise arm
       // Extend forward
    }

    // Weapon Override
    if (weaponType == WeaponType.bow) {
       lArmAngle = -1.5; // Holding bow
       rArmAngle = -1.5; // Drawing string
    } else if (weaponType != WeaponType.none) {
       // Sword/Axe: hold ready
       if (!isAttacking) rArmAngle = -0.5;
    }

    Vector3 lElbow = _rotateX(Vector3(0, 10, 0), lArmAngle) + lShoulder;
    Vector3 rElbow = _rotateX(Vector3(0, 10, 0), rArmAngle) + rShoulder;

    Vector3 lHand = _rotateX(Vector3(0, 10, 0), lArmAngle - 0.3) + lElbow;
    Vector3 rHand = _rotateX(Vector3(0, 10, 0), rArmAngle - 0.3) + rElbow;

    // Attack Extension (Punch/Strike)
    if (isAttacking) {
       double punchProgress = sin((_attackTimer / 0.3) * pi); // 0 -> 1 -> 0
       if (weaponType == WeaponType.none) {
          rHand.z += punchProgress * 15; // Punch forward in Z
          rHand.y -= punchProgress * 5;
       } else {
          // Swing weapon
          // We don't change hand pos much, just the weapon angle usually, but here stickman:
          rHand.y += punchProgress * 10; // Swipe down
          rHand.z += punchProgress * 10;
       }
    }

    // --- 2. APPLY BODY ROTATION (Facing Direction) ---
    // We rotate all points around the Y-axis based on _facingAngle
    List<Vector3> allPoints = [hip, neck, lShoulder, rShoulder, lHip, rHip, lKnee, rKnee, lFoot, rFoot, lElbow, rElbow, lHand, rHand];

    for (var p in allPoints) {
      _applyRotationY(p, _facingAngle);
    }

    // --- 3. PROJECT TO 2D (Render) ---
    // Simple orthographic projection: screenX = x, screenY = y + (z * 0.5) (2.5D look)
    Offset toScreen(Vector3 v) => Offset(v.x, v.y + (v.z * 0.3)); // 0.3 depth factor

    // Draw Body
    canvas.drawLine(toScreen(hip), toScreen(neck), paint); // Spine
    canvas.drawLine(toScreen(neck), toScreen(lShoulder), paint); // Shoulders
    canvas.drawLine(toScreen(neck), toScreen(rShoulder), paint);
    canvas.drawLine(toScreen(hip), toScreen(lHip), paint); // Hips
    canvas.drawLine(toScreen(hip), toScreen(rHip), paint);

    // Draw Legs
    canvas.drawLine(toScreen(lHip), toScreen(lKnee), paint);
    canvas.drawLine(toScreen(lKnee), toScreen(lFoot), paint);
    canvas.drawLine(toScreen(rHip), toScreen(rKnee), paint);
    canvas.drawLine(toScreen(rKnee), toScreen(rFoot), paint);

    // Draw Arms
    canvas.drawLine(toScreen(lShoulder), toScreen(lElbow), paint);
    canvas.drawLine(toScreen(lElbow), toScreen(lHand), paint);
    canvas.drawLine(toScreen(rShoulder), toScreen(rElbow), paint);
    canvas.drawLine(toScreen(rElbow), toScreen(rHand), paint);

    // Draw Head
    Offset headCenter = toScreen(neck + Vector3(0, -8, 0)); // Rotated Neck offset
    // Head doesn't really rotate shape-wise, it's a sphere
    canvas.drawCircle(headCenter, 6, fillPaint);

    // Draw Weapons
    if (weaponType == WeaponType.sword) {
       _drawSword(canvas, toScreen(rHand), _facingAngle, isAttacking);
    } else if (weaponType == WeaponType.axe) {
       _drawAxe(canvas, toScreen(rHand), _facingAngle, isAttacking);
    } else if (weaponType == WeaponType.bow) {
       _drawBow(canvas, toScreen(lHand), _facingAngle);
    }

    canvas.restore();
  }

  void _drawSword(Canvas canvas, Offset handPos, double facing, bool attacking) {
      double angle = facing; // Base rotation
      if (attacking) angle += pi / 2; // Swing

      final Paint p = Paint()..color = Colors.white ..strokeWidth = 2;
      Offset end = handPos + Offset(cos(angle) * 20, sin(angle) * 5 - 20); // Pointy end up/out
      canvas.drawLine(handPos, end, p);
      // Guard
      Offset guardCenter = handPos + Offset(cos(angle) * 5, sin(angle) * 1 - 5);
      canvas.drawLine(guardCenter - Offset(5,0), guardCenter + Offset(5,0), p);
  }

  void _drawAxe(Canvas canvas, Offset handPos, double facing, bool attacking) {
      double angle = facing;
      if (attacking) angle += pi / 2;

      final Paint p = Paint()..color = Colors.grey ..strokeWidth = 3;
      Offset end = handPos + Offset(cos(angle) * 10, -25);
      canvas.drawLine(handPos, end, p);

      // Blade
      final Paint bladeP = Paint()..color = Colors.grey ..style = PaintingStyle.fill;
      canvas.drawCircle(end, 8, bladeP); // Simple round axe head
  }

  void _drawBow(Canvas canvas, Offset handPos, double facing) {
      final Paint p = Paint()..color = Colors.brown ..style = PaintingStyle.stroke ..strokeWidth=2;
      // Bow arc
      Rect rect = Rect.fromCenter(center: handPos, width: 10, height: 30);
      canvas.drawArc(rect, facing - pi/2, pi, false, p);
      // String
      canvas.drawLine(handPos + Offset(0, -15), handPos + Offset(0, 15), Paint()..color=Colors.white..strokeWidth=1);
  }

  // Helper: Rotate vector around X axis (local joint rotation)
  Vector3 _rotateX(Vector3 v, double angle) {
    double c = cos(angle);
    double s = sin(angle);
    return Vector3(v.x, v.y * c - v.z * s, v.y * s + v.z * c);
  }

  // Helper: Apply rotation around Y axis (global body facing)
  void _applyRotationY(Vector3 v, double angle) {
    double c = cos(angle);
    double s = sin(angle);
    double newX = v.x * c + v.z * s;
    double newZ = -v.x * s + v.z * c;
    v.x = newX;
    v.z = newZ;
  }
}

class Vector3 {
  double x, y, z;
  Vector3(this.x, this.y, this.z);
  Vector3 operator +(Vector3 other) => Vector3(x + other.x, y + other.y, z + other.z);
}
