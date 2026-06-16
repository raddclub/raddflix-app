/// Shared authentication error message helpers.
///
/// P3.4: Extracted from login_screen.dart and register_screen.dart to
/// eliminate duplicate _friendly() functions. Each screen-specific method
/// preserves its original error messages exactly.
class AuthErrors {
  const AuthErrors._();

  /// Friendly error for the login screen.
  static String login(String raw) {
    if (raw.contains('401') || raw.contains('Invalid')) {
      return 'Wrong phone or password.';
    }
    if (raw.contains('SocketException') || raw.contains('connection')) {
      return 'No internet connection.';
    }
    return 'Login failed. Please try again.';
  }

  /// Friendly error for the registration screen.
  static String register(String raw) {
    if (raw.contains('409') || raw.contains('already')) {
      return 'Phone already registered. Try signing in.';
    }
    if (raw.contains('SocketException') || raw.contains('connection')) {
      return 'No internet connection.';
    }
    return 'Registration failed. Please try again.';
  }

  /// Generic network error (used for guest/other flows).
  static const String noInternet = 'No internet connection.';
}
