import 'package:flutter_riverpod/flutter_riverpod.dart';

/// L10 (TEN_POINT_PLAN Phase L): replaces `ApiClient.isGuestMode` — a mutable
/// `static bool` — with Riverpod-managed state, following the same pattern
/// established for `RemoteValues` in `remote_values_provider.dart` (G5).
///
/// A bare mutable static is unsafe in a multi-isolate context and untestable
/// (no way to inject a different value in tests). It also has no single
/// place that guarantees it is reset — every call site that flips it to
/// `true` must remember to flip it back. Centralising it here means the
/// reset-on-logout guarantee lives in one notifier method instead of being
/// re-implemented at every auth call site.
///
/// `ApiClient` (a non-widget singleton) reads this through `appContainer`,
/// exactly like it already does for `remoteValuesProvider`. `AuthNotifier`
/// (a widget-tree provider with its own `ref`) writes to it via
/// `ref.read(authConfigProvider.notifier)`.
class AuthConfigNotifier extends StateNotifier<bool> {
  AuthConfigNotifier() : super(false);

  /// Sets guest mode. `AuthNotifier.checkAuth()` / `continueAsGuest()` call
  /// this with `true`; `login()` calls it with `false`.
  void setGuestMode(bool value) {
    if (state == value) return;
    state = value;
  }

  /// Explicit reset for the logout path — kept as a separate named method
  /// (rather than relying on callers to pass `false`) so the intent at the
  /// call site in `AuthNotifier.logout()` is unambiguous.
  void resetOnLogout() => setGuestMode(false);
}

/// `state` is `true` when the current session is an offline-first guest —
/// see the original doc comment on `ApiClient.isGuestMode` for behaviour.
final authConfigProvider =
    StateNotifierProvider<AuthConfigNotifier, bool>((ref) => AuthConfigNotifier());
