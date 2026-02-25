import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // 팔레트 (Coolors) — 눈 피로감 최소화
  static const Color mint = Color(0xFFC2E7DA); // Frozen Water — 민트
  static const Color blue = Color(0xFF6290C3); // Dusty Denim — 블루
  static const Color navy = Color(0xFF1A1B41); // Space Indigo — 남색

  // 라이트 전용 색상
  static const Color _lightBg = Color(0xFFE8F0EC); // 민트 틴트 배경 (눈에 띄게)
  static const Color _lightSurface = Color(0xFFF7FAF8); // 카드: 약간 민트 흰색
  static const Color _lightBorder = Color(0xFFCBDDD3); // 민트 계열 테두리

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: Brightness.light,
      primary: blue,
      primaryContainer: mint,
      onPrimaryContainer: navy,
      surface: _lightSurface,
      surfaceContainerLow: const Color(0xFFDAEBE2), // 민트 틴트 (헤더/섹션)
      onSurface: navy,
      onSurfaceVariant: const Color(0xFF4A5568), // 부제/보조 텍스트
      outline: _lightBorder,
      outlineVariant: _lightBorder,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _lightBg,
      textTheme: GoogleFonts.notoSansKrTextTheme(),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: _lightBg,
        foregroundColor: navy,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: _lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _lightBorder),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          backgroundColor: blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          foregroundColor: blue,
          side: const BorderSide(color: blue),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: _lightBorder),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFEBF3EF),
        selectedColor: mint,
        side: const BorderSide(color: _lightBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: Brightness.dark,
      primary: blue,
      primaryContainer: navy,
      surface: const Color(0xFF121212),
      surfaceContainerLow: const Color(0xFF1A1B2E), // navy 계열 어두운 톤
      onSurfaceVariant: const Color(0xFF9CA3AF),
      outline: const Color(0xFF2D3748),
      outlineVariant: const Color(0xFF2D3748),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF121212),
      textTheme: GoogleFonts.notoSansKrTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2D3748)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          backgroundColor: blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          foregroundColor: mint,
          side: const BorderSide(color: blue),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF2D3748)),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF1A1B2E),
        selectedColor: navy,
        side: const BorderSide(color: Color(0xFF2D3748)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  // 상태 색상
  static const Color acceptedColor = Color(0xFF22C55E);
  static const Color rejectedColor = Color(0xFFDC2626);
  static const Color pendingColor = Color(0xFFF59E0B);
  static const Color evidenceColor = Color(0xFF6290C3);
}
