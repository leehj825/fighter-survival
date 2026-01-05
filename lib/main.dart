import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

void main() {
  runApp(const GameApp());
}

class GameApp extends StatelessWidget {
  const GameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neon RPG Prototype',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;

  // Game World State
  Offset _playerPos = Offset.zero;
  Offset _velocity = Offset.zero;
  double _playerAngle = 0.0; // Orientation for triangle/dash

  // Player Form State
  bool _isDashing = false;
  double _dashTimer = 0.0;

  bool _isSlashing = false;
  double _slashTimer = 0.0;
  double _slashVisualAngle = 0.0; // The rotation of the sword

  // Input State
  bool _isTouching = false;
  Offset _fingerPos = Offset.zero;
  Offset? _gestureStartPos;
  DateTime? _lastTouchTime;
  double _accumulatedRotation = 0.0;
  Offset? _lastTouchPos;

  // Constants
  static const double kPlayerSpeed = 150.0; // pixels per second
  static const double kDashSpeed = 800.0; // pixels per second (approx 3x high speed burst)
  static const double kDashDuration = 0.3; // seconds
  static const double kSlashDuration = 0.2; // seconds
  static const double kFlickVelocityThreshold = 1000.0; // pixels/sec to trigger dash
  static const double kSlashRotationThreshold = 300.0 * (pi / 180.0); // 300 degrees in radians

  Size _screenSize = Size.zero;

  @override
  void initState() {
    super.initState();
    // Initialize player in the center of the screen (we'll set it properly in build or first tick)
    _ticker = createTicker(_gameLoop);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _gameLoop(Duration elapsed) {
    // We need delta time in seconds.
    // Ticker gives elapsed time since start, so we need to track previous frame time.
    _update(elapsed);
  }

  Duration _lastElapsed = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenSize = MediaQuery.of(context).size;
    if (_playerPos == Offset.zero) {
      _playerPos = Offset(_screenSize.width / 2, _screenSize.height / 2);
    }
  }

  void _update(Duration elapsed) {
    final double dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;

    // Prevent huge dt steps (e.g. paused)
    if (dt > 0.1) return;

    setState(() {
      // --- DASH PHYSICS ---
      if (_isDashing) {
        // Move player in direction of velocity
        _playerPos += _velocity * dt;

        // Update timer
        _dashTimer -= dt;
        if (_dashTimer <= 0) {
          _isDashing = false;
          // Slow down velocity to normal speed or zero?
          // "then slows down" - let's just revert to joystick control capability
        }
      }
      // --- JOYSTICK MOVEMENT ---
      else if (_isTouching && !_isSlashing) {
        // Move towards finger
        final Offset toFinger = _fingerPos - _playerPos;
        final double dist = toFinger.distance;

        // Deadzone to prevent jitter
        if (dist > 5.0) {
          final Offset dir = toFinger / dist;
          // Move
          _playerPos += dir * kPlayerSpeed * dt;

          // Smoothly update angle to look at finger (optional, but good for dash prep)
          // But requirement says "Orientation: The Triangle must point in the direction of the dash."
          // So we update orientation when dash triggers.
          // For now, let's keep player angle aligned with movement if we want.
          _playerAngle = atan2(dir.dy, dir.dx);
        }
      }

      // --- SLASH ANIMATION ---
      if (_isSlashing) {
        _slashTimer -= dt;
        // Spin 360 degrees rapidly
        // calculate rotation speed
        double spinSpeed = (2 * pi) / kSlashDuration;
        _slashVisualAngle += spinSpeed * dt;

        if (_slashTimer <= 0) {
          _isSlashing = false;
        }
      }

      // Keep player on screen
      _playerPos = Offset(
        _playerPos.dx.clamp(0, _screenSize.width),
        _playerPos.dy.clamp(0, _screenSize.height),
      );
    });
  }

  // --- GESTURE HANDLING ---

  void _onPointerDown(PointerDownEvent event) {
    _isTouching = true;
    _fingerPos = event.position;
    _gestureStartPos = event.position;
    _lastTouchPos = event.position;
    _lastTouchTime = DateTime.now();
    _accumulatedRotation = 0.0;
  }

  void _onPointerMove(PointerMoveEvent event) {
    final DateTime now = DateTime.now();
    final double dt = now.difference(_lastTouchTime!).inMicroseconds / 1000000.0;

    // Update finger position for Joystick
    _fingerPos = event.position;

    if (dt > 0) {
      final Offset delta = event.localDelta;
      final double distance = delta.distance;
      final double velocity = distance / dt;

      // 1. DASH DETECTION (High Velocity "Wipe")
      // Only trigger if not already dashing or slashing
      if (!_isDashing && !_isSlashing && velocity > kFlickVelocityThreshold) {
        _triggerDash(delta);
      }
    }

    // 2. SLASH DETECTION (Circular Motion)
    // We calculate the angle change relative to the gesture start point
    if (_gestureStartPos != null && !_isSlashing && !_isDashing) {
      final Offset vecPrev = _lastTouchPos! - _gestureStartPos!;
      final Offset vecCurr = event.position - _gestureStartPos!;

      // Avoid noise near the center
      if (vecPrev.distance > 10 && vecCurr.distance > 10) {
        final double anglePrev = atan2(vecPrev.dy, vecPrev.dx);
        final double angleCurr = atan2(vecCurr.dy, vecCurr.dx);

        // Calculate minimal difference in range -pi to pi
        double diff = angleCurr - anglePrev;
        while (diff < -pi) diff += 2 * pi;
        while (diff > pi) diff -= 2 * pi;

        _accumulatedRotation += diff;

        // Check threshold (300 degrees)
        if (_accumulatedRotation.abs() > kSlashRotationThreshold) {
          _triggerSlash();
        }
      }
    }

    _lastTouchPos = event.position;
    _lastTouchTime = now;
  }

  void _onPointerUp(PointerUpEvent event) {
    _isTouching = false;
    _accumulatedRotation = 0.0;
    _gestureStartPos = null;
  }

  void _triggerDash(Offset direction) {
    setState(() {
      _isDashing = true;
      _dashTimer = kDashDuration;
      // Normalize direction and apply speed
      if (direction.distance > 0) {
        _velocity = (direction / direction.distance) * kDashSpeed;
        _playerAngle = atan2(_velocity.dy, _velocity.dx);
      } else {
        // Fallback if delta is zero (unlikely with high velocity)
        _velocity = Offset(kDashSpeed, 0);
        _playerAngle = 0;
      }
    });
  }

  void _triggerSlash() {
    setState(() {
      _isSlashing = true;
      _slashTimer = kSlashDuration;
      _slashVisualAngle = 0.0; // Start spin from 0 (relative to player)
      _accumulatedRotation = 0.0; // Reset
    });
  }

  @override
  Widget build(BuildContext context) {
    // We pass our state to the painter
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      child: CustomPaint(
        painter: GamePainter(
          playerPos: _playerPos,
          playerAngle: _playerAngle,
          isDashing: _isDashing,
          isSlashing: _isSlashing,
          slashAngle: _slashVisualAngle,
        ),
        child: Container(), // Fills the screen
      ),
    );
  }
}

class GamePainter extends CustomPainter {
  final Offset playerPos;
  final double playerAngle;
  final bool isDashing;
  final bool isSlashing;
  final double slashAngle;

  GamePainter({
    required this.playerPos,
    required this.playerAngle,
    required this.isDashing,
    required this.isSlashing,
    required this.slashAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Background (handled by scaffold/theme, but we can ensure black here)
    // canvas.drawColor(Colors.black, BlendMode.src);

    canvas.save();
    canvas.translate(playerPos.dx, playerPos.dy);

    // 2. Draw Player
    if (isDashing) {
      // --- TRIANGLE (Yellow) ---
      // Rotate canvas to match dash direction
      canvas.save();
      canvas.rotate(playerAngle);

      final Paint paint = Paint()
        ..color = Colors.yellowAccent
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 4); // Neon glow effect

      final Path path = Path();
      // Draw a triangle pointing to the right (0 radians), then rotation handles the rest
      // Tip at (20, 0), Back at (-10, -10) and (-10, 10)
      path.moveTo(25, 0);
      path.lineTo(-15, -15);
      path.lineTo(-15, 15);
      path.close();

      canvas.drawPath(path, paint);

      // Add a stroke for high contrast
      final Paint strokePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawPath(path, strokePaint);

      canvas.restore();

    } else {
      // --- CIRCLE (Blue) ---
      final Paint paint = Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 5); // Neon glow

      canvas.drawCircle(Offset.zero, 20.0, paint);

      // White border
      final Paint borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(Offset.zero, 20.0, borderPaint);
    }

    // 3. Draw Slash Stick (if active)
    if (isSlashing) {
      final Paint stickPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2);

      // Rotate the stick around the player center
      canvas.save();
      canvas.rotate(slashAngle);

      // Draw line extending from player radius out
      // Stick length 60
      canvas.drawLine(const Offset(20, 0), const Offset(80, 0), stickPaint);

      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) {
    return oldDelegate.playerPos != playerPos ||
           oldDelegate.playerAngle != playerAngle ||
           oldDelegate.isDashing != isDashing ||
           oldDelegate.isSlashing != isSlashing ||
           oldDelegate.slashAngle != slashAngle;
  }
}
