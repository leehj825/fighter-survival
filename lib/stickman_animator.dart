import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

enum AttackType { punch, kick, bow, sword, axe } // Added sword/axe back to support existing Enemy logic if needed, though user provided enum only had punch, kick, bow. Let's check if I need to keep sword/axe.

/// A class that procedurally animates a stickman in pseudo-3D
class StickmanAnimator {
  final Color color;
  final double scale;
  final WeaponType weaponType; // Added to support existing Enemy logic

  // Animation State
  double _time = 0.0;
  double _runWeight = 0.0; // 0.0 = Idle, 1.0 = Running

  // 3D Rotation State (Facing Direction)
  double _facingAngle = 0.0;

  // Actions
  bool isAttacking = false;
  AttackType attackType = AttackType.punch; // Default
  double _attackTimer = 0.0;

  StickmanAnimator({
    this.color = Colors.white,
    this.scale = 1.0,
    this.attackType = AttackType.punch,
    this.weaponType = WeaponType.sword // Default to sword to match existing Enemy constructor
  });

  void update(double dt, Vector2 velocity, bool isDashing) {
    _time += dt * 10; // Animation Speed

    // Determine Run Weight based on speed
    double speed = velocity.length;
    double targetWeight = speed > 10 ? 1.0 : 0.0;
    _runWeight += (targetWeight - _runWeight) * dt * 5;

    // Determine Facing Angle
    if (speed > 10) {
      // FIX: Adjusted offset to pi/2 (90 degrees) to fix Left/Right swap
      // Also ensure we are rotating correctly relative to the "Front" facing model
      double targetAngle = atan2(velocity.y, velocity.x) + pi / 2;

      double diff = targetAngle - _facingAngle;
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

  void render(Canvas canvas, Vector2 position, double height, {bool isDashing = false}) {
    canvas.save();
    canvas.translate(position.x, position.y);
    canvas.scale(scale);

    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final Paint fillPaint = Paint()..color = color..style = PaintingStyle.fill;

    // --- 1. BASE SKELETON (Local Space) ---
    // Model faces "Front" (Z+)
    Vector3 hip = Vector3(0, 0, 0);
    Vector3 neck = Vector3(0, -25, 0);

    // Breathing / Bobbing
    double breath = sin(_time * 0.5) * 1.0;
    neck.y += breath * (1 - _runWeight);
    neck.y += sin(_time).abs() * 3.0 * _runWeight;

    // Lean Forward Logic (Pitch Spine Forward)
    // Rotate neck around X axis relative to hip
    if (_runWeight > 0.1 || isDashing) {
       double leanAmount = 0.4 * _runWeight; // Lean forward
       if (isDashing) leanAmount = 0.8; // Lean more when dashing

       // Apply lean to neck
       double ny = neck.y * cos(leanAmount) - neck.z * sin(leanAmount);
       double nz = neck.y * sin(leanAmount) + neck.z * cos(leanAmount);
       neck.y = ny;
       neck.z = nz;
    }

    // Shoulders & Hips
    Vector3 lShoulder = Vector3(-8, neck.y, neck.z); // Attach to neck position
    Vector3 rShoulder = Vector3(8, neck.y, neck.z);

    Vector3 lHip = Vector3(-4, 0, 0);
    Vector3 rHip = Vector3(4, 0, 0);

    // --- 2. ANIMATE LIMBS ---
    double legSwing = sin(_time) * 0.8 * _runWeight;
    double armSwing = cos(_time) * 0.8 * _runWeight;

    if (isDashing) {
       // Freeze legs in dash pose (One back, one forward)
       legSwing = 0.8;
       armSwing = 0.0;
    }

    // LEGS
    Vector3 lKnee = _rotateX(Vector3(0, 12, 0), legSwing) + lHip;
    Vector3 rKnee = _rotateX(Vector3(0, 12, 0), -legSwing) + rHip;
    Vector3 lFoot = _rotateX(Vector3(0, 12, 0), legSwing + 0.2) + lKnee;
    Vector3 rFoot = _rotateX(Vector3(0, 12, 0), -legSwing + 0.2) + rKnee;

    // ARMS
    double lArmAngle = -armSwing;
    double rArmAngle = armSwing;
    double rElbowBend = -0.3; // Slight natural bend

    // -- DASH PUNCH LOGIC --
    if (isDashing) {
       // Left arm tucked back
       lArmAngle = 0.5;

       // Right arm PUNCH (Forward Z)
       // Quick retraction then punch? Just hold punch pose for dash duration
       rArmAngle = -1.5; // Raise arm
       rElbowBend = 0.0; // Straighten

       // We'll calculate positions and then override the Z depth for the punch
    }
    // -- ROUND KICK LOGIC --
    else if (isAttacking && attackType == AttackType.kick) {
       // Swing Right Leg in a circle
       double kickProgress = (_attackTimer / 0.3); // 0.0 to 1.0
       double kickAngle = sin(kickProgress * pi) * 2.5; // Arc

       // Override Right Leg
       // Rotate around Y axis (Hip) locally
       Vector3 legDir = Vector3(12, 0, 0); // Side kick
       // Rotate this vector based on progress
       double ka = kickProgress * pi * 2; // Full spin illusion? Or just side sweep
       rKnee = rHip + Vector3(cos(ka)*10, 5, sin(ka)*10); // Circular motion
       rFoot = rKnee + Vector3(cos(ka)*12, 5, sin(ka)*12);
    }

    // Calculate Arm Joints
    Vector3 lElbow = _rotateX(Vector3(0, 10, 0), lArmAngle) + lShoulder;
    Vector3 rElbow = _rotateX(Vector3(0, 10, 0), rArmAngle) + rShoulder;

    Vector3 lHand = _rotateX(Vector3(0, 10, 0), lArmAngle - 0.3) + lElbow;
    Vector3 rHand = _rotateX(Vector3(0, 10, 0), rArmAngle + rElbowBend) + rElbow;

    // Apply Dash Punch Extension
    if (isDashing) {
       rHand.z += 20; // Punch FORWARD relative to body
       rHand.x = rShoulder.x; // Center the punch
    }

    // --- 3. GLOBAL ROTATION (Facing) ---
    List<Vector3> allPoints = [hip, neck, lShoulder, rShoulder, lHip, rHip, lKnee, rKnee, lFoot, rFoot, lElbow, rElbow, lHand, rHand];
    for (var p in allPoints) {
      _applyRotationY(p, _facingAngle);
    }

    // --- 4. RENDER ---
    Offset toScreen(Vector3 v) => Offset(v.x, v.y + (v.z * 0.3));

    // Body
    canvas.drawLine(toScreen(hip), toScreen(neck), paint);
    canvas.drawLine(toScreen(neck), toScreen(lShoulder), paint);
    canvas.drawLine(toScreen(neck), toScreen(rShoulder), paint);
    canvas.drawLine(toScreen(hip), toScreen(lHip), paint);
    canvas.drawLine(toScreen(hip), toScreen(rHip), paint);

    // Legs
    canvas.drawLine(toScreen(lHip), toScreen(lKnee), paint);
    canvas.drawLine(toScreen(lKnee), toScreen(lFoot), paint);
    canvas.drawLine(toScreen(rHip), toScreen(rKnee), paint);
    canvas.drawLine(toScreen(rKnee), toScreen(rFoot), paint);

    // Arms
    canvas.drawLine(toScreen(lShoulder), toScreen(lElbow), paint);
    canvas.drawLine(toScreen(lElbow), toScreen(lHand), paint);
    canvas.drawLine(toScreen(rShoulder), toScreen(rElbow), paint);
    canvas.drawLine(toScreen(rElbow), toScreen(rHand), paint);

    // Head
    Offset headCenter = toScreen(neck + Vector3(0, -8, 0));
    canvas.drawCircle(headCenter, 6, fillPaint);

    // Draw Weapon (if not punching/kicking)
    if (weaponType == WeaponType.sword || weaponType == WeaponType.axe) {
        // Simple line attached to rHand
        Vector3 weaponEnd = rHand + Vector3(0, -20, 10);
        // Rotate weapon with hand?
        // For now just draw it
        Offset h = toScreen(rHand);
        Offset w = toScreen(weaponEnd);
        canvas.drawLine(h, w, paint..strokeWidth = 2);
        if (weaponType == WeaponType.axe) {
           canvas.drawCircle(w, 4, paint..style=PaintingStyle.fill);
        }
    } else if (weaponType == WeaponType.bow) {
       // Draw bow
    }

    canvas.restore();
  }

  Vector3 _rotateX(Vector3 v, double angle) {
    double c = cos(angle);
    double s = sin(angle);
    return Vector3(v.x, v.y * c - v.z * s, v.y * s + v.z * c);
  }

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

// Added WeaponType enum to match existing code usage in game.dart
enum WeaponType { sword, axe, bow, none }
