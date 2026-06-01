import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants.dart';
import 'theme_provider.dart';
import 'brand_theme_provider.dart';

class JazzThemeData {
  static ThemeData build(JazzTheme mode, [BrandThemeState? brand]) {
    final b      = brand ?? BrandThemeState.defaults;
    final isDark = mode != JazzTheme.light;

    final primary = b.primary;
    final accent  = b.accent;

    final Color bg;
    final Color surfaceColor;
    final Color cardColor;
    switch (mode) {
      case JazzTheme.amoled:
        bg          = AppColors.amoled;
        surfaceColor = AppColors.amoledSurface;
        cardColor   = AppColors.amoledCard;
        break;
      case JazzTheme.light:
        bg          = AppColors.lightBg;
        surfaceColor = AppColors.lightSurface;
        cardColor   = AppColors.lightCard;
        break;
      default:
        bg          = b.darkBackground;
        surfaceColor = b.darkSurface;
        cardColor   = b.darkCard;
    }

    final text  = isDark ? b.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = isDark ? AppColors.textMuted : AppColors.lightTextMuted;
    final br    = b.buttonRadius;

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor:                    Colors.transparent,
      statusBarIconBrightness:           isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor:          bg,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    ));

    final base      = isDark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
    final textTheme = _textTheme(b.fontFamily, base.textTheme, text);

    return base.copyWith(
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: ColorScheme(
        brightness:    isDark ? Brightness.dark : Brightness.light,
        primary:       primary,
        onPrimary:     Colors.white,
        secondary:     accent,
        onSecondary:   Colors.white,
        error:         AppColors.error,
        onError:       Colors.white,
        surface:       surfaceColor,
        onSurface:     text,
        background:    bg,
        onBackground:  text,
      ),
      scaffoldBackgroundColor: bg,
      textTheme:               textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor:         bg,
        elevation:               0,
        scrolledUnderElevation:  0,
        centerTitle:             false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor:          Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ),
        titleTextStyle: _style(b.fontFamily, color: text, size: 18,
            weight: FontWeight.w700, spacing: -0.3),
        iconTheme: IconThemeData(color: text),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor:     isDark ? surfaceColor : AppColors.lightSurface,
        selectedItemColor:   primary,
        unselectedItemColor: muted,
        type:                BottomNavigationBarType.fixed,
        elevation:           0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled:         true,
        fillColor:      isDark ? surfaceColor : AppColors.lightCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide:   BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(
            color: isDark ? AppColors.glassBorder : AppColors.lightBorder,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide:   BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide:   const BorderSide(color: AppColors.error, width: 1),
        ),
        labelStyle: TextStyle(color: muted, fontSize: 14),
        hintStyle:  TextStyle(color: muted, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.resolveWith((s) =>
              s.contains(MaterialState.disabled) ? primary.withOpacity(0.4) : primary),
          foregroundColor: MaterialStateProperty.all(Colors.white),
          overlayColor:    MaterialStateProperty.all(Colors.white10),
          minimumSize:     MaterialStateProperty.all(const Size(double.infinity, 52)),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(br)),
          ),
          elevation:  MaterialStateProperty.all(0),
          textStyle: MaterialStateProperty.all(
            _style(b.fontFamily, size: 15, weight: FontWeight.w600, spacing: 0.2),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: MaterialStateProperty.all(text),
          side: MaterialStateProperty.all(
            BorderSide(color: isDark ? AppColors.glassBorder : AppColors.lightBorder),
          ),
          minimumSize: MaterialStateProperty.all(const Size(double.infinity, 52)),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(br)),
          ),
          textStyle: MaterialStateProperty.all(
            _style(b.fontFamily, size: 15, weight: FontWeight.w500, spacing: 0),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      cardTheme: CardTheme(
        color:     isDark ? cardColor : AppColors.lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(
            color: isDark ? AppColors.cardBorder : AppColors.lightBorder,
            width: 0.5,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color:     isDark ? AppColors.divider : AppColors.dividerLight,
        thickness: 0.5,
        space:     0,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: isDark ? surfaceColor : AppColors.lightSurface,
        elevation:       24,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor:      isDark ? surfaceColor : AppColors.lightSurface,
        modalBackgroundColor: isDark ? surfaceColor : AppColors.lightSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:  isDark ? AppColors.surfaceHigh : Colors.grey[850],
        contentTextStyle: _style(b.fontFamily, color: Colors.white, size: 14,
            weight: FontWeight.normal, spacing: 0),
        shape:    RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((s) =>
            s.contains(MaterialState.selected) ? primary : Colors.white),
        trackColor: MaterialStateProperty.resolveWith((s) =>
            s.contains(MaterialState.selected)
                ? primary.withOpacity(0.4)
                : Colors.grey.withOpacity(0.2)),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateProperty.resolveWith((s) =>
            s.contains(MaterialState.selected) ? primary : Colors.transparent),
        side:  BorderSide(color: muted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }

  // ── Font helpers ─────────────────────────────────────────────────────────────
  static TextTheme _textTheme(String font, TextTheme base, Color textColor) {
    TextTheme t;
    switch (font.toLowerCase()) {
      case 'poppins': t = GoogleFonts.poppinsTextTheme(base); break;
      case 'roboto':  t = GoogleFonts.robotoTextTheme(base);  break;
      case 'nunito':  t = GoogleFonts.nunitoTextTheme(base);  break;
      case 'outfit':  t = GoogleFonts.outfitTextTheme(base);  break;
      default:        t = GoogleFonts.interTextTheme(base);   break;
    }
    return t.apply(bodyColor: textColor, displayColor: textColor);
  }

  static TextStyle _style(String font, {
    Color?      color,
    double      size    = 14,
    FontWeight  weight  = FontWeight.w400,
    double      spacing = 0,
  }) {
    final args = <String, dynamic>{
      'fontSize': size, 'fontWeight': weight, 'letterSpacing': spacing,
      if (color != null) 'color': color,
    };
    switch (font.toLowerCase()) {
      case 'poppins': return GoogleFonts.poppins(color: color, fontSize: size, fontWeight: weight, letterSpacing: spacing);
      case 'roboto':  return GoogleFonts.roboto( color: color, fontSize: size, fontWeight: weight, letterSpacing: spacing);
      case 'nunito':  return GoogleFonts.nunito( color: color, fontSize: size, fontWeight: weight, letterSpacing: spacing);
      case 'outfit':  return GoogleFonts.outfit( color: color, fontSize: size, fontWeight: weight, letterSpacing: spacing);
      default:        return GoogleFonts.inter(  color: color, fontSize: size, fontWeight: weight, letterSpacing: spacing);
    }
  }
}
