import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'player_prefs.dart';

/// Global provider for all player preferences.
/// Read with: ref.watch(playerPrefsProvider)
/// Update with: ref.read(playerPrefsProvider.notifier).update((p) => p.copyWith(...))
final playerPrefsProvider =
    StateNotifierProvider<PlayerPrefsNotifier, PlayerPrefs>((ref) {
  return PlayerPrefsNotifier();
});

class PlayerPrefsNotifier extends StateNotifier<PlayerPrefs> {
  PlayerPrefsNotifier() : super(const PlayerPrefs()) {
    _load();
  }

  Future<void> _load() async {
    state = await PlayerPrefs.load();
  }

  /// Apply a transformation and immediately persist.
  Future<void> update(PlayerPrefs Function(PlayerPrefs current) updater) async {
    final next = updater(state);
    state = next;
    await next.save();
  }

  /// Replace the entire prefs object and persist.
  Future<void> set(PlayerPrefs prefs) async {
    state = prefs;
    await prefs.save();
  }

  /// Reset all preferences to factory defaults.
  Future<void> reset() async {
    const defaults = PlayerPrefs();
    state = defaults;
    await defaults.save();
  }
}
