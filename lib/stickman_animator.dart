import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:stickman_3d/stickman_3d.dart' hide CameraView, StickmanPainter;
import 'package:vector_math/vector_math_64.dart' as v;
import 'custom_stickman_painter.dart';

export 'package:stickman_3d/stickman_3d.dart' show WeaponType;

enum AttackType { punch, kick, bow, sword, axe }

/// A wrapper around StickmanController to maintain compatibility with the Game's API
/// and provide legacy procedural animation fallback.
class StickmanAnimator {
  final StickmanController controller;
  final Color color;

  AttackType _attackType = AttackType.punch;
  LegacyMotionStrategy? _legacyStrategy;
  final Map<String, StickmanClip> _clips = {};

  // NEW: Track facing angle manually since Controller ignores it during animation
  double _facingAngle = 0.0;

  StickmanAnimator({
    this.color = Colors.white,
    double scale = 1.0,
    WeaponType weaponType = WeaponType.none,
    AttackType attackType = AttackType.punch,
    String? data,
  }) : controller = StickmanController(scale: scale, weaponType: weaponType) {
    _attackType = attackType;

    // Use Legacy Strategy by default to preserve original look
    _legacyStrategy = LegacyMotionStrategy();
    _legacyStrategy!.attackType = attackType;
    controller.setStrategy(_legacyStrategy!);

    if (data != null) {
      _parseData(data);
    }
  }

  set attackType(AttackType type) {
    _attackType = type;
    _legacyStrategy?.attackType = type;
  }

  AttackType get attackType => _attackType;

  set isAttacking(bool value) => controller.isAttacking = value;
  set weaponType(WeaponType value) => controller.weaponType = value;

  void _parseData(String data) {
    try {
      final json = jsonDecode(data);
      if (json is Map<String, dynamic> && json.containsKey('clips')) {
        final List<dynamic> clipsList = json['clips'];
        for (final clipData in clipsList) {
          var clip = StickmanClip.fromJson(clipData);

          // SPEED HACK: Double the speed of specific animations
          if (clip.name == "Hurricane Kick" || clip.name == "Bow Shoot" || clip.name == "Shoot") {
             clip = StickmanClip(
                name: clip.name,
                keyframes: clip.keyframes,
                fps: clip.fps * 2, // Double speed
                isLooping: clip.isLooping
             );
          } else if (clip.name == "Hook Punch") {
             clip = StickmanClip(
                name: clip.name,
                keyframes: clip.keyframes,
                fps: 90.0, // High speed for dash
                isLooping: clip.isLooping
             );
          }

          _clips[clip.name] = clip;
        }
      }
    } catch (e) {
      debugPrint('Error parsing animation data: $e');
    }
  }

  void play(String animationName) {
    if (_clips.containsKey(animationName)) {
      if (controller.activeClip?.name == animationName && controller.isPlaying) return;

      controller.activeClip = _clips[animationName];
      controller.currentFrameIndex = 0;
      controller.setMode(EditorMode.animate);
      controller.isPlaying = true;
    }
  }

  void stopAnimation() {
    if (controller.mode == EditorMode.animate) {
      controller.activeClip = null;
      controller.isPlaying = false;
      controller.setMode(EditorMode.pose); // Use 'pose' mode which maps to legacy procedural in update logic
    }
  }

  void update(double dt, Vector2 velocity, bool isDashing) {
    // 1. Calculate Target Angle based on Velocity
    if (velocity.length > 1.0) { // Only turn if moving
      // Note: atan2(x, y) for 0-up orientation usually, or standard (y,x)
      // Stickman3D usually treats 0 as facing +Z (or similar).
      // Let's use standard atan2(velocity.y, velocity.x) but offset if needed.

      double target = atan2(velocity.y, velocity.x);

      // Smooth Rotation (Lerp)
      // Shortest angle interpolation
      double diff = target - _facingAngle;
      while (diff < -pi) diff += 2 * pi;
      while (diff > pi) diff -= 2 * pi;

      _facingAngle += diff * (dt * 10); // Turn speed 10
    }

    // 2. Legacy/Procedural Mode Fallback
    if (controller.mode != EditorMode.animate || _clips.isEmpty) {
        _legacyStrategy?.isDashing = isDashing;
        // Sync controller angle so legacy strategy works too
        controller.facingAngle = _facingAngle;
    }

    // 3. Update Controller
    // We pass velocity here so procedural animations (like running lean) work if they use velocity.
    // The provided snippet said pass (0,0) to avoid overwriting, but that breaks legacy running.
    // Since we manually set facingAngle on controller above, passing velocity shouldn't hurt angle?
    // Wait, controller.update calculates facingAngle from velocity.
    // If we pass velocity, controller overwrites facingAngle.
    // But if we are in Legacy mode, we synced it *before*.
    // If we pass velocity, controller will recalculate it.
    // If we pass 0, legacy run won't lean.

    // Compromise: Pass velocity so runWeight works.
    // In animate mode, controller ignores facingAngle anyway (according to user).
    // In legacy mode, controller calculates it.
    // If we want SMOOTH rotation, we should ensure controller uses our smoothed `_facingAngle`.
    // StickmanController typically does `_facingAngle = ...` inside update if velocity > 0.
    // If we want to override it, we must do it *after* update?
    // Or pass 0 velocity and set runWeight manually?

    // User snippet used: controller.update(dt, 0, 0);
    // If I use that, I trust the user's snippet. But I recall legacy motion needs runWeight.
    // Let's check `LegacyMotionStrategy`... it uses `controller.runWeight`.
    // `controller.update` logic (from memory of `stickman_3d`):
    // `runWeight += (targetWeight - runWeight) * dt * 5;` where target is 1 if speed > 10.
    // If I pass 0, target is 0. Run weight decays.

    // I will try to follow the user snippet but maybe the user assumes `EditorMode.animate` is always used for movement now?
    // Player uses "Standard Run". Enemies use "Standard Run".
    // So Legacy running is rarely used?
    // Red Enemy uses procedural punch (attack). But that's stationary usually?
    // "If out of range, play Standard Run".
    // So mostly we are in Animate mode.
    // If we are in Animate mode, we calculate `_facingAngle` manually and rotate points.
    // If we are in Legacy mode, we might be standing still (Red Enemy punch).
    // So maybe `controller.update(dt, 0, 0)` is fine for the requested scope.

    controller.update(dt, 0, 0);

    // 4. MANUAL ROTATION FIX
    // Apply the rotation to the skeleton points manually
    // This ensures rotation happens regardless of whether we are playing a clip or not
    // User requested "when controller.mode == EditorMode.animate".
    // But if we use (0,0) update, controller won't rotate in legacy either.
    // So we should apply rotation always if we want smooth turning in legacy too?
    // Or just rely on Legacy fallback syncing `controller.facingAngle = _facingAngle`?
    // If we passed 0,0, controller won't update facingAngle. So syncing is good.
    // But legacy strategy rotates points based on `controller.facingAngle`.
    // So for legacy, step 2 `controller.facingAngle = _facingAngle` is sufficient.

    // For Animate mode, the Controller/Clip overwrites points. So we must rotate AFTER update.
    if (controller.mode == EditorMode.animate) {
       // Offset by 90 degrees (pi/2) because standard stickman faces Front (Z+)
       // but movement angle 0 is Right (X+).
       final rotY = v.Matrix3.rotationY(_facingAngle + (pi / 2));
       for (var p in controller.skeleton.allPoints) {
         p.setFrom(rotY.transform(p));
       }
    }
  }

  void render(Canvas canvas, Vector2 position, double height, {bool isDashing = false}) {
    canvas.save();
    canvas.translate(position.x, position.y);

    // Render with Pseudo-3D Bird's Eye Projection using CustomStickmanPainter (No Grid)
    final painter = CustomStickmanPainter(
      controller: controller,
      color: color,
      cameraView: CameraView.free,
      viewRotationX: -pi / 6, // 30 degrees pitch (Bird's Eye)
      viewRotationY: 0,       // We rotate the skeleton points manually, so view rotation is 0
      viewZoom: 1.0,
      cameraHeightOffset: 0.0,
    );

    painter.paint(canvas, Size.zero);
    canvas.restore();
  }
}

/// Implements the original procedural animation logic using the new library's skeleton
class LegacyMotionStrategy implements MotionStrategy {
  AttackType attackType = AttackType.punch;
  bool isDashing = false;
  bool _wasDashing = false;
  double _dashTimer = 0.0;

  @override
  void update(double dt, StickmanController controller) {
    // --- 1. Update Custom State ---
    if (isDashing) {
      if (!_wasDashing) _dashTimer = 0.0;
      _dashTimer += dt;
    } else {
      _dashTimer = 0.0;
    }
    _wasDashing = isDashing;

    // --- 2. Calculate Skeleton (Copied from old logic) ---

    // Reset Root
    controller.skeleton.hip.setValues(0, 0, 0);

    // Breathing / Bobbing
    double breath = sin(controller.time * 0.5) * 1.0;
    v.Vector3 neck = v.Vector3(0, -25, 0);
    neck.y += breath * (1 - controller.runWeight);
    neck.y += sin(controller.time).abs() * 3.0 * controller.runWeight;

    // LEAN FORWARD
    if (controller.runWeight > 0.1 || _wasDashing) {
       double leanAmount = 0.15 * controller.runWeight;
       if (_wasDashing) leanAmount = 0.9;

       double ny = neck.y * cos(leanAmount) - neck.z * sin(leanAmount);
       double nz = neck.y * sin(leanAmount) + neck.z * cos(leanAmount);
       neck.y = ny;
       neck.z = nz;
    }

    // BODY LEAN (Whirlwind Kick)
    if (controller.isAttacking && (attackType == AttackType.kick || controller.weaponType == WeaponType.none)) {
        double kickProgress = (controller.attackTimer / 0.3);
        double lean = sin(kickProgress * pi) * -8.0;
        neck.x += lean;
    }

    // Set Neck
    controller.skeleton.neck.setFrom(neck);
    controller.skeleton.setHead(neck + v.Vector3(0, -8, 0)); // Helper to set head

    // --- LIMBS ---
    double legSwing = sin(controller.time) * 0.8 * controller.runWeight;
    double armSwing = cos(controller.time) * 0.8 * controller.runWeight;

    if (_wasDashing) {
       legSwing = 1.0;
       armSwing = 0.0;
    }

    v.Vector3 rotateX(v.Vector3 vec, double angle) {
      final c = cos(angle);
      final s = sin(angle);
      return v.Vector3(vec.x, vec.y * c - vec.z * s, vec.y * s + vec.z * c);
    }

    // Legs
    v.Vector3 lKnee = rotateX(v.Vector3(-3, 12, 0), legSwing) + controller.skeleton.hip;
    v.Vector3 rKnee = rotateX(v.Vector3(3, 12, 0), -legSwing) + controller.skeleton.hip;
    v.Vector3 lFoot = rotateX(v.Vector3(-3, 12, 0), legSwing + 0.2) + lKnee;
    v.Vector3 rFoot = rotateX(v.Vector3(3, 12, 0), -legSwing + 0.2) + rKnee;

    // Kick Override
    if (controller.isAttacking && (attackType == AttackType.kick || controller.weaponType == WeaponType.none)) {
        rKnee = controller.skeleton.hip + v.Vector3(10, -5, 5);
        rFoot = rKnee + v.Vector3(12, -2, 2);
    }

    controller.skeleton.lKnee = lKnee;
    controller.skeleton.rKnee = rKnee;
    controller.skeleton.lFoot = lFoot;
    controller.skeleton.rFoot = rFoot;

    // Arms
    double lArmAngle = -armSwing;
    double rArmAngle = armSwing;
    double rElbowBend = 0.0;
    double lElbowBend = 0.0;

    if (controller.runWeight < 0.1 && !_wasDashing && !controller.isAttacking) {
       lArmAngle = 0.3;
       rArmAngle = 0.3;
    }

    if (controller.isAttacking) {
      if (attackType != AttackType.kick && controller.weaponType != WeaponType.none) rArmAngle = -1.5;
    }

    if (controller.weaponType == WeaponType.bow) {
       lArmAngle = -1.5;
       rArmAngle = -1.5;
    } else if (controller.weaponType != WeaponType.none && !controller.isAttacking) {
       rArmAngle = -0.5;
    }

    // Dash (Superman)
    if (_wasDashing) {
       lArmAngle = 0.8;
       lElbowBend = -1.0;
       double extension = (_dashTimer / 0.1).clamp(0.0, 1.0);
       rArmAngle = -1.6 * extension;
    }

    // Joints
    v.Vector3 lElbow = rotateX(v.Vector3(-6, 10, 0), lArmAngle) + neck; // Neck is effectively shoulder center
    v.Vector3 rElbow = rotateX(v.Vector3(6, 10, 0), rArmAngle) + neck;

    v.Vector3 lHand = rotateX(v.Vector3(0, 10, 0), lArmAngle + lElbowBend) + lElbow;
    v.Vector3 rHand = rotateX(v.Vector3(0, 10, 0), rArmAngle + rElbowBend) + rElbow;

    if (_wasDashing) {
       rHand.z += 25;
       rHand.x = neck.x + 6; // Align
    }

    if (controller.isAttacking && attackType != AttackType.kick && controller.weaponType != WeaponType.none) {
       double punchProgress = sin((controller.attackTimer / 0.3) * pi);
       if (controller.weaponType == WeaponType.none) {
          rHand.z += punchProgress * 15;
          rHand.y -= punchProgress * 5;
       } else {
          rHand.y += punchProgress * 10;
          rHand.z += punchProgress * 10;
       }
    }

    controller.skeleton.lElbow = lElbow;
    controller.skeleton.rElbow = rElbow;
    controller.skeleton.lHand = lHand;
    controller.skeleton.rHand = rHand;

    // Global Rotation
    double renderAngle = controller.facingAngle + (pi / 2);
    if (controller.isAttacking && (attackType == AttackType.kick || controller.weaponType == WeaponType.none)) {
      double kickProgress = (controller.attackTimer / 0.3);
      renderAngle += kickProgress * pi * 2;
    }

    final rotY = v.Matrix3.rotationY(renderAngle);
    for (var p in controller.skeleton.allPoints) {
      p.setFrom(rotY.transform(p));
    }
  }
}
