import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class Hud extends PositionComponent with HasGameRef<RpgGame> {
  final TextComponent scoreText = TextComponent(
    text: 'Kills: 0',
    textRenderer: TextPaint(style: const TextStyle(color: Colors.white, fontSize: 20)),
    position: Vector2(20, 40),
  );

  final TextComponent healthText = TextComponent(
    text: 'HP: 100',
    textRenderer: TextPaint(style: const TextStyle(color: Colors.green, fontSize: 20)),
    position: Vector2(20, 70),
  );

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

  final Paint _barBgPaint = Paint()..color = Colors.grey.withOpacity(0.5);
  final Paint _barFillPaint = Paint()..color = Colors.cyanAccent;

  Hud() : super(priority: 100);

  @override
  Future<void> onLoad() async {
    add(scoreText);
    add(healthText);
    add(storyText);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    storyText.position = Vector2(size.x / 2, size.y - 50);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final double width = gameRef.size.x - 40;
    const double height = 10;
    // Prevent division by zero if game just started
    final int nextLevel = gameRef.player.xpToNextLevel > 0 ? gameRef.player.xpToNextLevel : 1;
    final double pct = (gameRef.player.xp / nextLevel).clamp(0.0, 1.0);

    canvas.drawRect(Rect.fromLTWH(20, 10, width, height), _barBgPaint);
    canvas.drawRect(Rect.fromLTWH(20, 10, width * pct, height), _barFillPaint);
  }

  @override
  void update(double dt) {
    scoreText.text = 'Lv.${gameRef.player.level} | Wave ${gameRef.wave}';
    healthText.text = 'HP: ${gameRef.player.health}';
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
}
