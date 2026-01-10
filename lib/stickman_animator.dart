import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

enum WeaponType { none, sword, axe, bow }
enum AttackType { punch, kick, bow, sword, axe }

/// A class that procedurally animates a stickman in pseudo-3D
class StickmanAnimator {
  final Color color;
  final double scale;
  final WeaponType weaponType;
  AttackType attackType;

  // Animation State
  double _time = 0.0;
  double _runWeight = 0.0; // 0.0 = Idle, 1.0 = Running

  // 3D Rotation State (Facing Direction)
  double _facingAngle = 0.0;

  // Actions
  bool isAttacking = false;
  double _attackTimer = 0.0;

  // Dash State
  double _dashTimer = 0.0;
  bool _wasDashing = false;

  StickmanAnimator({
    this.color = Colors.white,
    this.scale = 1.0,
    this.weaponType = WeaponType.none,
    this.attackType = AttackType.punch,
  });

  void update(double dt, Vector2 velocity, bool isDashing) {
    _time += dt * 10; // Animation Speed

    // Update Dash Timer
    if (isDashing) {
      if (!_wasDashing) _dashTimer = 0.0; // Reset on start
      _dashTimer += dt;
    } else {
      _dashTimer = 0.0;
    }
    _wasDashing = isDashing;

    // Determine Run Weight based on speed
    double speed = velocity.length;
    double targetWeight = speed > 10 ? 1.0 : 0.0;
    _runWeight += (targetWeight - _runWeight) * dt * 5;

    // Determine Facing Angle
    if (speed > 10) {
      // Adjusted offset to -pi/2 (-90 degrees) to fix Left/Right swap
      // Invert Y velocity to fix Up/Down swap
      double targetAngle = atan2(-velocity.y, velocity.x) - pi / 2;

      double diff = targetAngle - _facingAngle;
      while (diff < -pi) diff += 2 * pi;
      while (diff > pi) diff -= 2 * pi;
      _facingAngle += diff * dt * 10;
    }

    if (isAttacking) {
      _attackTimer += dt;
      if (_attackTimer > 0.3) {
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
    Vector3 hip = Vector3(0, 0, 0);
    Vector3 neck = Vector3(0, -25, 0);

    // Breathing / Bobbing
    double breath = sin(_time * 0.5) * 1.0;
    neck.y += breath * (1 - _runWeight);
    neck.y += sin(_time).abs() * 3.0 * _runWeight; // Fixed abs()

    // Lean Forward Logic (Pitch Spine Forward)
    if (_runWeight > 0.1 || isDashing) {
       double leanAmount = 0.2 * _runWeight; // Reduced Lean forward
       if (isDashing) leanAmount = 0.4; // Lean more when dashing

       // Apply lean to neck
       double ny = neck.y * cos(leanAmount) - neck.z * sin(leanAmount);
       double nz = neck.y * sin(leanAmount) + neck.z * cos(leanAmount);
       neck.y = ny;
       neck.z = nz;
    }

    // Shoulders (Centered at Neck for Triangular shape)
    Vector3 lShoulder = Vector3(0, neck.y, neck.z);
    Vector3 rShoulder = Vector3(0, neck.y, neck.z);

    // Hips (Centered)
    Vector3 lHip = Vector3(0, 0, 0);
    Vector3 rHip = Vector3(0, 0, 0);

    // --- 2. LIMB ANIMATION ---
    double legSwing = sin(_time) * 0.8 * _runWeight;
    double armSwing = cos(_time) * 0.8 * _runWeight;

    if (_wasDashing) {
       legSwing = 1.0; // Legs fly back during dash
       armSwing = 0.0;
    }

    // LEGS (Triangular /\ )
    // Offset X by -3/3 to make them flare out from center
    Vector3 lKnee = _rotateX(Vector3(-3, 12, 0), legSwing) + lHip;
    Vector3 rKnee = _rotateX(Vector3(3, 12, 0), -legSwing) + rHip;
    Vector3 lFoot = _rotateX(Vector3(-3, 12, 0), legSwing + 0.2) + lKnee;
    Vector3 rFoot = _rotateX(Vector3(3, 12, 0), -legSwing + 0.2) + rKnee;

    // ARMS (Triangular \/ )
    double lArmAngle = -armSwing;
    double rArmAngle = armSwing;
    double rElbowBend = 0.0; // Straight by default
    double lElbowBend = 0.0;

    // Default "Guard" pose when not running (arms slightly bent up)
    if (_runWeight < 0.1 && !_wasDashing && !isAttacking) {
       lArmAngle = -0.2;
       rArmAngle = -0.2;
       lElbowBend = -0.5; // Slight bend
       rElbowBend = -0.5;
    }

    // Attack/Weapon Poses
    if (isAttacking) {
        // Default attack pose (will be overridden by Kick/Dash)
        if (attackType != AttackType.kick) rArmAngle = -1.5;
    }

    if (weaponType == WeaponType.bow) {
       lArmAngle = -1.5;
       rArmAngle = -1.5;
    } else if (weaponType != WeaponType.none && !isAttacking) {
       rArmAngle = -0.5;
    }

    // --- DASH ANIMATION LOGIC ---
    if (_wasDashing) {
       // Left arm tucked back
       lArmAngle = 0.8;
       lElbowBend = -1.5;

       // Right Arm Punch Animation Curve
       // 0.0 -> 0.1s: Wind Up (Pull back)
       // 0.1 -> 0.3s: Strike (Punch forward)
       double punchProgress = (_dashTimer / 0.3).clamp(0.0, 1.0);

       if (punchProgress < 0.3) {
          // Wind Up Phase
          rArmAngle = 0.5; // Arm back
          rElbowBend = -2.0; // Cocked elbow
       } else {
          // Strike Phase
          rArmAngle = -1.6; // Point forward
          rElbowBend = 0.0; // FULL STRAIGHT EXTENSION

          // "Small details like slight swing"
          // We add a sine wave vibration to the angle as it extends
          double swing = sin(_dashTimer * 20) * 0.1;
          rArmAngle += swing;
       }
    }

    // Arms with Triangular Start (Offset X by -6/6)
    Vector3 lElbow = _rotateX(Vector3(-6, 10, 0), lArmAngle) + lShoulder;
    Vector3 rElbow = _rotateX(Vector3(6, 10, 0), rArmAngle) + rShoulder;

    // Hands relative to elbows
    Vector3 lHand = _rotateX(Vector3(0, 10, 0), lArmAngle + lElbowBend) + lElbow;
    Vector3 rHand = _rotateX(Vector3(0, 10, 0), rArmAngle + rElbowBend) + rElbow;

    // Attack Animation Extensions
    if (isAttacking && attackType != AttackType.kick) {
       double punchProgress = sin((_attackTimer / 0.3) * pi);
       if (weaponType == WeaponType.none) {
          rHand.z += punchProgress * 15;
          rHand.y -= punchProgress * 5;
       } else {
          rHand.y += punchProgress * 10;
          rHand.z += punchProgress * 10;
       }
    }

    // Dash Punch Extension Logic (Z-Depth)
    if (_wasDashing && _dashTimer > 0.1) {
       rHand.z += 25; // Punch reaches deep into Z space
       // rHand.x = rShoulder.x; // Keeping triangular math for now to avoid centering conflicts
    }

    // -- ROUND KICK LOGIC --
    if (isAttacking && attackType == AttackType.kick) {
       // Override Right Leg: Hold extended position while body spins
       // Extended Side/Forward, Lifted
       // We override the previously calculated knee/foot
       rKnee = rHip + Vector3(20, -10, 10);
       rFoot = rKnee + Vector3(15, 0, 5);
    }

    // --- 3. GLOBAL ROTATION ---
    double renderAngle = _facingAngle;
    if (isAttacking && attackType == AttackType.kick) {
      // Whirlwind Spin: Spin 360 degrees during attack
      double kickProgress = (_attackTimer / 0.3);
      renderAngle += kickProgress * pi * 2;
    }

    List<Vector3> allPoints = [hip, neck, lShoulder, rShoulder, lHip, rHip, lKnee, rKnee, lFoot, rFoot, lElbow, rElbow, lHand, rHand];
    for (var p in allPoints) {
      _applyRotationY(p, renderAngle);
    }

    // --- 4. RENDER TO 2D ---
    Offset toScreen(Vector3 v) => Offset(v.x, v.y + (v.z * 0.3));

    // Draw Spine
    canvas.drawLine(toScreen(hip), toScreen(neck), paint);

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
    Offset headCenter = toScreen(neck + Vector3(0, -8, 0));
    canvas.drawCircle(headCenter, 6, fillPaint);

    // Draw Weapons
    if (weaponType == WeaponType.sword) _drawSword(canvas, toScreen(rHand), renderAngle, isAttacking);
    else if (weaponType == WeaponType.axe) _drawAxe(canvas, toScreen(rHand), renderAngle, isAttacking);
    else if (weaponType == WeaponType.bow) _drawBow(canvas, toScreen(lHand), renderAngle);

    canvas.restore();
  }

  void _drawSword(Canvas canvas, Offset handPos, double facing, bool attacking) {
      double angle = facing;
      if (attacking) angle += pi / 2;
      final Paint p = Paint()..color = Colors.white ..strokeWidth = 2;
      Offset end = handPos + Offset(cos(angle) * 20, sin(angle) * 5 - 20);
      canvas.drawLine(handPos, end, p);
      Offset guardCenter = handPos + Offset(cos(angle) * 5, sin(angle) * 1 - 5);
      canvas.drawLine(guardCenter - Offset(5,0), guardCenter + Offset(5,0), p);
  }

  void _drawAxe(Canvas canvas, Offset handPos, double facing, bool attacking) {
      double angle = facing;
      if (attacking) angle += pi / 2;
      final Paint p = Paint()..color = Colors.grey ..strokeWidth = 3;
      Offset end = handPos + Offset(cos(angle) * 10, -25);
      canvas.drawLine(handPos, end, p);
      canvas.drawCircle(end, 8, Paint()..color = Colors.grey ..style = PaintingStyle.fill);
  }

  void _drawBow(Canvas canvas, Offset handPos, double facing) {
      final Paint p = Paint()..color = Colors.brown ..style = PaintingStyle.stroke ..strokeWidth=2;
      canvas.drawArc(Rect.fromCenter(center: handPos, width: 10, height: 30), facing - pi/2, pi, false, p);
      canvas.drawLine(handPos + Offset(0, -15), handPos + Offset(0, 15), Paint()..color=Colors.white..strokeWidth=1);
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
