import 'package:flutter/services.dart';

import 'managers.dart';

/// Thin wrapper over the platform haptics.
///
/// Throttled, because a busy wave would otherwise buzz continuously, and
/// silent when the player has turned haptics off in Settings.
class Haptics {
  Haptics._();

  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minGap = Duration(milliseconds: 90);

  static bool get _enabled {
    try {
      return GameData().hapticsEnabled;
    } catch (_) {
      // GameData has not been initialised (e.g. under test).
      return false;
    }
  }

  static bool _allow() {
    if (!_enabled) return false;
    final DateTime now = DateTime.now();
    if (now.difference(_last) < _minGap) return false;
    _last = now;
    return true;
  }

  /// A kill, a dash, a pickup.
  static void light() {
    if (_allow()) HapticFeedback.lightImpact();
  }

  /// Taking a hit, an elite dying.
  static void medium() {
    if (_allow()) HapticFeedback.mediumImpact();
  }

  /// A boss phase change, a revive, death.
  static void heavy() {
    if (_allow()) HapticFeedback.heavyImpact();
  }
}
