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
  final double glowSigma; // Neon glow blur radius, 0 = off

  AttackType _attackType = AttackType.punch;
  LegacyMotionStrategy? _legacyStrategy;
  final Map<String, StickmanClip> _clips = {};

  // NEW: Track facing angle manually since Controller ignores it during animation
  double _facingAngle = 0.0;

  // Easing applied between consecutive keyframes (replaces hard frame stepping)
  static const Curve frameEase = Curves.easeOutQuad;

  // Clip-level time curves: strikes snap out fast, then recover slowly.
  // Clips not listed play at a constant rate (run/idle cycles, magic, bow).
  static const Map<String, Curve> clipTimeCurves = {
    'Hook': Curves.easeOutCubic,
    'Hook Punch': Curves.easeOutCubic,
    'Punching': Curves.easeOutCubic,
    'Kicking': Curves.easeOutCubic,
    'Side Kick': Curves.easeOutCubic,
    'Round Kick': Curves.easeOutCubic,
    'Roundhouse Kick': Curves.easeOutCubic,
  };

  // Keyframe where each strike reaches full extension (measured from the
  // .sap data: farthest hand/foot). Fires onFrameEvent(clip, 'impact').
  static const Map<String, int> impactFrames = {
    'Hook': 23,
    'Hook Punch': 26,
    'Punching': 17,
    'Kicking': 37,
    'Side Kick': 21,
    'Round Kick': 27,
    'Roundhouse Kick': 29,
  };

  /// Called when playback (base or upper-body layer) crosses a clip's
  /// impact frame. Use it to time sounds/effects to the animation.
  void Function(String clipName, String event)? onFrameEvent;
  double _basePrevSample = -1.0;
  double _upperPrevSample = -1.0;

  // --- Upper-Body Overlay Layer ---
  // Plays a one-shot clip on the torso/arms/head while the base clip
  // (e.g. running) keeps driving the hips and legs.
  static const Set<String> upperBodyBones = {'neck', 'head', 'lElbow', 'lHand', 'rElbow', 'rHand'};
  static const double _upperBlendIn = 0.06; // Seconds
  static const double _upperBlendOut = 0.12; // Seconds
  StickmanClip? _upperClip;
  double _upperFrame = 0.0;
  double _upperSpeed = 1.0;
  final StickmanSkeleton _upperPose = StickmanSkeleton();

  StickmanAnimator({
    this.color = Colors.white,
    this.glowSigma = 0.0,
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
  bool get isPlaying => controller.isPlaying;
  bool get isUpperBodyPlaying => _upperClip != null;
  String? get upperBodyClipName => _upperClip?.name;

  void _parseData(String data) {
    try {
      final json = jsonDecode(data);
      if (json is Map<String, dynamic> && json.containsKey('clips')) {
        final List<dynamic> clipsList = json['clips'];
        for (final clipData in clipsList) {
          var clip = StickmanClip.fromJson(clipData);

          // SPEED HACK: Increase speed of specific animations per user request
          // Updated names to match asset file: "Shooting Arrow"
          if (clip.name == "Hurricane Kick" || clip.name == "Shooting Arrow" || clip.name == "Shoot" || clip.name == "Kicking") {
             double multiplier = (clip.name == "Shooting Arrow") ? 5.0 : 2.0;
             clip = StickmanClip(
                name: clip.name,
                keyframes: clip.keyframes,
                fps: clip.fps * multiplier,
                isLooping: clip.isLooping
             );
          } else if (clip.name == "Hook Punch" || clip.name == "Hook") {
             // Make Hook and Hook Punch animations faster for tap attacks
             clip = StickmanClip(
                name: clip.name,
                keyframes: clip.keyframes,
                fps: clip.fps * 2.5, // 2.5x faster for quick tap attacks
                isLooping: clip.isLooping
             );
          }

          _clips[clip.name] = clip;
          // Alias 'Hook Punch' to 'Kicking' to satisfy usage requirements even if asset is named differently
          if (clip.name == "Hook Punch") {
             _clips["Kicking"] = clip;
          }
        }
      }
    } catch (e) {
      debugPrint('Error parsing animation data: $e');
    }
  }

  void play(String animationName) {
    // Check if clip exists, but also handle case where it might not
    if (_clips.containsKey(animationName)) {
      // Don't interrupt if the same animation is already playing
      if (controller.activeClip?.name == animationName && controller.isPlaying) return;
      
      // Don't interrupt tap attack animations (Hook/Hook Punch) if they're still actively playing
      String? currentClip = controller.activeClip?.name;
      if ((currentClip == "Hook" || currentClip == "Hook Punch") && controller.isPlaying) {
        // Only allow interruption if the new animation is higher priority (dash, slash, shooting, idle, running)
        if (animationName != "Round Kick" && animationName != "Roundhouse Kick" && 
            animationName != "magic" && animationName != "Shooting Arrow" &&
            animationName != "idle" && animationName != "running") {
          return; // Don't interrupt tap attack with movement
        }
      }

      controller.activeClip = _clips[animationName];
      // Start magic animation from frame 50
      controller.currentFrameIndex = (animationName == "magic") ? 50 : 0;
      _basePrevSample = -1.0;
      controller.setMode(EditorMode.animate);
      controller.isPlaying = true;
      debugPrint('Playing animation: $animationName');
    } else {
      // Debug: Log which animation is missing
      debugPrint('Animation "$animationName" not found in clips. Available: ${_clips.keys.toList()}');
    }
  }

  /// Plays [animationName] once on the upper body only, layered over whatever
  /// the base clip is doing with the legs. Restarts if already playing.
  /// [speed] scales playback on top of the clip's own fps.
  void playUpperBody(String animationName, {double speed = 1.0}) {
    final clip = _clips[animationName];
    if (clip == null || clip.frameCount < 2) {
      debugPrint('Upper-body animation "$animationName" not found or too short.');
      return;
    }
    _upperClip = clip;
    _upperFrame = 0.0;
    _upperSpeed = speed;
    _upperPrevSample = -1.0;
  }

  void stopUpperBody() {
    _upperClip = null;
  }

  /// Writes the pose at fractional [frame] of [clip] into [out], easing
  /// between the two surrounding keyframes with [frameEase].
  static void _samplePose(StickmanClip clip, double frame, StickmanSkeleton out, {required bool loop}) {
    final int count = clip.frameCount;
    if (count == 0) return;
    final int i = min(max(frame.floor(), 0), count - 1);
    int next = i + 1;
    if (next >= count) next = loop ? 0 : count - 1;
    final double t = frameEase.transform((frame - i).clamp(0.0, 1.0));

    out.lerp(clip.getFrame(i).pose, 1.0); // Full copy of the current keyframe
    if (next != i && t > 0) {
      out.lerp(clip.getFrame(next).pose, t);
    }
  }

  /// Maps linear playback position [frame] (0..[length]) through the clip's
  /// time curve, if it has one.
  static double _remapFrame(StickmanClip clip, double frame, double length) {
    final curve = clipTimeCurves[clip.name];
    if (curve == null || length <= 0) return frame;
    return curve.transform((frame / length).clamp(0.0, 1.0)) * length;
  }

  /// Fires the impact event if the sampled frame crossed it this update.
  void _checkFrameEvents(StickmanClip clip, double prev, double current) {
    final int? impact = impactFrames[clip.name];
    if (impact == null || onFrameEvent == null || prev < 0) return;
    final bool crossed = current >= prev
        ? (prev < impact && impact <= current)
        : (prev < impact || impact <= current); // Wrapped around (looping)
    if (crossed) onFrameEvent!(clip.name, 'impact');
  }

  /// Base layer playback for Animate mode (mirrors the package's looping
  /// behavior, but with eased interpolation instead of frame stepping).
  void _updateBaseClip(double dt) {
    final clip = controller.activeClip!;
    if (controller.isPlaying && clip.frameCount > 0) {
      controller.currentFrameIndex += dt * clip.fps;
      if (controller.currentFrameIndex >= clip.frameCount) {
        controller.currentFrameIndex %= clip.frameCount; // Loop
      }
    }
    final double sampled = _remapFrame(clip, controller.currentFrameIndex, clip.frameCount.toDouble());
    _checkFrameEvents(clip, _basePrevSample, sampled);
    _basePrevSample = sampled;
    _samplePose(clip, sampled, controller.skeleton, loop: true);
  }

  /// Blends the upper-body overlay onto the already-posed base skeleton.
  void _updateUpperBody(double dt) {
    final clip = _upperClip;
    if (clip == null) return;

    final double framesPerSecond = clip.fps * _upperSpeed;
    _upperFrame += dt * framesPerSecond;
    final double lastFrame = (clip.frameCount - 1).toDouble();
    if (_upperFrame >= lastFrame || framesPerSecond <= 0) {
      _upperClip = null; // One-shot finished; base pose shows through
      return;
    }

    // Layer weight: ease in at the start, ease out toward the end
    final double elapsed = _upperFrame / framesPerSecond;
    final double remaining = (lastFrame - _upperFrame) / framesPerSecond;
    final double rawWeight = min(elapsed / _upperBlendIn, remaining / _upperBlendOut).clamp(0.0, 1.0);
    final double weight = Curves.easeOut.transform(rawWeight);

    final double sampled = _remapFrame(clip, _upperFrame, lastFrame);
    _checkFrameEvents(clip, _upperPrevSample, sampled);
    _upperPrevSample = sampled;
    _samplePose(clip, sampled, _upperPose, loop: false);

    // Keep the torso attached to the base hip (clips may carry root motion)
    final v.Vector3 hipOffset = controller.skeleton.hip - _upperPose.hip;
    final baseNodes = controller.skeleton.nodes;
    final overlayNodes = _upperPose.nodes;

    // Arm lengths to hold after blending (blend of base and overlay lengths),
    // so the position lerp can't visibly shrink the arms mid-transition.
    final skel = controller.skeleton;
    double blendLen(v.Vector3 a, v.Vector3 b, v.Vector3 oa, v.Vector3 ob) =>
        a.distanceTo(b) + (oa.distanceTo(ob) - a.distanceTo(b)) * weight;
    final double lUpper = blendLen(skel.neck, skel.lElbow, _upperPose.neck, _upperPose.lElbow);
    final double lLower = blendLen(skel.lElbow, skel.lHand, _upperPose.lElbow, _upperPose.lHand);
    final double rUpper = blendLen(skel.neck, skel.rElbow, _upperPose.neck, _upperPose.rElbow);
    final double rLower = blendLen(skel.rElbow, skel.rHand, _upperPose.rElbow, _upperPose.rHand);
    for (final id in upperBodyBones) {
      final baseNode = baseNodes[id];
      final overlayNode = overlayNodes[id];
      if (baseNode == null || overlayNode == null) continue;
      final v.Vector3 target = overlayNode.position + hipOffset;
      final v.Vector3 current = baseNode.position;
      current.setValues(
        current.x + (target.x - current.x) * weight,
        current.y + (target.y - current.y) * weight,
        current.z + (target.z - current.z) * weight,
      );
    }

    // Two-bone IK: keep hands where the blend put them, re-solve elbows
    StickmanIK.solveTwoBone(
      root: skel.neck, mid: skel.lElbow, end: skel.lHand,
      target: skel.lHand.clone(), upperLength: lUpper, lowerLength: lLower,
    );
    StickmanIK.solveTwoBone(
      root: skel.neck, mid: skel.rElbow, end: skel.rHand,
      target: skel.rHand.clone(), upperLength: rUpper, lowerLength: rLower,
    );
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
      // Use atan2(-y, x) to fix Up/Down inversion (Up is negative Y in Flame)
      double target = atan2(-velocity.y, velocity.x);

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
        _legacyStrategy?.facingAngle = _facingAngle; // Sync manual angle to legacy strategy
    }

    // 3. Update Controller
    // For Animate mode, we pass 0 velocity because we handle rotation manually.
    // For Legacy mode, we might want procedural running?
    // The provided snippet suggests forcing manual angle calculation.
    // If we pass 0, procedural running weight decays.
    // However, the user explicitly requested: "controller.update(dt, 0, 0);" in previous steps for fixing rotation lock.
    // And "LegacyMotionStrategy" in this file uses "controller.runWeight".
    // If we pass 0, runWeight becomes 0.
    // BUT: "Red Enemy uses procedural punch (attack). But that's stationary".
    // So Legacy movement is likely not critical for running if "Standard Run" clip is used.

    // Animate mode is sampled here (eased interpolation + upper-body layer);
    // pose/legacy mode and ragdoll still go through the controller.
    final bool sampleClips = controller.mode == EditorMode.animate &&
        controller.activeClip != null &&
        controller.state == StickmanState.animating;
    if (sampleClips) {
      _updateBaseClip(dt);
      _updateUpperBody(dt);
    } else {
      controller.update(dt, 0, 0);
    }

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
      glowSigma: glowSigma,
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
  double facingAngle = 0.0; // Synced from StickmanAnimator

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
    // Use the synced facingAngle instead of controller.facingAngle which might be stale
    double renderAngle = facingAngle + (pi / 2);
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
