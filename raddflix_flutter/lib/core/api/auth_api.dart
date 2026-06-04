import 'package:dio/dio.dart';
import '../constants.dart';
import 'api_client.dart';
import '../../models/user.dart';
import '../security/keystore.dart';
import '../security/device_id.dart';

class AuthApi {
  static final _client = ApiClient.instance;

  /// Continue as guest — returns a short-lived access token, no account needed.
  static Future<String> guestLogin() async {
    final response = await _client.post(ApiPaths.guest);
    final data = response.data as Map<String, dynamic>;
    return data['access_token'] as String;
  }

  /// Register a new account with phone + password.
  /// Returns void — if no DioException is thrown, the account was created.
  /// Does NOT parse the response body to avoid cast errors on XOR-encoded responses.
  static Future<void> register({
    required String phone,
    required String password,
  }) async {
    await _client.post(
      ApiPaths.register,
      data: {'phone': phone, 'password': password},
    );
  }

  /// Login with phone + password. Returns access + refresh tokens.
  /// Also binds device ID automatically.
  static Future<LoginResult> login({
    required String phone,
    required String password,
  }) async {
    final deviceId   = await DeviceIdentifier.getDeviceId();
    final deviceName = await DeviceIdentifier.getDeviceName();

    final response = await _client.post(
      ApiPaths.login,
      data: {
        'phone':       phone,
        'password':    password,
        'device_id':   deviceId,
        'device_name': deviceName,
      },
    );

    final data = response.data as Map<String, dynamic>;
    return LoginResult.fromJson(data);
  }

  /// Get the currently logged-in user's profile + subscription info.
  static Future<AppUser> getMe() async {
    final response = await _client.get(ApiPaths.me);
    return AppUser.fromJson(response.data as Map<String, dynamic>);
  }

  /// Logout — invalidates the refresh token on the server.
  static Future<void> logout() async {
    try {
      final refreshToken = await Keystore.getRefreshToken();
      if (refreshToken != null) {
        await _client.post(
          ApiPaths.logout,
          data: {'refresh_token': refreshToken},
        );
      }
    } catch (_) {
      // Ignore logout errors — we'll clear tokens locally regardless
    } finally {
      await Keystore.clearAll();
    }
  }

  // BUG-A27: bindDevice() removed — device binding is handled
  // automatically inside login() via the /api/auth/login endpoint.


  // ═══════════════════════════════════════════════════════════════════════════
  // OTP DEVICE SWITCH — future integration hook
  //
  // These methods are stubs. To activate:
  //   1. Set AppConstants.otpDeviceSwitchEnabled = true in constants.dart
  //   2. Add your OTP provider call inside requestDeviceSwitchOtp()
  //   3. Add your OTP verification call inside verifyDeviceSwitchOtp()
  //   4. Add the two server endpoints listed in ApiPaths
  //
  // The UI in login_screen.dart _DeviceConflictPanel already has the
  // "Switch via OTP" button wired up — it just needs these to be real.
  // ═══════════════════════════════════════════════════════════════════════════

  /// Request an OTP to switch this account to the current device.
  /// [phone] — the account's registered phone number.
  /// Calls POST /api/auth/device-switch/otp-request.
  /// Expected server response: { "ok": true }
  static Future<void> requestDeviceSwitchOtp({required String phone}) async {
    await _client.post(
      ApiPaths.deviceSwitchOtpRequest,
      data: {'phone': phone},
    );
  }

  /// Verify the OTP and bind the current device to the account.
  /// [phone] — the account's registered phone number.
  /// [otpCode] — the 6-digit code the user received via SMS.
  /// Calls POST /api/auth/device-switch/otp-verify.
  /// Expected server response: { "ok": true, "access_token": "...", "refresh_token": "..." }
  static Future<LoginResult> verifyDeviceSwitchOtp({
    required String phone,
    required String otpCode,
  }) async {
    final deviceId   = await DeviceIdentifier.getDeviceId();
    final deviceName = await DeviceIdentifier.getDeviceName();
    final resp = await _client.post(
      ApiPaths.deviceSwitchOtpVerify,
      data: {
        'phone':       phone,
        'otp_code':    otpCode,
        'device_id':   deviceId,
        'device_name': deviceName,
      },
    );
    return LoginResult.fromJson(resp.data as Map<String, dynamic>);
  }
}

class LoginResult {
  final String accessToken;
  final String refreshToken;
  final int userId;
  final String phone;

  const LoginResult({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.phone,
  });

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    final user = rawUser is Map<String, dynamic> ? rawUser : <String, dynamic>{};
    return LoginResult(
      accessToken: (json['access_token'] ?? '') as String,
      refreshToken: (json['refresh_token'] ?? '') as String,
      userId: json['user_id'] as int? ?? user['id'] as int? ?? 0,
      phone: json['phone'] as String? ?? user['phone'] as String? ?? '',
    );
  }
}
