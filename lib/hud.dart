import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'game.dart';

class Hud extends PositionComponent with HasGameReference<RpgGame> {
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
        backgroundColor: Colors.black.withValues(alpha: 0.5),
      ),
    ),
  );

  static const TextStyle _warningStyle = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
  );

  /// Two prepared renderers instead of rebuilding a TextPaint on every
  /// show/hide of the boss warning.
  static final TextPaint _warningVisible =
      TextPaint(style: _warningStyle.copyWith(color: Colors.redAccent));
  static final TextPaint _warningHidden =
      TextPaint(style: _warningStyle.copyWith(color: Colors.transparent));

  final TextComponent bossWarningText = TextComponent(
    text: 'WARNING: GIANT ENEMY APPROACHING',
    anchor: Anchor.center,
    textRenderer: _warningHidden,
  );

  final TextComponent comboText = TextComponent(
    text: '',
    anchor: Anchor.topRight,
    textRenderer: TextPaint(
      style: const TextStyle(
        color: Colors.orangeAccent,
        fontSize: 22,
        fontWeight: FontWeight.bold,
        shadows: [Shadow(blurRadius: 3, color: Colors.black)],
      ),
    ),
  );

  final Paint _barBgPaint = Paint()..color = Colors.grey.withValues(alpha: 0.5);
  final Paint _barFillPaint = Paint()..color = Colors.cyanAccent;
  final Paint _hpBarFillPaint = Paint()..color = Colors.green;
  final Paint _hpBarBgPaint = Paint()..color = Colors.red.withValues(alpha: 0.3);
  final Paint _bossBarBgPaint =
      Paint()..color = Colors.black.withValues(alpha: 0.6);
  final Paint _bossBarFillPaint = Paint()..color = Colors.redAccent;
  final Paint _bossTickPaint =
      Paint()..color = Colors.white.withValues(alpha: 0.6)..strokeWidth = 2;

  // Countdowns driven by the game clock, so they pause with the game and can
  // never fire after this component is removed (Future.delayed did both).
  static const double _messageDuration = 4.0;
  double _storyTimer = 0.0;
  double _warningTimer = 0.0;

  String _lastScoreText = '';

  // A brief scale-pop every time the combo climbs, purely cosmetic.
  int _lastShownCombo = 0;
  double _comboPulse = 0.0;
  static const double _comboPulseDuration = 0.18;

  Hud() : super(priority: 1000); // Higher priority to ensure on top

  @override
  Future<void> onLoad() async {
    add(scoreText);
    add(storyText);
    add(bossWarningText);
    add(comboText);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    storyText.position = Vector2(size.x / 2, 80); // Moved to top, under bars
    bossWarningText.position = size / 2;
    comboText.position = Vector2(size.x - 20, 20);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final double width = game.size.x - 40;
    const double height = 10;

    // XP Bar (Top)
    final int nextLevel = game.player.xpToNextLevel > 0 ? game.player.xpToNextLevel : 1;
    final double xpPct = (game.player.xp / nextLevel).clamp(0.0, 1.0);

    canvas.drawRect(Rect.fromLTWH(20, 10, width, height), _barBgPaint);
    canvas.drawRect(Rect.fromLTWH(20, 10, width * xpPct, height), _barFillPaint);

    // HP Bar (Under Level Text)
    // Level text is at 20, 20 (height ~20-30). So bar at y=50
    final double hpPct = (game.player.health / game.player.maxHealth).clamp(0.0, 1.0);
    canvas.drawRect(const Rect.fromLTWH(20, 50, 200, 15), _hpBarBgPaint);
    canvas.drawRect(Rect.fromLTWH(20, 50, 200 * hpPct, 15), _hpBarFillPaint);

    _renderBossBar(canvas);
  }

  /// Health bar for the boss, with ticks marking the phase thresholds.
  void _renderBossBar(Canvas canvas) {
    final bosses = game.world.children.whereType<Boss>();
    if (bosses.isEmpty) return;

    final Boss boss = bosses.first;
    if (boss.maxHealth <= 0) return;

    final double pct = (boss.health / boss.maxHealth).clamp(0.0, 1.0);
    final double barWidth = game.size.x * 0.6;
    final double left = (game.size.x - barWidth) / 2;
    const double top = 110;
    const double height = 14;

    _bossBarFillPaint.color =
        boss.phase == 2 ? Colors.redAccent : Colors.deepOrangeAccent;

    canvas.drawRect(
        Rect.fromLTWH(left, top, barWidth, height), _bossBarBgPaint);
    canvas.drawRect(
        Rect.fromLTWH(left, top, barWidth * pct, height), _bossBarFillPaint);

    for (final double fraction in const <double>[1 / 3, 2 / 3]) {
      final double x = left + barWidth * fraction;
      canvas.drawLine(
          Offset(x, top), Offset(x, top + height), _bossTickPaint);
    }
  }

  @override
  void update(double dt) {
    final String score = 'Lv.${game.player.level} | Wave ${game.wave}';
    if (score != _lastScoreText) {
      _lastScoreText = score;
      scoreText.text = score;
    }

    if (_storyTimer > 0) {
      _storyTimer -= dt;
      if (_storyTimer <= 0) storyText.text = '';
    }

    if (_warningTimer > 0) {
      _warningTimer -= dt;
      if (_warningTimer <= 0) bossWarningText.textRenderer = _warningHidden;
    }

    if (game.gameOver) {
      _storyTimer = 0.0;
      storyText.text = 'SIGNAL LOST.';
    }

    _updateCombo(dt);
  }

  void _updateCombo(double dt) {
    final int combo = game.combo;
    if (combo != _lastShownCombo) {
      if (combo > _lastShownCombo) _comboPulse = _comboPulseDuration;
      _lastShownCombo = combo;
      comboText.text = combo >= 2 ? '${combo}x COMBO' : '';
    }

    if (_comboPulse > 0) {
      _comboPulse -= dt;
      final double t = (_comboPulse / _comboPulseDuration).clamp(0.0, 1.0);
      comboText.scale = Vector2.all(1.0 + t * 0.4);
    } else {
      comboText.scale = Vector2.all(1.0);
    }
  }

  void showStory(String message) {
    storyText.text = message;
    _storyTimer = _messageDuration;
  }

  void showBossWarning() {
    bossWarningText.textRenderer = _warningVisible;
    _warningTimer = _messageDuration;
  }
}
