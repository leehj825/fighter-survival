import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rpg_prototype/main.dart'; // Ensure package name matches pubspec.yaml

void main() {
  testWidgets('Game app starts and renders', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const GameApp());

    // Verify that the GameScreen is present
    expect(find.byType(GameScreen), findsOneWidget);

    // Verify that CustomPaint is present
    expect(find.byType(CustomPaint), findsOneWidget);
  });
}
