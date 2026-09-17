import 'dart:math';

/// Behavioural variants an enemy can spawn with.
enum EnemyModifier { none, swift, ghostly, regen, kamikaze, shieldBearer, summoner }

/// An in-run upgrade offered when the player levels up.
enum Boon {
  damage('Power Surge', '+15% damage'),
  maxHealth('Reinforced Hull', '+25 max HP, fully healed'),
  moveSpeed('Overdrive', '+10% move speed'),
  dashCooldown('Cold Thrusters', '-15% dash cooldown'),
  pickupRadius('Tractor Beam', '+40 gem pickup radius'),
  meleeReach('Long Reach', '+20 melee reach'),
  regen('Nanobots', '+1 HP per second');

  const Boon(this.title, this.description);

  final String title;
  final String description;
}

/// Wave pacing, enemy scaling and the boon pool.
///
/// Everything here is pure and side-effect free so the difficulty curve can be
/// unit tested and tuned in one place, rather than living as literals spread
/// through the component classes.
class Balance {
  Balance._();

  // --- Wave composition ---

  /// An elite spawns alongside the wave every 5th wave.
  static bool isEliteWave(int wave) => wave % 5 == 0 && !isBossWave(wave);

  /// A boss replaces the elite every 10th wave.
  static bool isBossWave(int wave) => wave % 10 == 0;

  static int enemyCount(int wave) => 4 + (wave * 1.5).toInt();

  // --- Enemy scaling ---
  //
  // Wave 1 keeps the original values (2 HP, 100 HP elite) so early waves feel
  // unchanged; the growth is what late waves were missing.

  static int enemyHealth(int wave, {bool isElite = false, bool isBoss = false}) {
    final int base = 2 + (wave ~/ 2);
    if (isBoss) return base * 40 + 200;
    if (isElite) return base * 20 + 60;
    return base;
  }

  static int enemyMeleeDamage(int wave,
      {bool isElite = false, bool isBoss = false}) {
    final int base = isBoss ? 25 : (isElite ? 20 : 10);
    return base + (wave ~/ 5) * 2;
  }

  /// Hard cap on live enemies, so summoners cannot run the population away and
  /// leave a wave that can never be cleared.
  static const int maxLiveEnemies = 60;

  // --- Enemy modifiers ---
  //
  // These behaviours used to be reachable only on the single elite every 5th
  // wave, so most of them were never seen. Regular enemies now roll them, with
  // each variant introduced on its own wave so they are learnt one at a time.

  static const Map<EnemyModifier, int> _modifierUnlockWave =
      <EnemyModifier, int>{
    EnemyModifier.swift: 3,
    EnemyModifier.regen: 5,
    EnemyModifier.shieldBearer: 7,
    EnemyModifier.ghostly: 9,
    EnemyModifier.kamikaze: 11,
    EnemyModifier.summoner: 14,
  };

  /// Chance for a regular enemy to spawn with a modifier, ramping to 45%.
  static double modifierChance(int wave) =>
      (((wave - 2) * 0.04).clamp(0.0, 0.45)).toDouble();

  /// Modifiers introduced by [wave], in unlock order.
  static List<EnemyModifier> modifierPool(int wave) {
    final entries = _modifierUnlockWave.entries
        .where((entry) => wave >= entry.value)
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return entries.map((entry) => entry.key).toList();
  }

  /// Picks a modifier for a regular enemy, or [EnemyModifier.none].
  ///
  /// [summonersSpawned] caps summoners per wave: each one spawns an enemy
  /// every few seconds, so several at once snowballs.
  static EnemyModifier rollModifier(
    int wave,
    Random rng, {
    int summonersSpawned = 0,
    int maxSummoners = 1,
  }) {
    final pool = modifierPool(wave);
    if (pool.isEmpty || rng.nextDouble() >= modifierChance(wave)) {
      return EnemyModifier.none;
    }

    final candidates = summonersSpawned >= maxSummoners
        ? (pool.where((m) => m != EnemyModifier.summoner).toList())
        : pool;
    if (candidates.isEmpty) return EnemyModifier.none;

    return candidates[rng.nextInt(candidates.length)];
  }

  /// Modifier for the elite on an elite wave. Elites always get one.
  static EnemyModifier rollEliteModifier(int wave, Random rng) {
    final pool = modifierPool(wave);
    if (pool.isEmpty) return EnemyModifier.none;
    // Summoner elites are excluded: an elite that never stops spawning adds is
    // a stalemate, not a fight.
    final candidates =
        pool.where((m) => m != EnemyModifier.summoner).toList();
    if (candidates.isEmpty) return EnemyModifier.none;
    return candidates[rng.nextInt(candidates.length)];
  }

  // --- Boss phases ---

  /// Boss phase for a given health fraction: 0 while above 2/3, 1 above 1/3,
  /// 2 below that.
  static int bossPhase(double healthFraction) {
    if (healthFraction > 2 / 3) return 0;
    if (healthFraction > 1 / 3) return 1;
    return 2;
  }

  // --- Boons ---

  /// [count] distinct boons to offer on level up.
  static List<Boon> rollBoons(Random rng, {int count = 3}) {
    final pool = List<Boon>.of(Boon.values)..shuffle(rng);
    return pool.take(count.clamp(0, Boon.values.length)).toList();
  }
}
