import 'package:flutter/material.dart';

/// Design tokens mirrored from `Telegram-cup-ui/styles.css`.
/// Single source of truth for colors / radii / shadows / text styles.
class T {
  T._();

  // ── brand ─────────────────────────────────────────────────────────
  static const brand = Color(0xFF2CD7FD);
  static const brand2 = Color(0xFF5FBDFD);
  static const brandDeep = Color(0xFF0BAFD9);
  static const brandSoft = Color(0x242CD7FD); // 14% alpha
  static const gold = Color(0xFFD9AB7A);
  static const gold2 = Color(0xFFF0C896);

  // ── semantic ──────────────────────────────────────────────────────
  static const up = Color(0xFF2BD475);
  static const upDark = Color(0xFF1FA85B);
  static const down = Color(0xFFE03E2D);
  static const warn = Color(0xFFF5B544);

  // ── ink (light theme text) ────────────────────────────────────────
  static const ink = Color(0xFF0E2238);
  static const inkMd = Color(0xFF4A5C77);
  static const inkLo = Color(0xFF8C9CB1);
  static const inkSubtle = Color(0xFFC5CFDB);

  // ── surface (light theme) ─────────────────────────────────────────
  static const surface = Color(0xFFFFFFFF);
  static const bgPage = Color(0xFFF4F8FC);
  static const bgPage2 = Color(0xFFE8F1FB);
  static const fill = Color(0xFFF4F8FC);
  static const border = Color(0x140E2238); // 0.08 alpha
  static const borderStrong = Color(0x240E2238); // 0.14 alpha

  // ── radii ─────────────────────────────────────────────────────────
  static const rXs = 6.0;
  static const rSm = 10.0;
  static const rMd = 14.0;
  static const rLg = 20.0;

  // ── shadows ───────────────────────────────────────────────────────
  static const shadowCard = [
    BoxShadow(
      color: Color(0x0A0E2238),
      blurRadius: 14,
      offset: Offset(0, 4),
    ),
  ];

  static const shadowSoft = [
    BoxShadow(
      color: Color(0x080E2238),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  static const shadowGlowBrand = [
    BoxShadow(
      color: Color(0x4D2CD7FD), // 30% alpha
      blurRadius: 16,
      offset: Offset(0, 6),
    ),
  ];

  // ── gradients ─────────────────────────────────────────────────────
  static const pageGradient = RadialGradient(
    center: Alignment.topCenter,
    radius: 1.4,
    colors: [Color(0xFFE8F4FF), Color(0xFFF4F8FC), Color(0xFFEEF2F7)],
    stops: [0.0, 0.5, 1.0],
  );

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE5F4FF), Color(0xFFDCEEFF), Color(0xFFFFF5E8)],
    stops: [0.0, 0.6, 1.0],
  );

  static const brandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF5FE5FE), Color(0xFF2CD7FD), Color(0xFF0BAFD9)],
    stops: [0.0, 0.5, 1.0],
  );

  static const brandGradientShort = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF2CD7FD), Color(0xFF0BAFD9)],
  );

  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFE9B5), Color(0xFFF5C656), Color(0xFFD9AB7A)],
    stops: [0.0, 0.6, 1.0],
  );

  // ── text styles ───────────────────────────────────────────────────
  static const _font = '-apple-system'; // ignored on non-web; iOS picks San Francisco
  static const fontMono = 'monospace';

  static const display = TextStyle(
    fontFamily: _font, fontSize: 28, fontWeight: FontWeight.w700,
    height: 1.15, letterSpacing: -0.3, color: ink,
  );
  static const h1 = TextStyle(
    fontFamily: _font, fontSize: 22, fontWeight: FontWeight.w700,
    height: 1.2, letterSpacing: -0.2, color: ink,
  );
  static const h2 = TextStyle(
    fontFamily: _font, fontSize: 18, fontWeight: FontWeight.w600,
    height: 1.25, color: ink,
  );
  static const body = TextStyle(
    fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w400,
    height: 1.45, color: ink,
  );
  static const bodyMd = TextStyle(
    fontFamily: _font, fontSize: 14, fontWeight: FontWeight.w500,
    height: 1.45, color: ink,
  );
  static const cap = TextStyle(
    fontFamily: _font, fontSize: 12, fontWeight: FontWeight.w500,
    height: 1.3, letterSpacing: 0.2, color: inkMd,
  );
  static const micro = TextStyle(
    fontFamily: _font, fontSize: 11, fontWeight: FontWeight.w500,
    height: 1.2, letterSpacing: 0.4, color: inkLo,
  );
  static const tnum = TextStyle(
    fontFamily: fontMono, fontFeatures: [FontFeature.tabularFigures()],
    fontWeight: FontWeight.w700, color: ink,
  );

  // ── ThemeData ─────────────────────────────────────────────────────
  static ThemeData lightTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.light,
      primary: brandDeep,
      secondary: gold,
      surface: surface,
      error: down,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bgPage,
      textTheme: Typography.englishLike2021.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      splashFactory: InkRipple.splashFactory,
      sliderTheme: const SliderThemeData(
        activeTrackColor: brand,
        thumbColor: brand,
        overlayColor: brandSoft,
        inactiveTrackColor: Color(0xFFEEF2F7),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: ink,
        titleTextStyle: TextStyle(
            color: ink, fontSize: 15, fontWeight: FontWeight.w800),
        iconTheme: IconThemeData(color: ink),
      ),
    );
  }
}
