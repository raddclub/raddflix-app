import 'package:flutter_riverpod/flutter_riverpod.dart';

/// G5 (TEN_POINT_PLAN Phase G): shared [ProviderContainer] for non-widget
/// singleton services (ApiClient, RemoteConfig, SecurityTelemetry,
/// AppUpdateService) that run before/outside the widget tree and have no
/// `ref` of their own. main.dart creates this container once (before
/// runApp) and passes the *same instance* to `UncontrolledProviderScope`,
/// so `ref.watch`/`ref.read` inside widgets observe identical state to
/// what these services read/write here.
///
/// This mirrors the pattern already established for navigation globals in
/// `providers/app_navigation_provider.dart` (Phase E3) — a late-initialized
/// container *reference* is safer than bare mutable globals because the
/// data it holds (see `remote_values_provider.dart`) lives in testable,
/// override-able Riverpod state, not in untestable static fields.
late final ProviderContainer appContainer;
