import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../core/db/local_db.dart';
import '../models/profile.dart';

const int kMaxProfiles = 5;

class ProfileState {
  final List<Profile> profiles;
  final Profile? active;
  final bool loading;

  const ProfileState({this.profiles = const [], this.active, this.loading = true});

  ProfileState copyWith({List<Profile>? profiles, Profile? active, bool? loading}) {
    return ProfileState(
      profiles: profiles ?? this.profiles,
      active: active ?? this.active,
      loading: loading ?? this.loading,
    );
  }
}

class ProfileNotifier extends StateNotifier<ProfileState> {
  ProfileNotifier() : super(const ProfileState()) {
    load();
  }

  /// Loads all profiles and re-selects the previously-active one (or the
  /// first profile if none was saved / it was deleted). Always leaves
  /// LocalDb.currentProfileId in sync with state.active so every existing
  /// watchlist/history call site picks the right profile automatically.
  Future<void> load() async {
    var rows = await LocalDb.getProfiles();
    if (rows.isEmpty) {
      // Guard only — the DB always seeds a default profile on create/migrate.
      await LocalDb.createProfile(name: 'Me');
      rows = await LocalDb.getProfiles();
    }
    final profiles = rows.map(Profile.fromRow).toList();

    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getInt(StorageKeys.activeProfileId);
    final active = profiles.firstWhere(
      (p) => p.id == savedId,
      orElse: () => profiles.first,
    );

    LocalDb.currentProfileId = active.id;
    state = state.copyWith(profiles: profiles, active: active, loading: false);
  }

  /// Attempts to switch to [id]. If the profile is PIN-locked, [pin] must
  /// match or the switch is rejected (returns false) without changing state.
  Future<bool> selectProfile(int id, {String? pin}) async {
    final profile = state.profiles.firstWhere(
      (p) => p.id == id,
      orElse: () => state.profiles.first,
    );
    if (profile.isLocked && profile.pin != pin) return false;

    LocalDb.currentProfileId = profile.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(StorageKeys.activeProfileId, profile.id);
    state = state.copyWith(active: profile);
    return true;
  }

  Future<void> addProfile({
    required String name,
    required String avatarColor,
    required String avatarEmoji,
    bool isKids = false,
    String maxRating = 'nc17',
    String? pin,
  }) async {
    await LocalDb.createProfile(
      name: name,
      avatarColor: avatarColor,
      avatarEmoji: avatarEmoji,
      isKids: isKids,
      maxRating: maxRating,
      pin: pin,
    );
    await load();
  }

  Future<void> editProfile(
    int id, {
    String? name,
    String? avatarColor,
    String? avatarEmoji,
    bool? isKids,
    String? maxRating,
    String? pin,
    bool clearPin = false,
  }) async {
    await LocalDb.updateProfile(
      id,
      name: name,
      avatarColor: avatarColor,
      avatarEmoji: avatarEmoji,
      isKids: isKids,
      maxRating: isKids == true ? 'pg' : maxRating,
      pin: pin,
      clearPin: clearPin,
    );
    await load();
  }

  /// Resets profile state to empty on logout. The next authenticated user's
  /// auth flow will trigger a fresh [load()] via their own session.
  void reset() {
    state = const ProfileState(loading: false);
  }

  /// Always keeps at least one profile — deletion is a no-op otherwise.
  Future<void> removeProfile(int id) async {
    if (state.profiles.length <= 1) return;
    await LocalDb.deleteProfile(id);
    if (state.active?.id == id) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(StorageKeys.activeProfileId);
    }
    await load();
  }

}

final profileProvider = StateNotifierProvider<ProfileNotifier, ProfileState>(
  (_) => ProfileNotifier(),
);

/// Shared post-auth navigation: skips the "Who's Watching" screen when the
/// account only has a single profile (the common case), and shows it
/// whenever there's more than one — same convention as Netflix/Disney+.
/// Called from splash, login and register screens right after a successful
/// authentication.
Future<void> navigateAfterAuth(BuildContext context, WidgetRef ref) async {
  await ref.read(profileProvider.notifier).load();
  if (!context.mounted) return;
  final profiles = ref.read(profileProvider).profiles;
  if (profiles.length <= 1) {
    Navigator.of(context).pushReplacementNamed(AppRoutes.home);
  } else {
    Navigator.of(context).pushReplacementNamed(AppRoutes.profileSwitcher);
  }
}
