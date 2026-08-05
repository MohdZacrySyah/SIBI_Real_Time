import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Palet Warna Utama
  static const Color spaceDark = Color(0xFF090D16);
  static const Color surfaceDark = Color(0xFF131B2E);
  static const Color glassCard = Color(0x3F1A233D);
  static const Color glassBorder = Color(0x2294A3B8);

  static const Color electricIndigo = Color(0xFF6366F1);
  static const Color electricCyan = Color(0xFF06B6D4);
  static const Color neonPurple = Color(0xFFD946EF);
  
  static const Color successEmerald = Color(0xFF10B981);
  static const Color warningAmber = Color(0xFFF59E0B);
  static const Color dangerRose = Color(0xFFF43F5E);

  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Palet Warna Terang (Sesuai Mockup)
  static const Color primaryGreen = Color(0xFF004D25); // Hijau Gelap SIBI
  static const Color bgLightSidebar = Color(0xFFE2E8F0);
  static const Color bgLightContent = Color(0xFFF8FAFC);
  static const Color textLightPrimary = Color(0xFF1E293B);
  static const Color textLightSecondary = Color(0xFF475569);
  static const Color surfaceLight = Colors.white;

  // Gradient Backgrounds
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [electricIndigo, electricCyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [neonPurple, electricIndigo],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkBackgroundGradient = LinearGradient(
    colors: [spaceDark, Color(0xFF060910)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Glassmorphic Decoration
  static BoxDecoration glassDecoration({
    double blur = 16.0,
    double borderRadius = 20.0,
    Color color = glassCard,
    Color borderColor = glassBorder,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: borderColor, width: 1.0),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  // ThemeData Konfigurasi
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: electricIndigo,
      scaffoldBackgroundColor: spaceDark,
      cardColor: surfaceDark,
      fontFamily: GoogleFonts.outfit().fontFamily,
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).copyWith(
        displayLarge: GoogleFonts.outfit(
          color: textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        titleLarge: GoogleFonts.outfit(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: GoogleFonts.outfit(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.normal,
        ),
        bodyMedium: GoogleFonts.outfit(
          color: textSecondary,
          fontSize: 14,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: textPrimary,
          backgroundColor: electricIndigo,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: primaryGreen,
      scaffoldBackgroundColor: bgLightContent,
      cardColor: surfaceLight,
      fontFamily: GoogleFonts.outfit().fontFamily,
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme).copyWith(
        displayLarge: GoogleFonts.outfit(
          color: textLightPrimary,
          fontSize: 32,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        titleLarge: GoogleFonts.outfit(
          color: textLightPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: GoogleFonts.outfit(
          color: textLightPrimary,
          fontSize: 16,
          fontWeight: FontWeight.normal,
        ),
        bodyMedium: GoogleFonts.outfit(
          color: textLightSecondary,
          fontSize: 14,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textLightPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: primaryGreen,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textLightSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          side: const BorderSide(color: Color(0xFFCBD5E1)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
