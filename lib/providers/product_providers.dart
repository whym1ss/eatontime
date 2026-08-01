import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../data/models/product.dart';
import '../data/models/user_profile.dart';
import 'core_providers.dart';
import 'settings_providers.dart';

/// Все активные продукты (offline-first поток из Isar).
final activeProductsProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(productRepositoryProvider).watchActive();
});

/// Архив: съедено/выброшено.
final archivedProductsProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(productRepositoryProvider).watchArchive();
});

/// Выбранная зона хранения (null = все).
final selectedZoneProvider = StateProvider<String?>((ref) => null);

/// Поисковый запрос на главном экране.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Способ сортировки списка.
enum ProductSort { expiry, name, added, zone }

final sortModeProvider =
    StateProvider<ProductSort>((ref) => ProductSort.expiry);

/// Отфильтрованный и отсортированный список для главного экрана.
final filteredProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(activeProductsProvider).valueOrNull ?? const [];
  final zone = ref.watch(selectedZoneProvider);
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final sort = ref.watch(sortModeProvider);

  var result = products.where((p) {
    if (zone != null && p.zoneId != zone) return false;
    if (query.isEmpty) return true;
    return p.name.toLowerCase().contains(query) ||
        (p.brand?.toLowerCase().contains(query) ?? false) ||
        (p.category?.toLowerCase().contains(query) ?? false);
  }).toList();

  result.sort((a, b) {
    switch (sort) {
      case ProductSort.expiry:
        return a.expiryDate.compareTo(b.expiryDate);
      case ProductSort.name:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case ProductSort.added:
        return b.createdAt.compareTo(a.createdAt);
      case ProductSort.zone:
        final byZone = a.zoneId.compareTo(b.zoneId);
        return byZone != 0 ? byZone : a.expiryDate.compareTo(b.expiryDate);
    }
  });

  return result;
});

/// Группировка по статусу для секций на главном экране.
final groupedProductsProvider = Provider<Map<String, List<Product>>>((ref) {
  final products = ref.watch(filteredProductsProvider);
  final groups = <String, List<Product>>{
    AppConstants.statusExpired: [],
    AppConstants.statusCritical: [],
    AppConstants.statusExpiringSoon: [],
    AppConstants.statusFresh: [],
  };
  for (final p in products) {
    groups[p.freshnessStatus]?.add(p);
  }
  groups.removeWhere((_, v) => v.isEmpty);
  return groups;
});

/// Количество продуктов в каждой зоне (для чипов-фильтров).
final zoneCountsProvider = Provider<Map<String, int>>((ref) {
  final products = ref.watch(activeProductsProvider).valueOrNull ?? const [];
  final counts = <String, int>{};
  for (final p in products) {
    counts[p.zoneId] = (counts[p.zoneId] ?? 0) + 1;
  }
  return counts;
});

/// Сводка для карточки-дашборда наверху главного экрана.
class HomeSummary {
  const HomeSummary({
    required this.total,
    required this.expired,
    required this.critical,
    required this.expiringSoon,
    required this.fresh,
  });

  final int total;
  final int expired;
  final int critical;
  final int expiringSoon;
  final int fresh;

  int get needsAttention => expired + critical + expiringSoon;
}

final homeSummaryProvider = Provider<HomeSummary>((ref) {
  final products = ref.watch(activeProductsProvider).valueOrNull ?? const [];
  var expired = 0, critical = 0, soon = 0, fresh = 0;
  for (final p in products) {
    switch (p.freshnessStatus) {
      case AppConstants.statusExpired:
        expired++;
      case AppConstants.statusCritical:
        critical++;
      case AppConstants.statusExpiringSoon:
        soon++;
      default:
        fresh++;
    }
  }
  return HomeSummary(
    total: products.length,
    expired: expired,
    critical: critical,
    expiringSoon: soon,
    fresh: fresh,
  );
});

/// Достигнут ли лимит бесплатного тарифа.
final productLimitReachedProvider = Provider<bool>((ref) {
  final summary = ref.watch(homeSummaryProvider);
  final profile = ref.watch(userProfileProvider);
  return summary.total >= profile.productLimit;
});

/// Один продукт по id — для экрана деталей.
final productByIdProvider = Provider.family<Product?, String>((ref, id) {
  final products = ref.watch(activeProductsProvider).valueOrNull ?? const [];
  for (final p in products) {
    if (p.id == id) return p;
  }
  final archived = ref.watch(archivedProductsProvider).valueOrNull ?? const [];
  for (final p in archived) {
    if (p.id == id) return p;
  }
  return null;
});
