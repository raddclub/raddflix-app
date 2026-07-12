import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// E3 (TEN_POINT_PLAN Phase E): these used to be bare global mutable
/// variables in app.dart (`appNavigatorKey`, `pendingVideoUri`, etc.) —
/// invisible to Riverpod's dependency graph, not overridable in tests, and a
/// source of possible silent races. Moved into providers instead.
///
/// main.dart runs before the widget tree exists (it needs to read/write
/// these from a native MethodChannel handler with no BuildContext), so it
/// creates its own `ProviderContainer` and passes it to `runApp` via
/// `UncontrolledProviderScope` rather than reading these through `ref`.

/// The app's single Navigator key — lets code with no BuildContext (the
/// background "Open with" intent handler in main.dart) push routes.
final navigatorKeyProvider = Provider<GlobalKey<NavigatorState>>(
  (ref) => GlobalKey<NavigatorState>(),
);

/// Pending video URI from a cold-start "Open with" ACTION_VIEW intent.
/// Set once in main.dart before runApp(); read once and cleared by
/// SplashScreen._start().
final pendingVideoUriProvider = StateProvider<String?>((ref) => null);

/// Resolved display name for [pendingVideoUriProvider] (from Android
/// ContentResolver). Set alongside it in main.dart; cleared after use.
final pendingVideoTitleProvider = StateProvider<String?>((ref) => null);

/// Path to an external subtitle file found alongside the opened video (or
/// vice versa). Set by native MainActivity when a sidecar .srt/.ass exists,
/// or when the user opens a subtitle file and the matching video is found in
/// the same directory.
final pendingSubtitleUriProvider = StateProvider<String?>((ref) => null);
