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
    anchor: Anchor.bottomCenter,
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
    storyText.position = Vector2(size.x / 2, size.y - 50);
    bossWarningText.position = size / 2;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final double width = gameRef.size.x - 40;
    const double height = 10;

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
  }

  @override
  void update(double dt) {
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

  void showBossWarning() {
    // Fade In
    bossWarningText.textRenderer = TextPaint(style: (bossWarningText.textRenderer as TextPaint).style.copyWith(color: Colors.redAccent));

    // Flash effect or just show for a few seconds
    Future.delayed(const Duration(seconds: 4), () {
      bossWarningText.textRenderer = TextPaint(style: (bossWarningText.textRenderer as TextPaint).style.copyWith(color: Colors.transparent));
    });
  }
}
