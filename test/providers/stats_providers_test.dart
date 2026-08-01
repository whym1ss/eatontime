import 'package:eat_on_time/core/constants/app_constants.dart';
import 'package:eat_on_time/data/models/product.dart';
import 'package:eat_on_time/providers/product_providers.dart';
import 'package:eat_on_time/providers/stats_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a continuous seven-day timeline including zero days', () async {
    final now = DateTime.now();
    final consumedAt = now.subtract(const Duration(days: 2));
    final product = Product(
      id: 'product-1',
      userId: 'user-1',
      name: 'Молоко',
      expiryDate: now,
      status: AppConstants.statusConsumed,
      consumedAt: consumedAt,
      price: 120,
      createdAt: now.subtract(const Duration(days: 5)),
      updatedAt: consumedAt,
    );

    final container = ProviderContainer(
      overrides: [
        archivedProductsProvider.overrideWith(
          (ref) => Stream.value([product]),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(statsPeriodProvider.notifier).state = StatsPeriod.week;
    await container.read(archivedProductsProvider.future);

    final stats = container.read(statsProvider);

    expect(stats.timeline, hasLength(7));
    expect(
        stats.timeline.map((point) => point.consumed).reduce((a, b) => a + b),
        1);
    expect(stats.savedMoney, 120);
  });
}
