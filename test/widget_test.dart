import 'package:flutter_test/flutter_test.dart';
import 'package:flame/game.dart';
import 'package:fight_survival/game.dart'; // Changed import to game.dart

void main() {
  testWidgets('RpgGame starts and runs', (WidgetTester tester) async {
    // Build the GameWidget with our RpgGame
    final game = RpgGame();
    await tester.pumpWidget(GameWidget(game: game));

    // Verify the GameWidget is present
    expect(find.byType(GameWidget<RpgGame>), findsOneWidget);

    // Allow the game loop to tick (Flame requires this)
    await tester.pump();
  });
}
