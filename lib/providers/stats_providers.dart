import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/date_utils.dart';
import '../data/models/product.dart';
import 'product_providers.dart';

/// Период агрегации статистики.
enum StatsPeriod { week, month, year }

extension StatsPeriodX on StatsPeriod {
  String get label => switch (this) {
        StatsPeriod.week => 'Неделя',
        StatsPeriod.month => 'Месяц',
        StatsPeriod.year => 'Год',
      };

  Duration get duration => switch (this) {
        StatsPeriod.week => const Duration(days: 7),
        StatsPeriod.month => const Duration(days: 30),
        StatsPeriod.year => const Duration(days: 365),
      };
}

final statsPeriodProvider =
    StateProvider<StatsPeriod>((ref) => StatsPeriod.month);

class StatsData {
  const StatsData({
    required this.consumed,
    required this.wasted,
    required this.savedMoney,
    required this.lostMoney,
    required this.byCategory,
    required this.timeline,
  });

  final int consumed;
  final int wasted;
  final double savedMoney;
  final double lostMoney;

  /// Категория → количество выброшенного.
  final Map<String, int> byCategory;

  /// День → (съедено, выброшено) для графика.
  final List<DailyPoint> timeline;

  int get total => consumed + wasted;

  /// Доля спасённых продуктов, 0..1.
  double get savedRate => total == 0 ? 1.0 : consumed / total;

  static const empty = StatsData(
    consumed: 0,
    wasted: 0,
    savedMoney: 0,
    lostMoney: 0,
    byCategory: {},
    timeline: [],
  );
}

class DailyPoint {
  const DailyPoint(this.date, this.consumed, this.wasted);
  final DateTime date;
  final int consumed;
  final int wasted;
}

final statsProvider = Provider<StatsData>((ref) {
  final archived = ref.watch(archivedProductsProvider).valueOrNull ?? const [];
  final period = ref.watch(statsPeriodProvider);
  final today = AppDateUtils.dateOnly(DateTime.now());
  final daysInPeriod = period.duration.inDays;
  final cutoff = today.subtract(Duration(days: daysInPeriod - 1));

  final inPeriod = archived.where((p) {
    final at = AppDateUtils.dateOnly(p.consumedAt ?? p.updatedAt);
    return !at.isBefore(cutoff);
  }).toList();

  if (inPeriod.isEmpty) return StatsData.empty;

  var consumed = 0, wasted = 0;
  var savedMoney = 0.0, lostMoney = 0.0;
  final byCategory = <String, int>{};
  final byDay = <DateTime, List<int>>{};

  for (final p in inPeriod) {
    final at = p.consumedAt ?? p.updatedAt;
    final day = DateTime(at.year, at.month, at.day);
    final slot = byDay.putIfAbsent(day, () => [0, 0]);

    if (p.status == AppConstants.statusConsumed) {
      consumed++;
      savedMoney += p.price ?? 0;
      slot[0]++;
    } else if (p.status == AppConstants.statusWasted) {
      wasted++;
      lostMoney += p.price ?? 0;
      slot[1]++;
      final cat = p.category ?? 'other';
      byCategory[cat] = (byCategory[cat] ?? 0) + 1;
    }
  }

  final timeline = List.generate(daysInPeriod, (index) {
    final day = cutoff.add(Duration(days: index));
    final values = byDay[day] ?? const [0, 0];
    return DailyPoint(day, values[0], values[1]);
  });

  final sortedCategories = Map.fromEntries(
    byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
  );

  return StatsData(
    consumed: consumed,
    wasted: wasted,
    savedMoney: savedMoney,
    lostMoney: lostMoney,
    byCategory: sortedCategories,
    timeline: timeline,
  );
});

/// Продукты, которые стоит съесть в первую очередь (для виджета «Съешь сегодня»).
final eatSoonProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(activeProductsProvider).valueOrNull ?? const [];
  final urgent = products
      .where((p) =>
          p.daysLeft >= 0 &&
          p.daysLeft <= AppConstants.expiringSoonThresholdDays)
      .toList()
    ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
  return urgent.take(5).toList();
});
