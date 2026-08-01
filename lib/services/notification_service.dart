import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/constants/app_constants.dart';
import '../data/models/product.dart';

/// Локальные уведомления о сроках годности.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
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
    await init();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission() ?? false;
      return granted;
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

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          AppConstants.expiryChannelId,
          AppConstants.expiryChannelName,
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

  /// Сводное уведомление по списку истекающих продуктов.
  Future<void> showExpirySummary(List<Product> products) async {
    if (products.isEmpty) return;

    final expired = products.where((p) => p.daysLeft < 0).toList();
    final today = products.where((p) => p.daysLeft == 0).toList();
    final soon = products.where((p) => p.daysLeft > 0).toList();

    final String title;
    if (expired.isNotEmpty) {
      title = '${_plural(expired.length)} просрочено';
    } else if (today.isNotEmpty) {
      title = 'Съешьте сегодня: ${today.length}';
    } else {
      title = 'Скоро истекает срок: ${soon.length}';
    }

    final names = products.take(4).map((p) => p.name).join(', ');
    final more = products.length > 4 ? ' и ещё ${products.length - 4}' : '';

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
