/// TermuxForge — Material You Theme Configuration
///
/// Provides [darkTheme] and [lightTheme] with carefully tuned color
/// schemes, typography, and component styles that create a premium
/// IDE-grade visual experience.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:nexon/core/theme/app_colors.dart';

/// Application-wide theme factory.
abstract final class AppTheme {
  // ──────────────────────────────────────────────
  //  Typography
  // ──────────────────────────────────────────────

  /// UI text style — Inter.
  static TextTheme _buildTextTheme(Brightness brightness) {
    final base = GoogleFonts.interTextTheme();
    final color = brightness == Brightness.dark
        ? AppColors.textPrimary
        : AppColors.textPrimaryLight;
    final secondaryColor = brightness == Brightness.dark
        ? AppColors.textSecondary
        : AppColors.textSecondaryLight;

    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.5,
      ),
      displayMedium: base.displayMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      displaySmall: base.displaySmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: base.titleLarge?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleMedium: base.titleMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.15,
      ),
      titleSmall: base.titleSmall?.copyWith(
        color: secondaryColor,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        color: color,
        letterSpacing: 0.15,
        height: 1.5,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        color: secondaryColor,
        letterSpacing: 0.25,
        height: 1.5,
      ),
      bodySmall: base.bodySmall?.copyWith(
        color: secondaryColor,
        letterSpacing: 0.4,
      ),
      labelLarge: base.labelLarge?.copyWith(
        color: color,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: base.labelMedium?.copyWith(
        color: secondaryColor,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      labelSmall: base.labelSmall?.copyWith(
        color: secondaryColor,
        letterSpacing: 0.5,
      ),
    );
  }

  /// Monospace style for code/terminal contexts.
  static TextStyle get codeStyle => GoogleFonts.jetBrainsMono(
    fontSize: 13,
    height: 1.6,
    letterSpacing: 0,
    color: AppColors.textPrimary,
  );

  // ──────────────────────────────────────────────
  //  Dark Theme
  // ──────────────────────────────────────────────

  /// The premium dark theme — default for TermuxForge.
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.dark(
      primary: AppColors.accentBlue,
      onPrimary: AppColors.backgroundPrimary,
      primaryContainer: AppColors.accentBlue.withValues(alpha: 0.18),
      onPrimaryContainer: AppColors.accentBlueLight,
      secondary: AppColors.accentPurple,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.accentPurple.withValues(alpha: 0.18),
      onSecondaryContainer: const Color(0xFFD4BBFF),
      tertiary: AppColors.accentTeal,
      onTertiary: AppColors.backgroundPrimary,
      tertiaryContainer: AppColors.accentTeal.withValues(alpha: 0.18),
      surface: AppColors.backgroundSecondary,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.backgroundTertiary,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.borderSubtle,
      outlineVariant: AppColors.borderStrong,
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: AppColors.errorSoft,
    );

    final textTheme = _buildTextTheme(Brightness.dark);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.backgroundPrimary,
      textTheme: textTheme,

      // ── App Bar ──
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.backgroundPrimary.withValues(alpha: 0.85),
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: AppColors.accentBlue.withValues(alpha: 0.05),
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: AppColors.backgroundPrimary,
        ),
      ),

      // ── Card ── (Glassmorphism-ready)
      cardTheme: CardThemeData(
        color: AppColors.backgroundSecondary.withValues(alpha: 0.8),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.glassBorder),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      ),

      // ── Dialog ──
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.backgroundTertiary,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.glassBorder),
        ),
        titleTextStyle: textTheme.titleLarge,
      ),

      // ── Bottom Sheet ──
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.backgroundSecondary,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        dragHandleColor: AppColors.borderStrong,
        showDragHandle: true,
      ),

      // ── Input Decoration ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.backgroundPrimary.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accentBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.textTertiary,
        ),
        labelStyle: textTheme.bodyMedium,
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
      ),

      // ── Elevated Button ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentBlue,
          foregroundColor: AppColors.backgroundPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Outlined Button ──
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accentBlue,
          side: const BorderSide(color: AppColors.accentBlue),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      // ── Text Button ──
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accentBlue,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),

      // ── Floating Action Button ──
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentBlue,
        foregroundColor: AppColors.backgroundPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // ── Chip ──
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.backgroundTertiary,
        labelStyle: textTheme.labelMedium,
        side: BorderSide(color: AppColors.borderSubtle),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      // ── Tab Bar ──
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.accentBlue,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.accentBlue,
        dividerColor: AppColors.borderSubtle,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelMedium,
      ),

      // ── Navigation Bar ──
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.backgroundSecondary,
        indicatorColor: AppColors.accentBlue.withValues(alpha: 0.18),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelSmall),
      ),

      // ── Navigation Rail ──
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.backgroundSecondary,
        indicatorColor: AppColors.accentBlue.withValues(alpha: 0.18),
        selectedIconTheme: const IconThemeData(color: AppColors.accentBlue),
        unselectedIconTheme: const IconThemeData(
          color: AppColors.textSecondary,
        ),
        selectedLabelTextStyle: textTheme.labelSmall?.copyWith(
          color: AppColors.accentBlue,
        ),
        unselectedLabelTextStyle: textTheme.labelSmall,
      ),

      // ── Divider ──
      dividerTheme: const DividerThemeData(
        color: AppColors.borderSubtle,
        thickness: 1,
        space: 1,
      ),

      // ── Icon ──
      iconTheme: const IconThemeData(
        color: AppColors.textSecondary,
        size: 22,
      ),

      // ── Snack Bar ──
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.backgroundTertiary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.textPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Tooltip ──
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.backgroundTertiary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
      ),

      // ── Drawer ──
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.backgroundSecondary,
        elevation: 0,
      ),

      // ── PopupMenu ──
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.backgroundTertiary,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.glassBorder),
        ),
        textStyle: textTheme.bodyMedium,
      ),

      // ── Switch ──
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(AppColors.accentBlue),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.accentBlue.withValues(alpha: 0.4);
          }
          return AppColors.borderStrong;
        }),
      ),

      // ── Progress Indicator ──
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentBlue,
        linearTrackColor: AppColors.borderSubtle,
      ),
    );
  }

  // ──────────────────────────────────────────────
  //  Light Theme
  // ──────────────────────────────────────────────

  /// Clean light theme for daytime use.
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.light(
      primary: AppColors.accentBlueDark,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFDCEEFF),
      onPrimaryContainer: const Color(0xFF0A3068),
      secondary: AppColors.accentPurple,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFEDE5FF),
      onSecondaryContainer: const Color(0xFF3B1A7A),
      tertiary: const Color(0xFF0F9D8A),
      onTertiary: Colors.white,
      surface: AppColors.backgroundSecondaryLight,
      onSurface: AppColors.textPrimaryLight,
      surfaceContainerHighest: AppColors.backgroundTertiaryLight,
      onSurfaceVariant: AppColors.textSecondaryLight,
      outline: AppColors.borderSubtleLight,
      outlineVariant: AppColors.borderStrongLight,
      error: AppColors.error,
      onError: Colors.white,
    );

    final textTheme = _buildTextTheme(Brightness.light);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.backgroundPrimaryLight,
      textTheme: textTheme,

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.backgroundSecondaryLight,
        foregroundColor: AppColors.textPrimaryLight,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.backgroundSecondaryLight,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.borderSubtleLight),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.backgroundPrimaryLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderSubtleLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderSubtleLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.accentBlueDark,
            width: 1.5,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentBlueDark,
          foregroundColor: Colors.white,
          elevation: 1,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.borderSubtleLight,
        thickness: 1,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.backgroundSecondaryLight,
        indicatorColor: AppColors.accentBlueDark.withValues(alpha: 0.12),
      ),

      iconTheme: const IconThemeData(
        color: AppColors.textSecondaryLight,
        size: 22,
      ),
    );
  }
}
