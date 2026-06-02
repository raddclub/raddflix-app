import 'dart:convert';
import 'package:dio/dio.dart' hide RequestEncoder;
import '../constants.dart';
import '../security/keystore.dart';
import '../security/app_guard.dart';
import '../security/request_encoder.dart';
import '../security/device_id.dart';
import '../debug/debug_logger.dart';

/// Singleton Dio HTTP client.
/// Automatically attaches Bearer token to every request.
/// On 401 → auto-refreshes access token using refresh token → retries.
/// On refresh failure → clears tokens (user must log in again).
///
/// Security: if AppGuard.isTampered is true (cracked APK / Frida detected),
/// the _TamperInterceptor short-circuits ALL requests with fake empty responses.
/// The attacker sees empty catalog / failed login — never real data.
///
/// XOR encoding: _XorInterceptor encodes request bodies and decodes responses
/// using an hourly rotating session key derived from device ID + time.
class ApiClient {
  static ApiClient? _instance;
  late final Dio _dio;

  ApiClient._() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // Order matters:
    // 1. Tamper check: block cracked APKs before any network activity
    // 2. Logging: log original (pre-encoding) data for debug readability
    // 3. Auth: attach Bearer token
    // 4. XOR: encode outbound body, decode inbound response (last for requests, first for responses)
    _dio.interceptors.add(_TamperInterceptor());
    _dio.interceptors.add(_LoggingInterceptor());
    _dio.interceptors.add(_AuthInterceptor(_dio));
    _dio.interceptors.add(_XorInterceptor());
  }

  static ApiClient get instance {
    _instance ??= ApiClient._();
    return _instance!;
  }

  /// Set to true when the current session is an offline-first guest.
  /// When true, 401 responses do NOT trigger logout — guests rely on
  /// zero-rated JazzDrive delta for catalog and have no refresh token.
  static bool isGuestMode = false;

  /// Call this after RemoteConfig.fetch() to point Dio at the new server URL.
  static void updateBaseUrl(String url) {
    _instance ??= ApiClient._();
    _instance!._dio.options.baseUrl = url;
  }

  Dio get dio => _dio;

  // ── Convenience methods ───────────────────────────────────────────────────

  Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      _dio.get(path, queryParameters: params);

  Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> put(String path, {dynamic data}) =>
      _dio.put(path, data: data);
}

// ── Tamper Interceptor ────────────────────────────────────────────────────────
/// Security: blocks ALL API calls when AppGuard.isTampered = true.
///
/// Returns a fake 200 response with empty data instead of making a real call.
/// This implements "silent degradation":
///   - Cracked APK sees empty catalog, login always "fails" silently
///   - Attacker thinks the crack doesn't work and gives up
///   - We never crash or show an error that reveals the check exists
///
/// Runs BEFORE _LoggingInterceptor so tampered requests don't appear in logs.
class _TamperInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!AppGuard.isTampered) {
      return handler.next(options);
    }
    // Return fake empty response — never hits the real network
    final fake = Response(
      requestOptions: options,
      statusCode: 200,
      data: _fakeResponse(options.path),
    );
    handler.resolve(fake);
  }

  /// Generate a plausible-looking fake response for common API paths.
  static dynamic _fakeResponse(String path) {
    if (path.contains('/catalog/sync') || path.contains('/catalog/version')) {
      return {'items': [], 'version': 0, 'count': 0};
    }
    if (path.contains('/auth/login') || path.contains('/auth/register')) {
      return {'ok': false, 'error': 'Invalid credentials'};
    }
    if (path.contains('/subscription/plans')) {
      return {'plans': []};
    }
    if (path.contains('/notifications')) {
      return {'notifications': []};
    }
    return {'ok': false};
  }
}

// ── Logging Interceptor ───────────────────────────────────────────────────────
/// Records every HTTP request and response to the debug log file.
class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['_req_start_ms'] = DateTime.now().millisecondsSinceEpoch;
    final bodyPreview = options.data != null
        ? options.data.toString().length > 200
            ? options.data.toString().substring(0, 200) + '…'
            : options.data.toString()
        : null;
    DebugLogger.logApi(
      method: options.method,
      url: '${options.baseUrl}${options.path}',
      requestBody: bodyPreview,
    );
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final start =
        response.requestOptions.extra['_req_start_ms'] as int? ?? 0;
    final dur =
        start > 0 ? DateTime.now().millisecondsSinceEpoch - start : null;
    final rawBody = response.data?.toString() ?? '';
    DebugLogger.logApi(
      method: response.requestOptions.method,
      url:
          '${response.requestOptions.baseUrl}${response.requestOptions.path}',
      statusCode: response.statusCode,
      responsePreview: rawBody,
      durationMs: dur,
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final start = err.requestOptions.extra['_req_start_ms'] as int? ?? 0;
    final dur =
        start > 0 ? DateTime.now().millisecondsSinceEpoch - start : null;
    final respBody = err.response?.data?.toString() ?? '';
    final respPreview = respBody.length > 300
        ? respBody.substring(0, 300) + '…'
        : respBody;
    DebugLogger.logApi(
      method: err.requestOptions.method,
      url:
          '${err.requestOptions.baseUrl}${err.requestOptions.path}',
      error:
          '${err.type.name}: ${err.message}  HTTP ${err.response?.statusCode}  Body: $respPreview',
      durationMs: dur,
    );
    handler.next(err);
  }
}

/// Interceptor: attaches auth header + handles 401 token refresh.
class _AuthInterceptor extends Interceptor {
  final Dio _dio;
  bool _isRefreshing = false;

  _AuthInterceptor(this._dio);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Skip auth header for auth endpoints
    final noAuthPaths = [ApiPaths.login, ApiPaths.register, ApiPaths.refresh, ApiPaths.guest];
    if (noAuthPaths.contains(options.path)) {
      return handler.next(options);
    }

    final token = await Keystore.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
      DebugLogger.log('AUTH', 'Attaching Bearer token to ${options.path}');
    } else {
      DebugLogger.logWarn('AUTH', 'No access token for ${options.path}');
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Never attempt token refresh for auth endpoints — a 401 there means bad credentials
    final _noRefreshPaths = [ApiPaths.login, ApiPaths.register, ApiPaths.refresh, ApiPaths.guest];
    if (err.response?.statusCode == 401 && !_isRefreshing && !_noRefreshPaths.contains(err.requestOptions.path)) {
      DebugLogger.logWarn('AUTH', '401 received on ${err.requestOptions.path} — attempting token refresh');
      _isRefreshing = true;
      try {
        final refreshed = await _tryRefresh();
        if (refreshed) {
          // Retry the original request with new token
          final newToken = await Keystore.getAccessToken();
          final opts = err.requestOptions;
          opts.headers['Authorization'] = 'Bearer $newToken';
          DebugLogger.log('AUTH', 'Token refreshed — retrying ${opts.path}');
          final response = await _dio.fetch(opts);
          _isRefreshing = false;
          return handler.resolve(response);
        }
      } catch (e) {
        DebugLogger.logError('AUTH', 'Token refresh threw exception', e);
      }
      _isRefreshing = false;
      if (ApiClient.isGuestMode) {
        // Guest mode: never log out on 401 — guest identity is local-only.
        // They will continue using zero-rated JazzDrive delta catalog offline.
        DebugLogger.logWarn('AUTH', 'Guest 401 — staying authenticated (offline guest)');
        return handler.next(err);
      }
      DebugLogger.logError('AUTH', 'Refresh failed — clearing tokens, user must log in');
      // Refresh failed — clear tokens so app goes to login
      await Keystore.clearAll();
    }
    handler.next(err);
  }

  Future<bool> _tryRefresh() async {
    final refreshToken = await Keystore.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      // Guest mode: no refresh token — re-issue a fresh guest token instead of logging out
      try {
        final freshDio = Dio(BaseOptions(baseUrl: AppConstants.apiBaseUrl));
        final guestResp = await freshDio.post(ApiPaths.guest);
        if (guestResp.statusCode == 200) {
          final gData = guestResp.data as Map<String, dynamic>? ?? {};
          final newToken = gData['access_token'] as String?;
          if (newToken != null && newToken.isNotEmpty) {
            await Keystore.saveAccessToken(newToken);
            DebugLogger.log('AUTH', 'Guest token re-issued after 401 (token expired)');
            return true;
          }
        }
      } catch (e) {
        DebugLogger.logWarn('AUTH', 'Guest token re-issue failed: $e');
      }
      DebugLogger.logWarn('AUTH', 'No refresh token — cannot refresh session');
      return false;
    }

    try {
      // Use a fresh Dio instance (no interceptors) to avoid infinite loop
      final freshDio = Dio(BaseOptions(baseUrl: AppConstants.apiBaseUrl));
      final response = await freshDio.post(
        ApiPaths.refresh,
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final newAccess = data['access_token'] as String?;
        final newRefresh = data['refresh_token'] as String?;
        if (newAccess != null) {
          await Keystore.saveAccessToken(newAccess);
          if (newRefresh != null && newRefresh.isNotEmpty) {
            await Keystore.saveRefreshToken(newRefresh);
          }
          DebugLogger.log('AUTH', 'Token refresh successful');
          return true;
        }
      }
    } catch (e) {
      DebugLogger.logError('AUTH', '_tryRefresh network error', e);
    }
    return false;
  }
}

// ── XOR Interceptor ───────────────────────────────────────────────────────────
/// Adds XOR obfuscation layer on top of HTTPS for all Oracle API traffic.
///
/// Request: encodes POST/PUT/PATCH body with hourly session key.
///   Adds X-Encoded: 1 and X-Device-Id headers so server can decode.
/// Response: decodes application/octet-stream responses from server.
///
/// Only active when RequestEncoder.enabled == true.
/// Runs last for requests (encodes after auth) and first for responses (decodes first).
///
/// See: lib/core/security/request_encoder.dart for encoding details.
class _XorInterceptor extends Interceptor {
  String? _cachedDeviceId;

  Future<String> _getDeviceId() async {
    _cachedDeviceId ??= await DeviceIdentifier.getDeviceId();
    return _cachedDeviceId!;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!RequestEncoder.enabled) return handler.next(options);

    try {
      final deviceId   = await _getDeviceId();
      final sessionKey = RequestEncoder.generateSessionKey(deviceId);

      // Mark all requests as XOR-capable so server can encode responses
      options.headers['X-Encoded']   = '1';
      options.headers['X-Device-Id'] = deviceId;

      // Encode request body for write methods only
      final method = options.method.toUpperCase();
      if (options.data != null && (method == 'POST' || method == 'PUT' || method == 'PATCH')) {
        final jsonBody = options.data is String
            ? options.data as String
            : jsonEncode(options.data);
        final encoded = RequestEncoder.encode(jsonBody, sessionKey);
        options.data        = encoded;
        options.contentType = 'text/plain; charset=utf-8';
        DebugLogger.log('XOR', 'Encoded request body for ${options.path}');
      }

      // Store session key for response decoding
      options.extra['_xor_session_key'] = sessionKey;
    } catch (e) {
      DebugLogger.logWarn('XOR', 'Encoding error for ${options.path}: $e');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (!RequestEncoder.enabled) return handler.next(response);

    try {
      final sessionKey =
          response.requestOptions.extra['_xor_session_key'] as String?;
      if (sessionKey != null) {
        final contentType = response.headers.value('content-type') ?? '';
        if (contentType.contains('octet-stream')) {
          final rawData = response.data?.toString() ?? '';
          if (rawData.isNotEmpty) {
            final decoded = RequestEncoder.decode(rawData, sessionKey);
            try {
              response.data = jsonDecode(decoded);
              DebugLogger.log('XOR', 'Decoded response for ${response.requestOptions.path}');
            } catch (_) {
              response.data = decoded;
            }
          }
        }
      }
    } catch (e) {
      DebugLogger.logWarn('XOR', 'Decode error: $e');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (!RequestEncoder.enabled) return handler.next(err);

    // Decode XOR-encoded error response body so DioException handlers can read it
    try {
      final sessionKey = err.requestOptions.extra['_xor_session_key'] as String?;
      if (sessionKey != null && err.response != null) {
        final contentType = err.response!.headers.value('content-type') ?? '';
        if (contentType.contains('octet-stream')) {
          final rawData = err.response!.data?.toString() ?? '';
          if (rawData.isNotEmpty) {
            final decoded = RequestEncoder.decode(rawData, sessionKey);
            try {
              err.response!.data = jsonDecode(decoded);
              DebugLogger.log('XOR', 'Decoded error body for ${err.requestOptions.path}');
            } catch (_) {
              err.response!.data = decoded;
            }
          }
        }
      }
    } catch (e) {
      DebugLogger.logWarn('XOR', 'Error body decode failed: $e');
    }
    handler.next(err);
  }
}
