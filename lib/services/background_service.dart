import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../core/constants/app_constants.dart';
import '../data/local/isar_service.dart';
import '../data/local/product_local_source.dart';
import '../data/models/product.dart';
import 'notification_service.dart';

/// WorkManager starts this function in a background isolate.
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

/// The moment at which a date-only expiry becomes expired.
///
/// Product dates are entered without a time, so a product remains valid until
/// the end of the selected local calendar day.
DateTime expiryDeadline(DateTime expiryDate) {
  final local = expiryDate.isUtc ? expiryDate.toLocal() : expiryDate;
  return DateTime(local.year, local.month, local.day + 1);
}

/// Resolves the new hours preference while keeping existing installations
/// compatible with the old whole-days setting.
int resolveNotifyHours({int? configuredHours, int? legacyDays}) {
  final raw = configuredHours ??
      (legacyDays ?? AppConstants.expiringSoonThresholdDays) * 24;
  return raw.clamp(1, 24 * 365).toInt();
}

/// Classifies one product for a notification check.
ExpiryNotificationStage? expiryNotificationStage({
  required DateTime expiryDate,
  required DateTime now,
  required int notifyHoursBefore,
  int maxExpiredAgeDays = BackgroundService.maxExpiredAgeDays,
}) {
  final localNow = now.isUtc ? now.toLocal() : now;
  final deadline = expiryDeadline(expiryDate);

  if (!deadline.isAfter(localNow)) {
    final oldestUsefulDeadline =
        localNow.subtract(Duration(days: maxExpiredAgeDays));
    if (deadline.isBefore(oldestUsefulDeadline)) return null;
    return ExpiryNotificationStage.expired;
  }

  final horizon = localNow.add(Duration(hours: notifyHoursBefore));
  if (deadline.isAfter(horizon)) return null;

  final expiryLocal = expiryDate.isUtc ? expiryDate.toLocal() : expiryDate;
  final expiresToday = expiryLocal.year == localNow.year &&
      expiryLocal.month == localNow.month &&
      expiryLocal.day == localNow.day;
  return expiresToday
      ? ExpiryNotificationStage.today
      : ExpiryNotificationStage.soon;
}

String notificationDayKey(DateTime date) {
  final local = date.isUtc ? date.toLocal() : date;
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)}';
}

String expiryNotificationToken(
  String productId,
  ExpiryNotificationStage stage,
  DateTime expiryDate,
) =>
    '$productId:${notificationDayKey(expiryDate)}:${stage.name}';

/// Pure selection policy used both by WorkManager and unit tests.
List<ExpiryNotificationItem> selectExpiryNotifications({
  required Iterable<Product> products,
  required DateTime now,
  required int notifyHoursBefore,
  Set<String> alreadySent = const <String>{},
  int maxExpiredAgeDays = BackgroundService.maxExpiredAgeDays,
}) {
  final selected = <ExpiryNotificationItem>[];
  for (final product in products) {
    if (product.isArchived) continue;

    final stage = expiryNotificationStage(
      expiryDate: product.expiryDate,
      now: now,
      notifyHoursBefore: notifyHoursBefore,
      maxExpiredAgeDays: maxExpiredAgeDays,
    );
    if (stage == null) continue;

    final token =
        expiryNotificationToken(product.id, stage, product.expiryDate);
    if (alreadySent.contains(token)) continue;
    selected.add(ExpiryNotificationItem(product: product, stage: stage));
  }
  return selected;
}

class BackgroundService {
  BackgroundService._();

  static const notifyHoursBeforeKey = 'notify_hours_before';
  static const legacyNotifyDaysBeforeKey = 'notify_days_before';
  static const notificationHistoryKey = 'expiry_notification_history_v3';
  static const maxNotificationHistoryEntries = 1000;
  static const maxExpiredAgeDays = 7;
  static const periodicCheckFrequency = Duration(hours: 1);

  static const _taskUniqueName = 'expiry-check-daily';

  static Future<void> init() async {
    await Workmanager().initialize(backgroundCallbackDispatcher);
  }

  /// Registers an approximately hourly check.
  ///
  /// Android WorkManager deliberately does not guarantee an exact wall-clock
  /// time. Hourly checks make custom 4–5 hour horizons useful while the chosen
  /// minute remains a preferred anchor for the first and subsequent runs.
  static Future<void> schedule({
    required int hour,
    required int minute,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await Workmanager().cancelByUniqueName(_taskUniqueName);
    await Workmanager().registerPeriodicTask(
      _taskUniqueName,
      AppConstants.expiryCheckTaskName,
      frequency: periodicCheckFrequency,
      initialDelay: initialCheckDelay(hour: hour, minute: minute),
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

  /// Delay is never longer than one hour. Waiting until tomorrow's selected
  /// clock time would make an hours-based warning horizon ineffective.
  static Duration initialCheckDelay({
    required int hour,
    required int minute,
    DateTime? from,
  }) {
    final now = from ?? DateTime.now();
    final safeHour = hour.clamp(0, 23).toInt();
    final safeMinute = minute.clamp(0, 59).toInt();

    var daily = DateTime(now.year, now.month, now.day, safeHour, safeMinute);
    if (!daily.isAfter(now)) daily = daily.add(const Duration(days: 1));

    var hourly = DateTime(now.year, now.month, now.day, now.hour, safeMinute);
    if (!hourly.isAfter(now)) hourly = hourly.add(const Duration(hours: 1));

    final target = daily.isBefore(hourly) ? daily : hourly;
    return target.difference(now);
  }

  /// Reads Isar and posts one deduplicated expiry summary.
  static Future<void> runExpiryCheck() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('notifications_enabled') ?? false)) return;

    // Never consume a reminder when Android/iOS has blocked notifications.
    if (!await NotificationService.instance.areNotificationsEnabled()) return;

    final userId =
        prefs.getString('supabase_user_id') ?? prefs.getString('local_user_id');
    if (userId == null) return;

    final hours = resolveNotifyHours(
      configuredHours: prefs.getInt(notifyHoursBeforeKey),
      legacyDays: prefs.getInt(legacyNotifyDaysBeforeKey),
    );
    final now = DateTime.now();

    final isar = await IsarService.openBackground();
    final local = ProductLocalSource(isar);
    final rows = await local.getExpiryNotificationCandidates(
      userId,
      now: now,
      notifyHoursBefore: hours,
      maxExpiredAgeDays: maxExpiredAgeDays,
    );

    final storedHistory =
        prefs.getStringList(notificationHistoryKey) ?? const [];
    final notificationHistory = storedHistory.toSet();

    final items = selectExpiryNotifications(
      products: rows.map((row) => row.toModel()),
      now: now,
      notifyHoursBefore: hours,
      alreadySent: notificationHistory,
    );
    if (items.isEmpty) return;

    await NotificationService.instance.showExpiryItems(items);

    // Persist only after the plugin successfully posted the summary.
    notificationHistory.addAll(
      items.map(
        (item) => expiryNotificationToken(
          item.product.id,
          item.stage,
          item.product.expiryDate,
        ),
      ),
    );
    final boundedHistory = notificationHistory.toList();
    if (boundedHistory.length > maxNotificationHistoryEntries) {
      boundedHistory.removeRange(
        0,
        boundedHistory.length - maxNotificationHistoryEntries,
      );
    }
    await prefs.setStringList(notificationHistoryKey, boundedHistory);
  }
}
