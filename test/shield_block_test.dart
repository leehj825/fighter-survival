import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fight_survival/game.dart';

void main() {
  /// Every damage source passes knockbackDir as (enemy - attacker), i.e.
  /// pointing from the attacker towards the enemy.
  Vector2 hitFrom(Vector2 attacker, Vector2 enemy) => enemy - attacker;

  group('isBlockedByShield', () {
    test('blocks a hit arriving from straight in front', () {
      // Facing +x, attacker standing at +x.
      expect(isBlockedByShield(0, Vector2(-1, 0)), isTrue);
    });

    test('does not block a hit from behind', () {
      expect(isBlockedByShield(0, Vector2(1, 0)), isFalse);
    });

    test('does not block a hit from the side', () {
      // 90 degrees off the facing is outside the 60 degree half-arc.
      expect(isBlockedByShield(0, Vector2(0, -1)), isFalse);
      expect(isBlockedByShield(0, Vector2(0, 1)), isFalse);
    });

    test('blocks inside the arc and not outside it', () {
      for (final double offset in <double>[0, 0.4, 1.0]) {
        // Attacker sits `offset` radians off the facing direction.
        final Vector2 attacker = Vector2(cos(offset), sin(offset));
        expect(isBlockedByShield(0, -attacker), offset <= kShieldArcHalfWidth,
            reason: 'offset $offset rad');
      }
      expect(isBlockedByShield(0, -Vector2(cos(1.2), sin(1.2))), isFalse);
    });

    test('works for any facing angle', () {
      for (final double facing in <double>[-3.0, -1.5, 0, 0.7, 2.5, 3.1]) {
        final Vector2 inFront = Vector2(cos(facing), sin(facing));
        expect(isBlockedByShield(facing, -inFront), isTrue,
            reason: 'facing $facing should block a frontal hit');
        expect(isBlockedByShield(facing, inFront), isFalse,
            reason: 'facing $facing should not block a hit from behind');
      }
    });

    test('a player the shield has turned away from is not blocked', () {
      // Regression: the shield used to be tested against a facing recomputed
      // towards the player every frame, so the player was always in the arc
      // and every single hit was blocked -- the enemy could not be killed.
      final enemy = Vector2(100, 0);
      final player = Vector2.zero();
      const double facingAwayFromPlayer = 0; // looking +x, player is at -x
      expect(
        isBlockedByShield(facingAwayFromPlayer, hitFrom(player, enemy)),
        isFalse,
      );

      // Same hit, but with the shield turned to meet it.
      expect(isBlockedByShield(pi, hitFrom(player, enemy)), isTrue);
    });

    test('degenerate directions never block', () {
      expect(isBlockedByShield(0, Vector2.zero()), isFalse);
      expect(isBlockedByShield(0, Vector2(double.nan, 0)), isFalse);
    });
  });

  group('SafeVector2.safeNormalized', () {
    test('normalizes a regular vector', () {
      expect(Vector2(3, 4).safeNormalized().length, closeTo(1.0, 1e-6));
    });

    test('returns zero for a zero vector instead of NaN', () {
      expect(Vector2.zero().safeNormalized(), Vector2.zero());
    });

    test('returns zero for NaN components', () {
      expect(Vector2(double.nan, 1).safeNormalized(), Vector2.zero());
    });
  });
}
