import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api/auth_api.dart';
import '../core/db/local_db.dart';
import '../core/security/keystore.dart';
import '../core/constants.dart';
import '../models/user.dart';
import 'watchlist_provider.dart';
import 'profile_provider.dart';
import '../core/player/player_prefs_provider.dart';
import 'auth_config_provider.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class RegistrationException implements Exception {
  final String message;
  const RegistrationException(this.message);
  @override
  String toString() => message;
}

class AuthState {
  final AuthStatus status;
  final AppUser? user;
  final String? error;
  /// Set when login fails with a device_conflict (409).
  /// Contains the name of the device already bound to the account.
  final String? deviceConflictName;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.error,
    this.deviceConflictName,
  });

  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    String? error,
    String? deviceConflictName,
  }) {
    return AuthState(
      status:             status ?? this.status,
      user:               user ?? this.user,
      error:              error,
      deviceConflictName: deviceConflictName,
    );
  }

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isDeviceConflict => error == 'device_conflict';
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(const AuthState());
  final Ref _ref;

  Future<void> checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final isGuest = prefs.getBool(StorageKeys.isGuest) ?? false;

    if (isGuest) {
      // Local-only guest check — works 100% offline, no token or network needed.
      // Create guest identity if missing (handles app reinstall edge case).
      await LocalDb.getOrCreateGuestId();
      _ref.read(authConfigProvider.notifier).setGuestMode(true);
      state = AuthState(status: AuthStatus.authenticated, user: AppUser.guest());
      // Background: grab a server token for Oracle catalog fallback when online.
      _tryAcquireGuestServerToken();
      return;
    }

    final hasToken = await Keystore.hasTokens();
    if (!hasToken) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }

    // Optimistic auth: restore cached user immediately so the app opens
    // without a network round-trip on every restart.
    final cachedUser = await _loadCachedUser(prefs);
    if (cachedUser != null) {
      state = AuthState(status: AuthStatus.authenticated, user: cachedUser);
    }

    try {
      final user = await AuthApi.getMe();
      await _saveUserCache(user, prefs);
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        // Server explicitly rejected the token — force re-login.
        await Keystore.clearAll();
        await _clearUserCache(prefs);
        state = const AuthState(status: AuthStatus.unauthenticated);
      } else {
        // Network / server error: keep the user logged in with cached data.
        // Tokens are preserved so the next startup or API call can retry.
        if (cachedUser == null) {
          state = const AuthState(status: AuthStatus.unauthenticated);
        }
      }
    } catch (_) {
      // Unknown error: stay logged in if we have cached data.
      if (cachedUser == null) {
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    }
  }

  Future<void> login({required String phone, required String password}) async {
    state = const AuthState(status: AuthStatus.unknown);
    try {
      final result = await AuthApi.login(phone: phone, password: password);
      await Keystore.saveTokens(
        accessToken:  result.accessToken,
        refreshToken: result.refreshToken,
        userId:       result.userId.toString(),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(StorageKeys.isGuest);
      _ref.read(authConfigProvider.notifier).setGuestMode(false);
      final user = await AuthApi.getMe();
      await _saveUserCache(user, prefs);
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        // Device conflict — another device is already bound to this account
        final body = e.response?.data;
        String deviceName = 'Another Device';
        if (body is Map) {
          deviceName = (body['bound_device_name'] as String?)
              ?? (body['message'] as String?)
              ?? deviceName;
        }
        state = AuthState(
          status:             AuthStatus.unauthenticated,
          error:              'device_conflict',
          deviceConflictName: deviceName,
        );
        return;
      }
      // Other HTTP errors
      final body = e.response?.data;
      String message = 'Login failed. Please try again.';
      if (body is Map && body['error'] != null) {
        message = body['error'] as String;
      } else if (e.type == DioExceptionType.connectionError ||
                 e.type == DioExceptionType.connectionTimeout) {
        message = 'Cannot connect. Check your internet.';
      }
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error:  message,
      );
    } catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error:  'Login failed. Please try again.',
      );
    }
  }

  Future<void> register({required String phone, required String password}) async {
    // H-03: missing try-catch meant DioException (e.g. 422 "phone already taken")
    // crashed with an unhandled exception.  Wrap and rethrow as RegistrationException
    // so the UI can surface a user-readable message.
    try {
      await AuthApi.register(phone: phone, password: password);
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = (data is Map)
          ? (data['message'] ?? data['error'] ?? 'Registration failed').toString()
          : 'Registration failed. Please try again.';
      throw RegistrationException(msg);
    } catch (_) {
      throw RegistrationException('Registration failed. Please try again.');
    }
    // Auto-login removed: calling login() after register caused auth-state
    // race conditions that showed "Registration failed" even when the account
    // was created. User is sent to the login screen to sign in manually.
  }

  Future<void> continueAsGuest() async {
    // 1. Create or load local guest identity — works 100% offline, no server needed.
    //    The guest ID is a permanent UUID stored in SQLite sync_meta.
    await LocalDb.getOrCreateGuestId();

    // 2. Mark as guest and set authenticated state immediately.
    //    User enters the app NOW — no waiting for a network response.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.isGuest, true);
    _ref.read(authConfigProvider.notifier).setGuestMode(true);
    state = AuthState(status: AuthStatus.authenticated, user: AppUser.guest());

    // 3. Background: try to acquire a server guest token for Oracle catalog fallback.
    //    Silent fail — offline Jazz SIM users get catalog from zero-rated delta instead.
    _tryAcquireGuestServerToken();
  }

  /// Silently requests a short-lived guest token from the server.
  /// Called in background after guest login — never blocks the guest UX.
  /// If offline or server unavailable, does nothing (zero-rated catalog still works).
  void _tryAcquireGuestServerToken() {
    AuthApi.guestLogin().then((token) async {
      // H-04: race guard — user may have logged out between the API call starting
      // and this .then() callback firing.  Only persist tokens if still in guest mode.
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(StorageKeys.isGuest) ?? false)) return;
      return Keystore.saveTokens(
        accessToken:  token,
        refreshToken: '',
        userId:       '0',
      );
    }).catchError((_) {
      // Offline or server unavailable — guest still works via JazzDrive zero-rated delta.
    });
  }

  Future<void> logout() async {
    try { await AuthApi.logout(); } catch (_) {}
    await Keystore.clearAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.isGuest);
    await _clearUserCache(prefs);
    _ref.read(authConfigProvider.notifier).resetOnLogout();
    // A5: clear per-user state so next account doesn't inherit previous session
    _ref.read(watchlistProvider.notifier).clear();
    _ref.read(profileProvider.notifier).reset();
    _ref.read(playerPrefsProvider.notifier).reset();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Returns the current access token (for constructing stream URLs).
  Future<String?> getAccessToken() => Keystore.getAccessToken();

  void refreshUser(AppUser user) {
    state = state.copyWith(user: user);
  }

  /// Silently re-fetch user from server in the background.
  /// Called after catalog sync so plan upgrades reach the user immediately.
  /// Never disrupts authenticated state — any failure is silently swallowed.
  Future<void> silentRefresh() async {
    if (!state.isAuthenticated || (state.user?.isGuest ?? true)) return;
    try {
      final user = await AuthApi.getMe();
      final prefs = await SharedPreferences.getInstance();
      await _saveUserCache(user, prefs);
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } catch (_) {
      // Network/server error — keep current state, try again on next sync
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  // ── User cache helpers ────────────────────────────────────────────────────
  // Persists basic user info (id, phone, plan, sub expiry) to SharedPreferences
  // so checkAuth() can restore the session instantly on restart, even offline.

  Future<AppUser?> _loadCachedUser(SharedPreferences prefs) async {
    final id    = int.tryParse(prefs.getString(StorageKeys.cachedUserId)   ?? '');
    final phone = prefs.getString(StorageKeys.cachedUserPhone) ?? '';
    if (id == null || id == 0 || phone.isEmpty) return null;
    final plan      = prefs.getString(StorageKeys.cachedUserPlan)    ?? 'free';
    final expiresAt = prefs.getString(StorageKeys.cachedSubExpiry);
    final hasSub    = plan != 'free' && plan.isNotEmpty;
    // BUG-C03 fix: reuse UserSubscription.fromJson which checks expiresAt against
    // DateTime.now() — previously isActive was hardcoded true so expired subscriptions
    // still appeared active on every app restart until the /me network call completed.
    // BUG-5 fix: restore cached avatar fields so UI doesn't flash defaults on cold start.
    return AppUser(
      id:          id,
      phone:       phone,
      isActive:    true,
      displayName: prefs.getString('jm_cached_display_name'),
      avatarColor: prefs.getString('jm_cached_avatar_color') ?? '#8B002D',
      avatarEmoji: prefs.getString('jm_cached_avatar_emoji') ?? '',
      subscription: hasSub
          ? UserSubscription.fromJson({
              'plan':       plan,
              'is_active':  1,
              'expires_at': expiresAt,
            })
          : null,
    );
  }

  Future<void> _saveUserCache(AppUser user, SharedPreferences prefs) async {
    await prefs.setString(StorageKeys.cachedUserId,   user.id.toString());
    await prefs.setString(StorageKeys.cachedUserPhone, user.phone);
    await prefs.setString(StorageKeys.cachedUserPlan,  user.planName);
    // BUG-5 fix: persist avatar fields so _loadCachedUser can restore them.
    if (user.displayName != null) await prefs.setString('jm_cached_display_name', user.displayName!);
    await prefs.setString('jm_cached_avatar_color', user.avatarColor);
    await prefs.setString('jm_cached_avatar_emoji', user.avatarEmoji);
    final exp = user.subscription?.expiresAt;
    if (exp != null) await prefs.setString(StorageKeys.cachedSubExpiry, exp);
  }

  Future<void> _clearUserCache(SharedPreferences prefs) async {
    await prefs.remove(StorageKeys.cachedUserId);
    await prefs.remove(StorageKeys.cachedUserPhone);
    await prefs.remove(StorageKeys.cachedUserPlan);
    await prefs.remove(StorageKeys.cachedSubExpiry);
    await prefs.remove('jm_cached_display_name');
    await prefs.remove('jm_cached_avatar_color');
    await prefs.remove('jm_cached_avatar_emoji');
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref),
);
