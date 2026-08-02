import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';

import '../core/constants/app_constants.dart';
import '../data/models/product.dart';

enum ExpiryNotificationStage { soon, today, expired }

class ExpiryNotificationItem {
  const ExpiryNotificationItem({
    required this.product,
    required this.stage,
  });

  final Product product;
  final ExpiryNotificationStage stage;
}

/// Локальные уведомления о сроках годности.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const _androidChannel = MethodChannel('eat_on_time/notifications');

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('ic_notification');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            AppConstants.expiryChannelId,
            AppConstants.expiryChannelName,
            description: 'Напоминания о продуктах, у которых истекает срок',
            importance: Importance.high,
          ),
        );

    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        return await _androidChannel.invokeMethod<bool>(
              'requestNotificationPermission',
            ) ??
            false;
      } on PlatformException {
        // Старый embedding или фоновый FlutterEngine: используем плагин.
      } on MissingPluginException {
        // Нативный канал доступен только в основном Android Activity.
      }
    }

    await init();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? await android.areNotificationsEnabled() ?? false;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
              alert: true, badge: true, sound: true) ??
          false;
    }
    return true;
  }

  /// Фактическое системное разрешение, а не только переключатель приложения.
  Future<bool> areNotificationsEnabled() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          return await _androidChannel.invokeMethod<bool>(
                'areNotificationsEnabled',
              ) ??
              false;
        } on PlatformException {
          // Фоновый FlutterEngine не содержит Activity-канал.
        } on MissingPluginException {
          // Переходим к контекстной проверке плагина.
        }
      }

      await init();

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.areNotificationsEnabled() ?? false;
      }

      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final permissions = await ios.checkPermissions();
        return permissions?.isEnabled == true ||
            permissions?.isProvisionalEnabled == true;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Открывает системную страницу уведомлений приложения, если Android больше
  /// не может показать диалог разрешения (например, после явного отказа).
  Future<bool> openNotificationSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _androidChannel.invokeMethod<bool>(
            'openNotificationSettings',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          AppConstants.expiryChannelId,
          AppConstants.expiryChannelName,
          icon: 'ic_notification',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(''),
        ),
        iOS: DarwinNotificationDetails(),
      );

  /// Немедленное уведомление (используется фоновой задачей).
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await init();
    await _plugin.show(id, title, body, _details, payload: payload);
  }

  /// Запрашивает разрешение при необходимости и отправляет новое тестовое
  /// сообщение. UI получает честный результат вместо молчаливого успеха.
  Future<bool> showTestNotification() async {
    try {
      // На новых версиях Android проверка NotificationManager может вернуть
      // true до выдачи POST_NOTIFICATIONS. Всегда проходим через системный
      // запрос, а затем повторно проверяем фактическое состояние.
      final granted = await requestPermissions();
      if (!granted || !await areNotificationsEnabled()) {
        await openNotificationSettings();
        return false;
      }

      final id = DateTime.now().millisecondsSinceEpoch.remainder(0x7fffffff);
      await show(
        id: id,
        title: 'Eat on Time',
        body: 'Уведомления работают 👍',
        payload: 'notification-test',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Сводное уведомление по списку истекающих продуктов.
  Future<void> showExpirySummary(List<Product> products) async {
    if (products.isEmpty) return;

    final items = products
        .map(
          (product) => ExpiryNotificationItem(
            product: product,
            stage: product.daysLeft < 0
                ? ExpiryNotificationStage.expired
                : product.daysLeft == 0
                    ? ExpiryNotificationStage.today
                    : ExpiryNotificationStage.soon,
          ),
        )
        .toList();
    await showExpiryItems(items);
  }

  /// Сводка по продуктам, отобранным новой фоновой политикой.
  Future<void> showExpiryItems(List<ExpiryNotificationItem> items) async {
    if (items.isEmpty) return;

    final expired = items
        .where((item) => item.stage == ExpiryNotificationStage.expired)
        .toList();
    final today = items
        .where((item) => item.stage == ExpiryNotificationStage.today)
        .toList();
    final soon = items
        .where((item) => item.stage == ExpiryNotificationStage.soon)
        .toList();

    final String title;
    if (expired.isNotEmpty) {
      title = expired.length == 1
          ? '1 продукт просрочен'
          : '${_plural(expired.length)} просрочено';
    } else if (today.isNotEmpty) {
      title = 'Съешьте сегодня: ${today.length}';
    } else {
      title = 'Скоро истекает срок: ${soon.length}';
    }

    final names = items.take(4).map((item) => item.product.name).join(', ');
    final more = items.length > 4 ? ' и ещё ${items.length - 4}' : '';

    await show(id: 1001, title: title, body: '$names$more');
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id);
  }

  static String _plural(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return '$n продукт';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return '$n продукта';
    }
    return '$n продуктов';
  }
}
