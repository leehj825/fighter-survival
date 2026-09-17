import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fight_survival/game.dart';

void main() {
  group('isBlockedByShield', () {
    // knockbackDir always points from the attacker towards the enemy, which is
    // how every call site builds it (enemy.position - attacker.position).
    Vector2 hitFrom(Vector2 attacker, Vector2 enemy) => enemy - attacker;

    test('blocks a hit from the player the enemy is facing', () {
      final enemy = Vector2(100, 0);
      final player = Vector2.zero();
      expect(
        isBlockedByShield(player - enemy, hitFrom(player, enemy)),
        isTrue,
      );
    });

    test('does not block a hit from behind', () {
      final enemy = Vector2(100, 0);
      final player = Vector2.zero();
      final attackerBehind = Vector2(200, 0);
      expect(
        isBlockedByShield(player - enemy, hitFrom(attackerBehind, enemy)),
        isFalse,
      );
    });

    test('does not block a hit from exactly the side', () {
      expect(isBlockedByShield(Vector2(1, 0), Vector2(0, 1)), isFalse);
    });

    test('blocks frontal hits across all directions', () {
      for (final facing in <Vector2>[
        Vector2(1, 0),
        Vector2(-1, 0),
        Vector2(0, 1),
        Vector2(0, -1),
        Vector2(3, 4),
        Vector2(-7, 2),
      ]) {
        // A frontal attacker sits along the facing direction, so the hit
        // travels back towards the enemy.
        expect(isBlockedByShield(facing, -facing), isTrue,
            reason: 'facing $facing should block a frontal hit');
        expect(isBlockedByShield(facing, facing), isFalse,
            reason: 'facing $facing should not block a hit from behind');
      }
    });

    test('degenerate vectors never block', () {
      expect(isBlockedByShield(Vector2.zero(), Vector2(1, 0)), isFalse);
      expect(isBlockedByShield(Vector2(1, 0), Vector2.zero()), isFalse);
      expect(
        isBlockedByShield(Vector2(double.nan, 0), Vector2(1, 0)),
        isFalse,
      );
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
