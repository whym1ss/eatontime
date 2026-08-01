import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../presentation/screens/add_product_screen.dart';
import '../presentation/screens/app_shell.dart';
import '../presentation/screens/archive_screen.dart';
import '../presentation/screens/home_screen.dart';
import '../presentation/screens/product_detail_screen.dart';
import '../presentation/screens/receipt_scan_screen.dart';
import '../presentation/screens/scan_screen.dart';
import '../presentation/screens/settings_screen.dart';
import '../presentation/screens/stats_screen.dart';
import '../presentation/screens/voice_add_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _homeKey = GlobalKey<NavigatorState>();
final _statsKey = GlobalKey<NavigatorState>();
final _settingsKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(navigationShell: shell),
      branches: [
        StatefulShellBranch(
          navigatorKey: _homeKey,
          routes: [
            GoRoute(
              path: '/',
              name: 'home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _statsKey,
          routes: [
            GoRoute(
              path: '/stats',
              name: 'stats',
              builder: (context, state) => const StatsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _settingsKey,
          routes: [
            GoRoute(
              path: '/settings',
              name: 'settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/add',
      name: 'add',
      parentNavigatorKey: _rootKey,
      pageBuilder: (context, state) =>
          _motionPage(state, const AddProductScreen()),
      routes: [
        GoRoute(
          path: 'voice',
          name: 'add-voice',
          parentNavigatorKey: _rootKey,
          pageBuilder: (context, state) =>
              _motionPage(state, const VoiceAddScreen()),
        ),
      ],
    ),
    GoRoute(
      path: '/scan',
      name: 'scan',
      parentNavigatorKey: _rootKey,
      pageBuilder: (context, state) => _motionPage(state, const ScanScreen()),
      routes: [
        GoRoute(
          path: 'receipt',
          name: 'scan-receipt',
          parentNavigatorKey: _rootKey,
          pageBuilder: (context, state) =>
              _motionPage(state, const ReceiptScanScreen()),
        ),
      ],
    ),
    GoRoute(
      path: '/product/:id',
      name: 'product',
      parentNavigatorKey: _rootKey,
      pageBuilder: (context, state) => _motionPage(
        state,
        ProductDetailScreen(productId: state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/archive',
      name: 'archive',
      parentNavigatorKey: _rootKey,
      pageBuilder: (context, state) =>
          _motionPage(state, const ArchiveScreen()),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(),
    body: Center(child: Text('Страница не найдена: ${state.uri}')),
  ),
);

CustomTransitionPage<void> _motionPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
