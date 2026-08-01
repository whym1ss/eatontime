import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../core/constants/app_constants.dart';
import '../data/local/isar_service.dart';
import '../data/local/product_local_source.dart';
import 'notification_service.dart';

/// Фоновая проверка сроков годности (workmanager).
///
/// Должна быть top-level функцией — вызывается в отдельном изоляте.
@pragma('vm:entry-point')
void backgroundCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != AppConstants.expiryCheckTaskName) return true;
    try {
      await BackgroundService.runExpiryCheck();
      return true;
    } catch (_) {
      return false;
    }
  });
}

class BackgroundService {
  BackgroundService._();

  static const _taskUniqueName = 'expiry-check-daily';

  static Future<void> init() async {
    await Workmanager().initialize(backgroundCallbackDispatcher);
  }

  /// Регистрирует ежедневную проверку. [hour]/[minute] — желаемое время.
  static Future<void> schedule({
    required int hour,
    required int minute,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await Workmanager().cancelByUniqueName(_taskUniqueName);
    await Workmanager().registerPeriodicTask(
      _taskUniqueName,
      AppConstants.expiryCheckTaskName,
      frequency: const Duration(hours: 24),
      initialDelay: _delayUntil(hour, minute),
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: false,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  }

  static Future<void> cancel() =>
      defaultTargetPlatform == TargetPlatform.android
          ? Workmanager().cancelByUniqueName(_taskUniqueName)
          : Future.value();

  static Duration _delayUntil(int hour, int minute) {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour, minute);
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    return target.difference(now);
  }

  /// Тело фоновой задачи: читает Isar и шлёт сводное уведомление.
  static Future<void> runExpiryCheck() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('notifications_enabled') ?? true)) return;

    final userId =
        prefs.getString('supabase_user_id') ?? prefs.getString('local_user_id');
    if (userId == null) return;

    final days = prefs.getInt('notify_days_before') ??
        AppConstants.expiringSoonThresholdDays;

    final isar = await IsarService.openBackground();
    final local = ProductLocalSource(isar);
    final rows = await local.getExpiringWithin(userId, days);

    final products = rows
        .map((e) => e.toModel())
        .where((p) => !p.isArchived && !p.notified)
        .toList();

    if (products.isEmpty) return;

    await NotificationService.instance.showExpirySummary(products);
    await local.markNotified(products.map((p) => p.id).toList());
  }
}
