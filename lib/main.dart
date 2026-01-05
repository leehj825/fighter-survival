import 'dart:math';
import 'dart:ui'; // For Canvas, Paint, Path, etc.

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart' hide Draggable; // Hide Draggable to avoid conflict with Flame if needed, mainly for Colors.

void main() {
  runApp(GameWidget(game: RpgGame()));
}

/// The main Game class.
/// Mixes in [PanDetector] to handle single-finger touch inputs.
class RpgGame extends FlameGame with PanDetector {
  late Player player;

  // --- Input State ---
  Vector2? _lastFingerPosition;
  DateTime? _lastInputTime;

  // Slash Detection State
  double _accumulatedRotation = 0.0;
  Vector2? _gestureStartVector; // Vector from player to finger at start of gesture analysis window
  double _slashWindowTimer = 0.0;
  static const double _slashTimeWindow = 0.5; // Seconds to complete the circle
  static const double _slashThreshold = 300.0 * (pi / 180.0); // 300 degrees in radians

  // Tweakable Variable for Dash Sensitivity
  // Higher value = requires faster flick to dash.
  // This represents pixels per second.
  static const double dashVelocityThreshold = 2500.0;

  @override
  Future<void> onLoad() async {
    // Initialize Player in the center
    player = Player()
      ..position = size / 2
      ..anchor = Anchor.center;

    add(player);
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Slash Window Timer logic
    // We decay the accumulated rotation or reset it if user stops rotating fast enough?
    // Or simple window: Reset accumulation if no input for a bit, or just decay it.
    // The prompt says: "If the total absolute rotation exceeds 300 degrees within a short window (0.5s)"
    // This implies a sliding window or a reset. Simple approach:
    // If we haven't slashed, and time passes, we might want to reset the accumulation if input stops.
    // But strict window logic: We just accumulate. If timer exceeds 0.5, we reset accumulation.
    // We will handle the timer reset in onPanMove when we detect activity.

    if (_slashWindowTimer > 0) {
      _slashWindowTimer -= dt;
      if (_slashWindowTimer <= 0) {
        _accumulatedRotation = 0.0;
      }
    }
  }

  @override
  void onPanStart(DragStartInfo info) {
    // Only reset logic on start. Movement is handled in onPanUpdate via drag delta.
    _resetGestureLogic(info.eventPosition.global);
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    final Vector2 currentPos = info.eventPosition.global;
    final DateTime now = DateTime.now();

    // 1. Calculate Velocity for DASH
    if (_lastInputTime != null && _lastFingerPosition != null) {
      final double dtSeconds = now.difference(_lastInputTime!).inMicroseconds / 1000000.0;
      if (dtSeconds > 0) {
        final double dist = currentPos.distanceTo(_lastFingerPosition!);
        final double velocity = dist / dtSeconds;

        if (velocity > dashVelocityThreshold) {
          player.dash(currentPos - _lastFingerPosition!);
        }
      }
    }

    // 2. Calculate Angle for SLASH
    // We track the angle of the vector (Player -> Finger)
    // Actually, usually circular gestures are around a center.
    // The prompt says: "Track the angle between the player and the finger."
    if (!player.isSlashing) { // Only detect if not already slashing
      final Vector2 toFinger = currentPos - player.position;
      final Vector2 prevToFinger = (_lastFingerPosition ?? currentPos) - player.position;

      if (toFinger.length > 10 && prevToFinger.length > 10) { // Deadzone
        final double currentAngle = atan2(toFinger.y, toFinger.x);
        final double prevAngle = atan2(prevToFinger.y, prevToFinger.x);

        double diff = currentAngle - prevAngle;
        // Normalize to -pi to pi
        while (diff < -pi) diff += 2 * pi;
        while (diff > pi) diff -= 2 * pi;

        _accumulatedRotation += diff;
        _slashWindowTimer = _slashTimeWindow; // Keep window open while interacting

        if (_accumulatedRotation.abs() > _slashThreshold) {
          player.slash();
          _accumulatedRotation = 0.0;
        }
      }
    }

    // 3. Normal Movement (Virtual Joystick / Drag Direction)
    // Move in the direction of the drag delta, not to absolute position
    if (_lastFingerPosition != null) {
      final Vector2 delta = currentPos - _lastFingerPosition!;
      if (delta.length > 0) {
        _handleInput(delta.normalized());
      }
    }

    _lastFingerPosition = currentPos;
    _lastInputTime = now;
  }

  @override
  void onPanEnd(DragEndInfo info) {
    player.moveDirection = null; // Stop moving
    _accumulatedRotation = 0.0;
  }

  void _handleInput(Vector2 dir) {
    player.moveDirection = dir;
  }

  void _resetGestureLogic(Vector2 pos) {
    _lastFingerPosition = pos;
    _lastInputTime = DateTime.now();
    _accumulatedRotation = 0.0;
    _slashWindowTimer = _slashTimeWindow;
  }
}

class Player extends PositionComponent {
  // Movement
  Vector2? moveDirection;
  static const double _baseSpeed = 200.0;
  static const double _dashSpeedMult = 3.0;

  // Dash State
  bool isDashing = false;
  double _dashTimer = 0.0;
  static const double _dashDuration = 0.2; // 200ms
  Vector2 _dashDirection = Vector2.zero();

  // Slash State
  bool isSlashing = false; // Just a flag, the SwordEffect handles the visual

  // Visuals
  final Paint _cyanPaint = Paint()..color = const Color(0xFF00FFFF);
  final Paint _yellowPaint = Paint()..color = const Color(0xFFFFFF00);

  Player() : super(size: Vector2.all(40));

  @override
  void update(double dt) {
    super.update(dt);

    // --- DASH LOGIC ---
    if (isDashing) {
      _dashTimer -= dt;
      // Move constantly in dash direction
      position.add(_dashDirection * (_baseSpeed * _dashSpeedMult) * dt);

      if (_dashTimer <= 0) {
        isDashing = false;
        // Reset angle to 0 or keep it?
        // We usually want the player to return to normal orientation behavior.
        angle = 0;
      }
    }
    // --- NORMAL MOVEMENT ---
    else if (moveDirection != null) {
      // Move in the specific direction at constant speed
      position.add(moveDirection! * _baseSpeed * dt);
    }
  }

  @override
  void render(Canvas canvas) {
    // --- INSERT SPRITE LOADING HERE ---
    // In the future, replace the canvas drawing code below with:
    // animation?.getSprite().render(canvas, size: size);

    if (isDashing) {
      // --- Draw Yellow Triangle ---
      // Triangle points to the right (0 radians) by default, standard Flame orientation
      // We rely on component.angle to rotate it.

      final Path path = Path();
      // Tip at (width, height/2)
      path.moveTo(width, height / 2);
      // Top Back
      path.lineTo(0, 0);
      // Bottom Back
      path.lineTo(0, height);
      path.close();

      canvas.drawPath(path, _yellowPaint);
    } else {
      // --- Draw Cyan Circle ---
      // Draw centered in the component (0,0 is top left of component)
      // Radius = width / 2
      canvas.drawCircle((size / 2).toOffset(), width / 2, _cyanPaint);
    }
  }

  void dash(Vector2 direction) {
    if (isDashing) return;

    isDashing = true;
    _dashTimer = _dashDuration;

    if (direction.length > 0) {
      _dashDirection = direction.normalized();
      // Rotate player to face dash direction
      angle = atan2(_dashDirection.y, _dashDirection.x);
    } else {
      _dashDirection = Vector2(1, 0);
      angle = 0;
    }
  }

  void slash() {
    if (isSlashing) return;

    // Trigger slash action
    // Add SwordEffect child
    final sword = SwordEffect();
    // Center the sword on the player
    sword.position = size / 2;
    add(sword);
  }
}

class SwordEffect extends PositionComponent {
  double _lifeTime = 0.0;
  static const double _duration = 0.2; // Fast slash

  final Paint _whitePaint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.0;

  SwordEffect() : super(anchor: Anchor.centerLeft); // Anchor at 'handle'

  @override
  void onLoad() {
    // Sword length
    size = Vector2(60, 10);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _lifeTime += dt;

    // Spin 360 degrees (2pi) over duration
    angle += (2 * pi / _duration) * dt;

    if (_lifeTime >= _duration) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    // Draw the "Stick" / Sword
    // Line from (0,0) [handle] to (width, 0) [tip] relative to component
    // Offset slightly so it doesn't overlap player center exactly if desired

    // Draw a white line
    canvas.drawLine(const Offset(20, 0), Offset(width + 20, 0), _whitePaint);
  }
}
