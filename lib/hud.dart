import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class Hud extends PositionComponent with HasGameRef<RpgGame> {
  final TextComponent scoreText = TextComponent(
    text: 'Kills: 0',
    textRenderer: TextPaint(style: const TextStyle(color: Colors.white, fontSize: 20)),
    position: Vector2(20, 20), // Moved up
  );

  // Removed healthText, replaced with bar in render

  final TextComponent storyText = TextComponent(
    text: '',
    anchor: Anchor.topCenter, // Changed from bottomCenter
    textRenderer: TextPaint(
      style: TextStyle(
        color: Colors.yellowAccent,
        fontSize: 24,
        fontWeight: FontWeight.bold,
        backgroundColor: Colors.black.withOpacity(0.5),
      ),
    ),
  );

  final TextComponent bossWarningText = TextComponent(
    text: 'WARNING: GIANT ENEMY APPROACHING',
    anchor: Anchor.center,
    textRenderer: TextPaint(
      style: const TextStyle(
        color: Colors.redAccent,
        fontSize: 32,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  final Paint _barBgPaint = Paint()..color = Colors.grey.withOpacity(0.5);
  final Paint _barFillPaint = Paint()..color = Colors.cyanAccent;
  final Paint _hpBarFillPaint = Paint()..color = Colors.green;
  final Paint _hpBarBgPaint = Paint()..color = Colors.red.withOpacity(0.3);

  // HUD follows this fraction of the camera shake (joysticks stay still)
  static const double shakeFollow = 0.5;
  Vector2 _shake = Vector2.zero();
  static final Vector2 _scoreBasePos = Vector2(20, 20);
  Vector2 _storyBasePos = Vector2.zero();

  Hud() : super(priority: 1000); // Higher priority to ensure on top

  @override
  Future<void> onLoad() async {
    add(scoreText);
    add(storyText);
    add(bossWarningText);
    bossWarningText.textRenderer = TextPaint(style: (bossWarningText.textRenderer as TextPaint).style.copyWith(color: Colors.transparent));
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _storyBasePos = Vector2(size.x / 2, 80); // Moved to top, under bars
    storyText.position = _storyBasePos.clone();
    bossWarningText.position = size / 2;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final double width = gameRef.size.x - 40;
    const double height = 10;

    // Shake the bars with the camera
    canvas.save();
    canvas.translate(_shake.x, _shake.y);

    // XP Bar (Top)
    final int nextLevel = gameRef.player.xpToNextLevel > 0 ? gameRef.player.xpToNextLevel : 1;
    final double xpPct = (gameRef.player.xp / nextLevel).clamp(0.0, 1.0);

    canvas.drawRect(Rect.fromLTWH(20, 10, width, height), _barBgPaint);
    canvas.drawRect(Rect.fromLTWH(20, 10, width * xpPct, height), _barFillPaint);

    // HP Bar (Under Level Text)
    // Level text is at 20, 20 (height ~20-30). So bar at y=50
    final double hpPct = (gameRef.player.health / gameRef.player.maxHealth).clamp(0.0, 1.0);
    canvas.drawRect(Rect.fromLTWH(20, 50, 200, 15), _hpBarBgPaint);
    canvas.drawRect(Rect.fromLTWH(20, 50, 200 * hpPct, 15), _hpBarFillPaint);
    canvas.restore();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _shake = gameRef.shakeOffset * shakeFollow;
    scoreText.position = _scoreBasePos + _shake;
    storyText.position = _storyBasePos + _shake;

    scoreText.text = 'Lv.${gameRef.player.level} | Wave ${gameRef.wave}';
    if (gameRef.gameOver) {
      storyText.text = "SIGNAL LOST. TAP TO RESTART.";
    }
  }

  void showStory(String message) {
    storyText.text = message;
    Future.delayed(const Duration(seconds: 4), () {
      if (storyText.text == message) storyText.text = "";
    });
  }

  /// Animated "LEVEL UP!" popup that scales in with an elastic overshoot.
  void showLevelUp(int level) {
    for (final popup in children.whereType<LevelUpPopup>().toList()) {
      popup.removeFromParent();
    }
    add(LevelUpPopup(level)..position = Vector2(gameRef.size.x / 2, gameRef.size.y * 0.35));
  }

  void showBossWarning() {
    // Fade In
    bossWarningText.textRenderer = TextPaint(style: (bossWarningText.textRenderer as TextPaint).style.copyWith(color: Colors.redAccent));

    // Flash effect or just show for a few seconds
    Future.delayed(const Duration(seconds: 4), () {
      bossWarningText.textRenderer = TextPaint(style: (bossWarningText.textRenderer as TextPaint).style.copyWith(color: Colors.transparent));
    });
  }
}

/// Center-screen level-up banner: elastic scale-in, hold, then float up and
/// fade out.
class LevelUpPopup extends PositionComponent {
  static const double _scaleIn = 0.5;
  static const double _hold = 0.8;
  static const double _fadeOut = 0.4;

  final int level;
  double _time = 0.0;
  late final TextPainter _title;
  late final TextPainter _subtitle;

  LevelUpPopup(this.level) : super(anchor: Anchor.center, priority: 150);

  @override
  Future<void> onLoad() async {
    _title = _layout('LEVEL UP!', 40, Colors.yellowAccent);
    _subtitle = _layout('Lv.$level', 22, Colors.white);
  }

  TextPainter _layout(String text, double fontSize, Color color) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: color.withOpacity(0.8), blurRadius: 12)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    if (_time >= _scaleIn + _hold + _fadeOut) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final double inT = (_time / _scaleIn).clamp(0.0, 1.0);
    final double outT = ((_time - _scaleIn - _hold) / _fadeOut).clamp(0.0, 1.0);
    final double scale = max(0.0, Curves.elasticOut.transform(inT)) * (1 + 0.1 * outT);
    final double opacity = 1.0 - Curves.easeIn.transform(outT);
    if (scale <= 0 || opacity <= 0) return;

    canvas.save();
    canvas.translate(0, -30 * Curves.easeOut.transform(outT)); // Float up while fading
    canvas.scale(scale);
    canvas.saveLayer(null, Paint()..color = Colors.white.withOpacity(opacity));
    _title.paint(canvas, Offset(-_title.width / 2, -_title.height));
    _subtitle.paint(canvas, Offset(-_subtitle.width / 2, 4));
    canvas.restore();
    canvas.restore();
  }
}
