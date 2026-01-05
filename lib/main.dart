import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'game.dart'; // Import the separated game logic

void main() {
  runApp(GameWidget(game: RpgGame()));
}
