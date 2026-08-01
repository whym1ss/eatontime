import 'package:flutter/material.dart';

/// Brand and semantic colors used to build the light and dark themes.
///
/// Widgets should prefer `Theme.of(context).colorScheme`; these constants are
/// reserved for product statuses and branded surfaces that must stay stable.
class AppColors {
  AppColors._();

  // Product status colors. Text/icon always accompanies the color in the UI.
  static const Color freshGreen = Color(0xFF2F8F53);
  static const Color warningYellow = Color(0xFFE49A22);
  static const Color criticalRed = Color(0xFFDA5A52);
  static const Color expiredGrey = Color(0xFF7F7882);

  // Brand palette.
  static const Color primary = Color(0xFF236B3A);
  static const Color primaryLight = Color(0xFFAEDDB7);
  static const Color primaryDark = Color(0xFF124625);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color secondary = Color(0xFF65B96E);
  static const Color secondaryLight = Color(0xFFDDF2E1);
  static const Color mint = Color(0xFFE7F5E9);
  static const Color lime = Color(0xFFD7E977);

  // Light surfaces.
  static const Color surface = Color(0xFFF7F6F1);
  static const Color surfaceRaised = Color(0xFFF0F4ED);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF172019);
  static const Color textSecondary = Color(0xFF667068);
  static const Color divider = Color(0xFFDDE3DC);

  // Dark surfaces.
  static const Color surfaceDark = Color(0xFF101713);
  static const Color surfaceRaisedDark = Color(0xFF17211B);
  static const Color cardBackgroundDark = Color(0xFF1C2820);
  static const Color textOnDark = Color(0xFFF1F5F1);
  static const Color textSecondaryDark = Color(0xFFB5BFB7);
  static const Color dividerDark = Color(0xFF344139);

  // Storage zones.
  static const Color fridgeBlue = Color(0xFF4B9CCB);
  static const Color freezerCyan = Color(0xFF26A9B8);
  static const Color pantryOrange = Color(0xFFE59442);

  // Actions.
  static const Color error = criticalRed;
  static const Color success = freshGreen;
}
