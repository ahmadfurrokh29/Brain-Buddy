import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand colours from the project plan.
class BB {
  static const mint = Color(0xFF2EC4A6);
  static const mintDark = Color(0xFF1A9C83);
  static const mintLight = Color(0xFFE3F8F3);
  static const coral = Color(0xFFFF6B6B);
  static const coralLight = Color(0xFFFFECEC);
  static const sun = Color(0xFFFFD166);
  static const sunLight = Color(0xFFFFF6DD);
  static const ink = Color(0xFF1B2430);
  static const grey = Color(0xFF5B6573);
  static const cloud = Color(0xFFF7F9FC);
  static const night = Color(0xFF121826);
  static const nightCard = Color(0xFF1C2433);
  static const brainPink = Color(0xFFFF9EB5);
  static const brainPinkDark = Color(0xFFE0688A);
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: BB.mint,
      brightness: b,
      primary: BB.mint,
      secondary: BB.sun,
      error: BB.coral,
      surface: dark ? BB.nightCard : Colors.white,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
    final body = GoogleFonts.nunitoTextTheme(base.textTheme);
    final text = body.copyWith(
      displayLarge: GoogleFonts.fredoka(textStyle: body.displayLarge, fontWeight: FontWeight.w600),
      displayMedium: GoogleFonts.fredoka(textStyle: body.displayMedium, fontWeight: FontWeight.w600),
      displaySmall: GoogleFonts.fredoka(textStyle: body.displaySmall, fontWeight: FontWeight.w600),
      headlineLarge: GoogleFonts.fredoka(textStyle: body.headlineLarge, fontWeight: FontWeight.w600),
      headlineMedium: GoogleFonts.fredoka(textStyle: body.headlineMedium, fontWeight: FontWeight.w600),
      headlineSmall: GoogleFonts.fredoka(textStyle: body.headlineSmall, fontWeight: FontWeight.w600),
      titleLarge: GoogleFonts.fredoka(textStyle: body.titleLarge, fontWeight: FontWeight.w600),
    ).apply(
      bodyColor: dark ? Colors.white : BB.ink,
      displayColor: dark ? Colors.white : BB.ink,
    );
    return base.copyWith(
      scaffoldBackgroundColor: dark ? BB.night : BB.cloud,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        foregroundColor: dark ? Colors.white : BB.ink,
      ),
      cardTheme: CardThemeData(
        color: dark ? BB.nightCard : Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BB.mint,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.nunito(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: dark ? Colors.white : BB.ink,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: dark ? Colors.white24 : const Color(0xFFDDE3EA)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.nunito(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? BB.mint : null),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? BB.nightCard : Colors.white,
        indicatorColor: BB.mintLight,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700)),
      ),
      dividerTheme: DividerThemeData(color: dark ? Colors.white12 : const Color(0xFFEDF1F5), space: 1),
    );
  }
}
