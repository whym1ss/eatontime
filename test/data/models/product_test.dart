import 'package:eat_on_time/core/constants/app_constants.dart';
import 'package:eat_on_time/data/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Product productWithExpiry(DateTime expiry) {
    final now = DateTime.now();
    return Product(
      id: 'product-1',
      userId: 'user-1',
      name: 'Молоко',
      expiryDate: expiry,
      createdAt: now.subtract(const Duration(days: 2)),
      updatedAt: now,
    );
  }

  group('Product', () {
    test('calculates freshness from calendar dates', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      expect(
        productWithExpiry(today.subtract(const Duration(days: 1)))
            .freshnessStatus,
        AppConstants.statusExpired,
      );
      expect(
        productWithExpiry(today).freshnessStatus,
        AppConstants.statusCritical,
      );
      expect(
        productWithExpiry(today.add(const Duration(days: 3))).freshnessStatus,
        AppConstants.statusExpiringSoon,
      );
      expect(
        productWithExpiry(today.add(const Duration(days: 4))).freshnessStatus,
        AppConstants.statusFresh,
      );
    });

    test('archived status takes precedence over freshness', () {
      final product = productWithExpiry(DateTime.now()).copyWith(
        status: AppConstants.statusConsumed,
      );

      expect(product.isArchived, isTrue);
      expect(product.effectiveStatus, AppConstants.statusConsumed);
    });

    test('Supabase mapping excludes local flags and round-trips', () {
      final source =
          productWithExpiry(DateTime.now().add(const Duration(days: 5)))
              .copyWith(isDirty: true);
      final payload = source.toSupabase();
      final restored = Product.fromSupabase(payload);

      expect(payload.containsKey('isDirty'), isFalse);
      expect(restored.id, source.id);
      expect(restored.name, source.name);
      expect(restored.isDirty, isFalse);
    });
  });
}
