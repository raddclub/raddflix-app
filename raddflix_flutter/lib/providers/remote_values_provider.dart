import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';

/// G5 (TEN_POINT_PLAN Phase G): replaces the mutable `static var` fields that
/// used to live on [AppConstants] (`apiBaseUrl`, `jazzDriveDeltaUrl`,
/// `supportWhatsApp`) with Riverpod-managed state.
///
/// `RemoteConfig` calls the setters below instead of assigning to a static
/// field directly, and every consumer reads through `remoteValuesProvider`
/// (via `ref.watch`/`ref.read` in widgets, or `appContainer.read` in
/// non-widget services — see `core/app_container.dart`). This makes the
/// values overridable in tests and keeps app state out of untestable
/// mutable statics.
class RemoteValues {
  final String apiBaseUrl;
  final String jazzDriveDeltaUrl;
  final String supportWhatsApp;

  const RemoteValues({
    required this.apiBaseUrl,
    required this.jazzDriveDeltaUrl,
    required this.supportWhatsApp,
  });

  RemoteValues copyWith({
    String? apiBaseUrl,
    String? jazzDriveDeltaUrl,
    String? supportWhatsApp,
  }) =>
      RemoteValues(
        apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
        jazzDriveDeltaUrl: jazzDriveDeltaUrl ?? this.jazzDriveDeltaUrl,
        supportWhatsApp: supportWhatsApp ?? this.supportWhatsApp,
      );
}

class RemoteValuesNotifier extends StateNotifier<RemoteValues> {
  RemoteValuesNotifier()
      : super(const RemoteValues(
          apiBaseUrl: AppConstants.apiBaseUrlDefault,
          jazzDriveDeltaUrl: '',
          supportWhatsApp: AppConstants.supportWhatsAppDefault,
        ));

  void setApiBaseUrl(String url) {
    if (url.isEmpty || url == state.apiBaseUrl) return;
    state = state.copyWith(apiBaseUrl: url);
  }

  void setJazzDriveDeltaUrl(String url) {
    if (url.isEmpty || url == state.jazzDriveDeltaUrl) return;
    state = state.copyWith(jazzDriveDeltaUrl: url);
  }

  void setSupportWhatsApp(String number) {
    if (number.isEmpty || number == state.supportWhatsApp) return;
    state = state.copyWith(supportWhatsApp: number);
  }
}

final remoteValuesProvider =
    StateNotifierProvider<RemoteValuesNotifier, RemoteValues>(
        (ref) => RemoteValuesNotifier());
