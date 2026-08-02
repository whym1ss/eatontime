import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/themes/app_theme.dart';
import 'core/network/supabase_client.dart';
import 'data/local/isar_service.dart';
import 'data/local/product_local_source.dart';
import 'providers/core_providers.dart';
import 'providers/settings_providers.dart';
import 'router/app_router.dart';
import 'services/background_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('ru');

  final isar = await IsarService.open();
  final prefs = await SharedPreferences.getInstance();

  // Supabase — опционально: без него приложение работает офлайн.
  var supabaseReady = false;
  try {
    await SupabaseBootstrap.initialize();
    supabaseReady = true;
    final remoteUserId = await SupabaseBootstrap.ensureAnonymousSession();
    if (remoteUserId != null) {
      await _migrateLocalProducts(
        prefs: prefs,
        local: ProductLocalSource(isar.isar),
        remoteUserId: remoteUserId,
      );
    }
  } catch (_) {
    supabaseReady = false;
  }

  runApp(
    ProviderScope(
      overrides: [
        isarServiceProvider.overrideWithValue(isar),
        sharedPreferencesProvider.overrideWithValue(prefs),
        supabaseAvailableProvider.overrideWithValue(supabaseReady),
      ],
      child: const EatOnTimeApp(),
    ),
  );

  // Необязательные платформенные плагины не должны задерживать первый кадр
  // или мешать приложению запуститься.
  unawaited(_initializeOptionalServices(prefs));
}

Future<void> _migrateLocalProducts({
  required SharedPreferences prefs,
  required ProductLocalSource local,
  required String remoteUserId,
}) async {
  final localUserId = prefs.getString('local_user_id');
  if (localUserId == null) return;
  await local.migrateUser(localUserId, remoteUserId);
}

Future<void> _initializeOptionalServices(SharedPreferences prefs) async {
  try {
    await NotificationService.instance.init();
    await BackgroundService.init();
    if (prefs.getBool('notifications_enabled') ?? false) {
      await BackgroundService.schedule(
        hour: prefs.getInt('notification_hour') ?? 9,
        minute: prefs.getInt('notification_minute') ?? 0,
      );
    }
  } catch (error) {
    // Оставляем причину в системном журнале: это помогает диагностировать
    // ограничения конкретной прошивки, не мешая запуску приложения.
    debugPrint('Optional Android services are unavailable: $error');
    // Фоновые задачи недоступны (например, в тестах/desktop) — не критично.
  }
}

class EatOnTimeApp extends ConsumerWidget {
  const EatOnTimeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Eat on Time',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: appRouter,
    );
  }
}
