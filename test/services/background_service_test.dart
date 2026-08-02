import 'package:eat_on_time/core/constants/app_constants.dart';
import 'package:eat_on_time/data/models/product.dart';
import 'package:eat_on_time/services/background_service.dart';
import 'package:eat_on_time/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('notification horizon', () {
    test('new hours value wins and legacy days remain compatible', () {
      expect(
        resolveNotifyHours(configuredHours: 5, legacyDays: 7),
        5,
      );
      expect(resolveNotifyHours(legacyDays: 3), 72);
      expect(resolveNotifyHours(), 72);
      expect(resolveNotifyHours(configuredHours: 0), 1);
    });

    test('date-only expiry is valid until the end of its local day', () {
      final deadline = expiryDeadline(DateTime(2026, 8, 2));
      expect(deadline, DateTime(2026, 8, 3));
    });

    test('hours are compared with the end-of-day deadline', () {
      final now = DateTime(2026, 8, 2, 20);
      final expiry = DateTime(2026, 8, 3);

      expect(
        expiryNotificationStage(
          expiryDate: expiry,
          now: now,
          notifyHoursBefore: 27,
        ),
        isNull,
      );
      expect(
        expiryNotificationStage(
          expiryDate: expiry,
          now: now,
          notifyHoursBefore: 28,
        ),
        ExpiryNotificationStage.soon,
      );
    });

    test('today stage still respects the configured hour horizon', () {
      final expiry = DateTime(2026, 8, 10);

      expect(
        expiryNotificationStage(
          expiryDate: expiry,
          now: DateTime(2026, 8, 10, 18, 59),
          notifyHoursBefore: 5,
        ),
        isNull,
      );
      expect(
        expiryNotificationStage(
          expiryDate: expiry,
          now: DateTime(2026, 8, 10, 19),
          notifyHoursBefore: 5,
        ),
        ExpiryNotificationStage.today,
      );
    });

    test('classifies recent expiry but drops very old rows', () {
      final now = DateTime(2026, 8, 10, 12);

      expect(
        expiryNotificationStage(
          expiryDate: DateTime(2026, 8, 9),
          now: now,
          notifyHoursBefore: 1,
        ),
        ExpiryNotificationStage.expired,
      );
      expect(
        expiryNotificationStage(
          expiryDate: DateTime(2026, 7, 20),
          now: now,
          notifyHoursBefore: 1,
        ),
        isNull,
      );
    });
  });

  group('notification deduplication', () {
    test('does not resend the same product and stage', () {
      final now = DateTime(2026, 8, 1, 12);
      final product = _product('milk', DateTime(2026, 8, 2));
      final token = expiryNotificationToken(
        product.id,
        ExpiryNotificationStage.soon,
        product.expiryDate,
      );

      final selected = selectExpiryNotifications(
        products: [product],
        now: now,
        notifyHoursBefore: 36,
        alreadySent: {token},
      );

      expect(selected, isEmpty);
    });

    test('does not repeat the same stage on the following day', () {
      final product = _product('milk', DateTime(2026, 8, 5));
      final token = expiryNotificationToken(
        product.id,
        ExpiryNotificationStage.soon,
        product.expiryDate,
      );

      final selected = selectExpiryNotifications(
        products: [product],
        now: DateTime(2026, 8, 2, 12),
        notifyHoursBefore: 96,
        alreadySent: {token},
      );

      expect(selected, isEmpty);
    });

    test('notifies again as product moves through all stages', () {
      final product = _product('milk', DateTime(2026, 8, 2));

      final soon = selectExpiryNotifications(
        products: [product],
        now: DateTime(2026, 8, 1, 12),
        notifyHoursBefore: 36,
      );
      final today = selectExpiryNotifications(
        products: [product],
        now: DateTime(2026, 8, 2, 9),
        notifyHoursBefore: 36,
        alreadySent: {
          expiryNotificationToken(
            product.id,
            ExpiryNotificationStage.soon,
            product.expiryDate,
          ),
        },
      );
      final expired = selectExpiryNotifications(
        products: [product],
        now: DateTime(2026, 8, 3, 9),
        notifyHoursBefore: 36,
      );

      expect(soon.single.stage, ExpiryNotificationStage.soon);
      expect(today.single.stage, ExpiryNotificationStage.today);
      expect(expired.single.stage, ExpiryNotificationStage.expired);
    });

    test('does not notify archived products', () {
      final selected = selectExpiryNotifications(
        products: [
          _product(
            'used',
            DateTime(2026, 8, 2),
            status: AppConstants.statusConsumed,
          ),
        ],
        now: DateTime(2026, 8, 2, 9),
        notifyHoursBefore: 24,
      );

      expect(selected, isEmpty);
    });
  });

  test('first hourly check never waits until the following day', () {
    final delay = BackgroundService.initialCheckDelay(
      hour: 9,
      minute: 15,
      from: DateTime(2026, 8, 2, 10, 45),
    );

    expect(delay, const Duration(minutes: 30));
    expect(delay <= BackgroundService.periodicCheckFrequency, isTrue);
  });
}

Product _product(
  String id,
  DateTime expiryDate, {
  String status = AppConstants.statusFresh,
}) {
  final created = DateTime(2026, 7, 1);
  return Product(
    id: id,
    userId: 'user',
    name: id,
    expiryDate: expiryDate,
    status: status,
    createdAt: created,
    updatedAt: created,
  );
}
