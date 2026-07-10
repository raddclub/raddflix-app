import 'package:flutter/material.dart';

class AppConstants {
  static const String appName = 'RaddFlix';
  static const String tagline = 'Pakistan ka entertainment, data-free';

  /// Runtime-mutable: updated by RemoteConfig.fetch() on every app start.
  static String apiBaseUrl = 'http://92.4.95.252';


  static const Duration accessTokenValidity = Duration(days: 7);
  static const Duration refreshTokenValidity = Duration(days: 90);

  static const Duration catalogSyncInterval = Duration(hours: 6);
  static const String catalogDbName = 'raddflix_catalog.db';
  static const int catalogDbVersion = 21;
  static const int streamCacheTtlSeconds = 6600; // 110 min

  // ── JazzDrive (zero-rated CDN) ─────────────────────────────────────────────
  static const String jazzDriveCloudBase = 'https://cloud.jazzdrive.com.pk';

  /// Zero-rated delta.json URL — 24h rolling window, full playback data.
  /// Updated by RemoteConfig.fetch() from /api/config on every startup.
  /// Cached in SharedPreferences so it survives offline restarts.
  /// Empty = JazzDrive delta disabled (Oracle-only sync).
  /// Must be a mutable static field (not a getter) — RemoteConfig writes to it.
  static String jazzDriveDeltaUrl = '';

  /// Legacy: full db_update.json URL — Oracle-only, never public JazzDrive.
  static String get jazzDriveDbUpdateUrl => '\$apiBaseUrl/api/catalog/db_update';

  /// Stream link cache TTL. Same link reused for both watch + download within TTL.
  static const Duration streamLinkTtl = Duration(minutes: 110); // 110 min — matches jazzdrive_service.dart _cacheTtl

  // ── Support ──────────────────────────────────────────────────────────────
  /// WhatsApp support number (international format, no +, no spaces).
  static String supportWhatsApp = '923257719165';

  // ── Device Switch / OTP Hook ─────────────────────────────────────────────
  /// Controls self-serve device switching via OTP (6-digit code via WhatsApp).
  ///
  /// When true (current): user can request a device-switch code from the app.
  /// When false: UI shows WhatsApp-only contact support for device switches.
  ///
  /// Server endpoints are live:
  ///   POST /api/auth/device-switch/request  — sends OTP to registered phone
  ///   POST /api/auth/device-switch/verify   — verifies OTP, rebinds device
  ///
  /// To disable OTP switch (admin-only enforcement):
  ///   Set this to false and rebuild.
  static const bool otpDeviceSwitchEnabled = true;

  // ── SIMOSA (Phase 9) ─────────────────────────────────────────────────────
  /// Play Store URL for the SIMOSA app (Jazz daily free MB offer).
  static const String simosaPlayStoreUrl =
      'https://play.google.com/store/apps/details?id=com.jazz.world';

  /// Deep-link / app package for intent-based launch (Android).
  static const String simosaAppPackage = 'com.jazz.world';

  /// Daily free data in MB offered via SIMOSA.
  static const int simosaDailyMb = 100;
}

// ── Brand Colors ─────────────────────────────────────────────────────────────
class AppColors {
  // Primary brand
  static const Color primary       = Color(0xFFE8002D);
  static const Color primaryDark   = Color(0xFFB5001F);
  static const Color primaryGlow   = Color(0x40E8002D);
  static const Color primaryLight  = Color(0xFFFF4D6A);

  // Backgrounds (Dark theme)
  static const Color background    = Color(0xFF08080E);
  static const Color backgroundAlt = Color(0xFF0D0D1A);
  static const Color surface       = Color(0xFF0E0E1C);
  static const Color surfaceHigh   = Color(0xFF161628);
  static const Color card          = Color(0xFF1A1A2E);
  static const Color cardBorder    = Color(0xFF252540);

  // Glassmorphism
  static const Color glass         = Color(0x0DFFFFFF);
  static const Color glassBorder   = Color(0x14FFFFFF);
  static const Color glassHigh     = Color(0x1AFFFFFF);

  // AMOLED backgrounds
  static const Color amoled        = Color(0xFF000000);
  static const Color amoledSurface = Color(0xFF0A0A0A);
  static const Color amoledCard    = Color(0xFF111111);

  // Light theme
  static const Color lightBg       = Color(0xFFF0F0F7);
  static const Color lightSurface  = Color(0xFFFFFFFF);
  static const Color lightCard     = Color(0xFFF5F5FA);
  static const Color lightBorder   = Color(0xFFE0E0EC);

  // Text
  static const Color textPrimary   = Color(0xFFF2F2FF);
  static const Color textSecondary = Color(0xFFB0B0CC);
  static const Color textMuted     = Color(0xFF6A6A90);
  static const Color textDisabled  = Color(0xFF404060);

  // Text (light mode)
  static const Color lightTextPrimary   = Color(0xFF0A0A1A);
  static const Color lightTextSecondary = Color(0xFF444466);
  static const Color lightTextMuted     = Color(0xFF888899);

  // Shorthand aliases
  static const Color text      = textPrimary;
  static const Color border    = glassBorder;

  // Status
  static const Color success       = Color(0xFF22C55E);
  static const Color successGlow   = Color(0x2222C55E);
  static const Color error         = Color(0xFFEF4444);
  static const Color errorGlow     = Color(0x22EF4444);
  static const Color warning       = Color(0xFFF59E0B);
  static const Color warningGlow   = Color(0x22F59E0B);
  static const Color info          = Color(0xFF3B82F6);
  static const Color accent        = Color(0xFF3B82F6); // alias for info, used in year filter chips

  // Divider
  static const Color divider       = Color(0xFF1E1E35);
  static const Color dividerLight  = Color(0xFFE0E0F0);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFE8002D), Color(0xFFFF5C5C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [Color(0xFF08080E), Color(0xFF0D0D22)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Colors.transparent, Color(0xFF08080E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.3, 1.0],
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF161628), Color(0xFF0E0E1C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Brand / Partner colors ─────────────────────────────────────────────────
  static const Color warningDark    = Color(0xFFB45309); // dark amber — device conflict warning
  static const Color jazzGreen      = Color(0xFF00A651); // JazzCash brand green
  static const Color jazzGreenDark  = Color(0xFF006633); // JazzCash dark green
  static const Color orange         = Color(0xFFFF9800); // upload badge / burn indicator
  static const Color simosaAccent   = Color(0xFF7C5CFF); // Simosa card purple accent
  static const Color simosaBgDark   = Color(0xFF1A0A2E); // Simosa dark bg gradient start
  static const Color simosaBgDark2  = Color(0xFF2D1B5E); // Simosa dark bg gradient end
  static const Color simosaBgLight  = Color(0xFFEDE7FF); // Simosa light bg gradient start
  static const Color simosaBgLight2 = Color(0xFFD8C8FF); // Simosa light bg gradient end

  // ── Layout designer ────────────────────────────────────────────────────────
  static const Color layoutDeep     = Color(0xFF0D0D1A); // Layout designer scaffold bg
  static const Color layoutPanel    = Color(0xFF12121E); // Layout designer header/footer panel
  static const Color layoutSheet    = Color(0xFF1E1E2E); // Layout designer bottom sheet

  // ── Semantic — Volume II (accent.dataFree, protected color) ────────────────
  /// Reserved EXCLUSIVELY for zero-rated/data-free indicators. Never use for
  /// success, online, active, or downloaded states — see Volume I, Protected
  /// Colors, and `AI_RULES.md` rule 7.
  static const Color dataFree = Color(0xFF3DDC97);
}

// ── Shadows ───────────────────────────────────────────────────────────────────
class AppShadows {
  static List<BoxShadow> get primary => [
    BoxShadow(
      color: AppColors.primary.withOpacity(0.3),
      blurRadius: 20,
      spreadRadius: -4,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get card => [
    BoxShadow(
      color: Colors.black.withOpacity(0.4),
      blurRadius: 24,
      spreadRadius: -8,
      offset: const Offset(0, 12),
    ),
    BoxShadow(
      color: AppColors.primary.withOpacity(0.05),
      blurRadius: 40,
      spreadRadius: -10,
    ),
  ];

  static List<BoxShadow> get soft => [
    BoxShadow(
      color: Colors.black.withOpacity(0.2),
      blurRadius: 16,
      spreadRadius: -4,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get glow => [
    BoxShadow(
      color: AppColors.primary.withOpacity(0.4),
      blurRadius: 30,
      spreadRadius: -5,
    ),
  ];

  static List<BoxShadow> get elevated => [
    BoxShadow(
      color: Colors.black.withOpacity(0.6),
      blurRadius: 40,
      spreadRadius: -10,
      offset: const Offset(0, 20),
    ),
  ];
}

// ── Durations ─────────────────────────────────────────────────────────────────
class AppDurations {
  static const Duration fast   = Duration(milliseconds: 100);
  static const Duration normal = Duration(milliseconds: 180);
  static const Duration slow   = Duration(milliseconds: 280);
  static const Duration xslow  = Duration(milliseconds: 420);
}

// ── Curves ────────────────────────────────────────────────────────────────────
class AppCurves {
  // Legacy — kept for backwards compatibility
  static const Curve standard = Curves.easeOutCubic;
  static const Curve enter    = Curves.easeOutExpo;
  static const Curve exit     = Curves.easeInQuart;
  static const Curve spring   = Curves.easeOutBack;
  static const Curve bounce   = Curves.bounceOut;
  static const Curve snap     = Curves.easeOutCirc;

  // M3 Expressive (2026) — two-mode motion system
  // Spatial: physical objects that move through space (nav indicator, cards, panels)
  static const Curve expressiveSpring = Curves.easeOutBack;
  // Effect: value changes — opacity, color, scale-in-place (no overshoot)
  static const Curve expressiveEffect = Curves.easeOutCubic;
  // Exit: elements leaving the screen
  static const Curve expressiveExit   = Curves.easeInCubic;
}

// ── Gradients ─────────────────────────────────────────────────────────────────
class AppGradients {
  // Brand — primary action buttons, active indicators
  static const LinearGradient brand = LinearGradient(
    colors: [Color(0xFFE8002D), Color(0xFFFF5C5C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Nav capsule — transparent tinted background behind active nav item
  static const LinearGradient navCapsule = LinearGradient(
    colors: [Color(0x2AE8002D), Color(0x15FF5C5C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Hero overlay — fades content to background at bottom of cards
  static const LinearGradient hero = LinearGradient(
    colors: [Colors.transparent, Color(0xFF08080E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.3, 1.0],
  );

  // Dark background — scaffold/screen backgrounds
  static const LinearGradient dark = LinearGradient(
    colors: [Color(0xFF08080E), Color(0xFF0D0D22)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Card surface — elevated card backgrounds
  static const LinearGradient card = LinearGradient(
    colors: [Color(0xFF161628), Color(0xFF0E0E1C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Atmospheric — radial accent glow behind featured content
  static LinearGradient atmospheric(Color accent) => LinearGradient(
    colors: [accent.withOpacity(0.14), Colors.transparent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Status gradients
  static const LinearGradient success = LinearGradient(
    colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient premium = LinearGradient(
    colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient simosa = LinearGradient(
    colors: [Color(0xFF1A0A2E), Color(0xFF2D1B5E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// ── Border Radius ─────────────────────────────────────────────────────────────
class AppRadius {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double round = 100;

  static BorderRadius get xs_r  => BorderRadius.circular(xs);
  static BorderRadius get sm_r  => BorderRadius.circular(sm);
  static BorderRadius get md_r  => BorderRadius.circular(md);
  static BorderRadius get lg_r  => BorderRadius.circular(lg);
  static BorderRadius get xl_r  => BorderRadius.circular(xl);
}

// ── Routes ────────────────────────────────────────────────────────────────────
class AppRoutes {
  static const String splash       = '/';
  static const String login        = '/login';
  static const String register     = '/register';
  static const String home         = '/home';
  static const String search       = '/search';
  static const String player       = '/player';
  static const String subscription = '/subscription';
  static const String profile      = '/profile';
  static const String downloads    = '/downloads';
  static const String localMedia   = '/local-media';
  static const String watchlist    = '/watchlist';
  static const String history      = '/history';
  static const String vault        = '/vault';
  static const String vaultLock    = '/vault-lock';
  static const String showDetail   = '/show-detail';
  static const String quotaFull    = '/quota-full';
  static const String planExpired  = '/plan-expired';
  static const String settings     = '/settings';
  static const String profileSwitcher = '/profile-switcher';
  static const String addProfile      = '/add-profile';
  static const String editProfile     = '/edit-profile';
}

// ── Storage Keys ──────────────────────────────────────────────────────────────
class StorageKeys {
  static const String accessToken      = 'jm_access_token';
  static const String refreshToken     = 'jm_refresh_token';
  static const String userId           = 'jm_user_id';
  static const String deviceId         = 'jm_device_id';
  static const String isGuest          = 'jm_is_guest';
  static const String cachedUserPhone  = 'jm_cached_phone';
  static const String cachedUserId     = 'jm_cached_user_id';
  static const String cachedUserPlan   = 'jm_cached_plan';
  static const String cachedSubExpiry  = 'jm_cached_sub_expiry';
  static const String themeMode        = 'jm_theme_mode';
  static const String searchHistory    = 'jm_search_history';
  static const String subtitleDefault  = 'jm_subtitle_default';
  static const String activeProfileId  = 'jm_active_profile_id';
}

// ── API Paths ─────────────────────────────────────────────────────────────────
class ApiPaths {
  static const String register          = '/api/auth/register';
  static const String login             = '/api/auth/login';
  static const String guest             = '/api/auth/guest';
  static const String refresh           = '/api/auth/refresh';
  static const String logout            = '/api/auth/logout';
  static const String me                = '/api/auth/me';
  static const String bindDevice        = '/api/auth/device';
  static const String updateProfile     = '/api/auth/profile';
  static const String changePassword    = '/api/auth/change-password';

  // ── OTP Device Switch (future — wire when otpDeviceSwitchEnabled = true) ──
  // POST body: { phone } → server sends OTP to the phone
  static const String deviceSwitchOtpRequest = '/api/auth/device-switch/request';
  // POST body: { phone, otp_code } → server unbinds old device, binds new one
  static const String deviceSwitchOtpVerify  = '/api/auth/device-switch/verify';

  static const String catalogVersion    = '/api/catalog/version';
  static const String catalogSync       = '/api/catalog/sync';

  static const String plans             = '/api/subscription/plans';
  static const String subscriptionStatus= '/api/subscription/status';
  static const String tidSubmit         = '/api/subscription/tid/submit';
  static const String tidStatus         = '/api/subscription/tid/status';

  static const String historyBase       = '/api/history';
  static String saveHistory(String fileId) => '/api/history/$fileId';
  static String playUrl(String fileId)    => '/watch/api/play/$fileId';
  static String fileShareUrl(String fileId) => '/api/catalog/share_url?file_id=${fileId}';
  static const String publicMethods      = '/api/payment-methods';

  static const String notifications      = '/api/notifications/';
  static const String notificationsRead  = '/api/notifications/read';
  static String notificationImage(int id) => '/api/notifications/image/$id';

  // ── Recommendations (radd_recommend engine) ─────────────────────────────
  static const String recommend = '/api/recommend';

  // ── Phase 6: Data Usage ───────────────────────────────────────────────
  static const String usage  = '/api/usage';
  static const String quota  = '/api/usage/quota';

}