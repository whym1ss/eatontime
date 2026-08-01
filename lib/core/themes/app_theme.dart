import 'package:flutter/material.dart';

import 'colors.dart';

class AppTheme {
  AppTheme._();

  static const double radiusSmall = 12;
  static const double radiusMedium = 18;
  static const double radiusLarge = 26;

  static const Duration motionFast = Duration(milliseconds: 160);
  static const Duration motionMedium = Duration(milliseconds: 260);
  static const Duration motionSlow = Duration(milliseconds: 360);

  static ThemeData get lightTheme => _build(Brightness.light);
  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? AppColors.surfaceDark : AppColors.surface;
    final surface =
        dark ? AppColors.cardBackgroundDark : AppColors.cardBackground;
    final raised = dark ? AppColors.surfaceRaisedDark : AppColors.surfaceRaised;
    final text = dark ? AppColors.textOnDark : AppColors.textPrimary;
    final muted = dark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final outline = dark ? AppColors.dividerDark : AppColors.divider;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: dark ? const Color(0xFF8BD59A) : AppColors.primary,
      onPrimary: dark ? const Color(0xFF073916) : AppColors.onPrimary,
      primaryContainer:
          dark ? const Color(0xFF224E2E) : AppColors.secondaryLight,
      onPrimaryContainer:
          dark ? const Color(0xFFCBF4D2) : AppColors.primaryDark,
      secondary: dark ? const Color(0xFFBFD46C) : const Color(0xFF61741D),
      onSecondary: dark ? const Color(0xFF2C3400) : Colors.white,
      surface: surface,
      onSurface: text,
      surfaceContainerLowest: background,
      surfaceContainerLow: raised,
      surfaceContainer: surface,
      surfaceContainerHigh:
          dark ? const Color(0xFF26342B) : const Color(0xFFEAF0E8),
      outline: dark ? const Color(0xFF748078) : const Color(0xFF7B857D),
      outlineVariant: outline,
      error: AppColors.criticalRed,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
    );

    final textTheme = base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 30,
        height: 1.08,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: text,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 22,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.35,
        color: text,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 16,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: text,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.4,
        color: text,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.35,
        color: text,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.35,
        color: muted,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: text,
      ),
    );

    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusSmall),
      borderSide: BorderSide(color: outline),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          side: BorderSide(color: outline.withValues(alpha: dark ? 0.7 : 0.8)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: scheme.primaryContainer,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return textTheme.bodySmall?.copyWith(
            color:
                states.contains(WidgetState.selected) ? scheme.primary : muted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          );
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 6,
        focusElevation: 7,
        highlightElevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        modalBarrierColor: Colors.black.withValues(alpha: 0.38),
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(radiusLarge)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFFE6EFE7) : AppColors.primaryDark,
        contentTextStyle: TextStyle(
          color: dark ? AppColors.primaryDark : Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: outline,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide(color: outline),
        backgroundColor: surface,
        selectedColor: scheme.primaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        labelStyle: textTheme.bodyMedium,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: text,
          backgroundColor: raised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primary.withValues(alpha: 0.12),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : muted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? scheme.primary
              : outline;
        }),
      ),
    );
  }

  static Color statusColor(String status) {
    switch (status) {
      case 'fresh':
        return AppColors.freshGreen;
      case 'expiring_soon':
        return AppColors.warningYellow;
      case 'critical':
        return AppColors.criticalRed;
      case 'expired':
        return AppColors.expiredGrey;
      case 'consumed':
        return AppColors.freshGreen;
      case 'wasted':
        return AppColors.criticalRed;
      default:
        return AppColors.expiredGrey;
    }
  }

  static IconData statusIcon(String status) {
    switch (status) {
      case 'fresh':
        return Icons.eco_outlined;
      case 'expiring_soon':
        return Icons.schedule;
      case 'critical':
        return Icons.priority_high_rounded;
      case 'expired':
        return Icons.event_busy_outlined;
      case 'consumed':
        return Icons.restaurant_rounded;
      case 'wasted':
        return Icons.delete_outline_rounded;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  static IconData categoryIcon(String? category) {
    switch (category) {
      case 'dairy':
        return Icons.water_drop_outlined;
      case 'meat':
        return Icons.kebab_dining_outlined;
      case 'fish':
        return Icons.set_meal_outlined;
      case 'vegetables':
        return Icons.eco_outlined;
      case 'fruits':
        return Icons.apple_outlined;
      case 'eggs':
        return Icons.egg_alt_outlined;
      case 'grains':
        return Icons.bakery_dining_outlined;
      case 'canned':
        return Icons.inventory_2_outlined;
      case 'frozen':
        return Icons.ac_unit;
      case 'condiments':
        return Icons.local_dining_outlined;
      case 'beverages':
        return Icons.local_drink_outlined;
      default:
        return Icons.shopping_basket_outlined;
    }
  }

  static Color categoryColor(String? category) {
    switch (category) {
      case 'dairy':
        return const Color(0xFF5B9FD1);
      case 'meat':
        return const Color(0xFFD36B65);
      case 'fish':
        return const Color(0xFF398F9C);
      case 'vegetables':
        return const Color(0xFF4B9B59);
      case 'fruits':
        return const Color(0xFFDC7950);
      case 'eggs':
        return const Color(0xFFD1A42F);
      case 'grains':
        return const Color(0xFFA47A43);
      case 'frozen':
        return AppColors.freezerCyan;
      case 'beverages':
        return const Color(0xFF856BC0);
      default:
        return const Color(0xFF718078);
    }
  }

  static IconData zoneIcon(String zoneId) {
    switch (zoneId) {
      case 'fridge':
        return Icons.kitchen_outlined;
      case 'freezer':
        return Icons.ac_unit;
      case 'pantry':
        return Icons.shelves;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  static Color zoneColor(String zoneId) {
    switch (zoneId) {
      case 'fridge':
        return AppColors.fridgeBlue;
      case 'freezer':
        return AppColors.freezerCyan;
      case 'pantry':
        return AppColors.pantryOrange;
      default:
        return AppColors.expiredGrey;
    }
  }

  static String zoneLabel(String zoneId) {
    switch (zoneId) {
      case 'fridge':
        return 'Холодильник';
      case 'freezer':
        return 'Морозилка';
      case 'pantry':
        return 'Шкаф';
      default:
        return zoneId;
    }
  }
}
