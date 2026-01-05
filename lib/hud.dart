import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_rpg_prototype/main.dart';

class Hud extends PositionComponent with HasGameRef<RpgGame> {
  late TextComponent scoreText;
  late TextComponent waveText;
  late TextComponent healthText;

  Hud() : super(priority: 100); // Always on top

  @override
  Future<void> onLoad() async {
    scoreText = TextComponent(
      text: 'Kills: 0',
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.white, fontSize: 24),
      ),
      position: Vector2(20, 40),
    );
    add(scoreText);

    waveText = TextComponent(
      text: 'Wave: 1',
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.yellow, fontSize: 24),
      ),
      position: Vector2(20, 70),
    );
    add(waveText);

    healthText = TextComponent(
      text: 'HP: 100',
      textRenderer: TextPaint(
        style: const TextStyle(color: Colors.green, fontSize: 24),
      ),
      position: Vector2(20, 100),
    );
    add(healthText);
  }

  @override
  void update(double dt) {
    scoreText.text = 'Kills: ${gameRef.killCount}';
    waveText.text = 'Wave: ${gameRef.wave}';
    healthText.text = 'HP: ${gameRef.player.health}';

    // Simple Game Over check visualization
    if (gameRef.player.health <= 0) {
      healthText.text = "GAME OVER";
      healthText.textRenderer = TextPaint(
        style: const TextStyle(color: Colors.red, fontSize: 32, fontWeight: FontWeight.bold),
      );
    }

    // Keep HUD fixed on screen (it's a component in the game, but we want it static)
    // Wait! A standard PositionComponent in a Camera-based game moves with the world if added to the world.
    // We should add this to the GAME (viewport), not the WORLD.
    // In RpgGame.onLoad, we will add Hud directly to game, not world.
    // And Hud should accept size from gameRef.cameraComponent.viewport.size ideally, but fixed offset is fine.
  }
}
