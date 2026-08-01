import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../local/product_entity.dart';
import '../local/product_local_source.dart';
import '../models/product.dart';
import '../models/waste_entry.dart';
import '../remote/product_remote_source.dart';

/// Offline-first репозиторий: локальная БД — источник истины,
/// Supabase — фоновая синхронизация.
class ProductRepository {
  ProductRepository({
    required this.local,
    required this.remote,
    required this.userId,
    Connectivity? connectivity,
  }) : _connectivity = connectivity ?? Connectivity();

  final ProductLocalSource local;
  final ProductRemoteSource? remote;
  final String userId;
  final Connectivity _connectivity;

  static const _uuid = Uuid();
  static const _lastSyncKey = 'last_sync_at';

  bool _syncing = false;

  // ---------------------------------------------------------------- чтение

  Stream<List<Product>> watchActive() =>
      local.watchActive(userId).map(_mapAndRefreshStatus);

  Stream<List<Product>> watchArchive() => local
      .watchArchive(userId)
      .map((rows) => rows.map((e) => e.toModel()).toList());

  Future<List<Product>> getActive() async =>
      _mapAndRefreshStatus(await local.getActive(userId));

  Future<Product?> getById(String id) async =>
      (await local.getByUuid(id))?.toModel();

  Future<int> countActive() => local.countActive(userId);

  Future<int> availableSlots(int maxActiveProducts) async {
    final active = await countActive();
    return (maxActiveProducts - active).clamp(0, maxActiveProducts);
  }

  Future<void> ensureCapacity({
    required int requested,
    required int maxActiveProducts,
  }) async {
    if (requested <= 0) return;
    final available = await availableSlots(maxActiveProducts);
    if (requested > available) {
      throw ProductLimitException(
        limit: maxActiveProducts,
        requested: requested,
        available: available,
      );
    }
  }

  Future<List<Product>> getExpiringWithin(int days) async {
    final rows = await local.getExpiringWithin(userId, days);
    return rows.map((e) => e.toModel()).toList();
  }

  List<Product> _mapAndRefreshStatus(List<ProductEntity> rows) {
    return rows.map((e) {
      final model = e.toModel();
      if (model.isArchived) return model;
      return model.copyWith(status: model.freshnessStatus);
    }).toList();
  }

  // ---------------------------------------------------------------- запись

  Future<Product> add({
    required String name,
    required DateTime expiryDate,
    String zoneId = AppConstants.zoneFridge,
    String? brand,
    String? barcode,
    String? category,
    DateTime? purchaseDate,
    DateTime? openedDate,
    int quantity = 1,
    String unit = 'pcs',
    double? price,
    String? note,
    String? imagePath,
    String addMethod = AppConstants.addManual,
    required int maxActiveProducts,
  }) async {
    final products = await addMany(
      [
        ProductDraft(
          name: name,
          expiryDate: expiryDate,
          zoneId: zoneId,
          brand: brand,
          barcode: barcode,
          category: category,
          purchaseDate: purchaseDate,
          openedDate: openedDate,
          quantity: quantity,
          unit: unit,
          price: price,
          note: note,
          imagePath: imagePath,
          addMethod: addMethod,
        ),
      ],
      maxActiveProducts: maxActiveProducts,
    );
    return products.single;
  }

  /// Атомарно добавляет несколько продуктов одной локальной транзакцией.
  Future<List<Product>> addMany(
    List<ProductDraft> drafts, {
    required int maxActiveProducts,
  }) async {
    if (drafts.isEmpty) return [];
    await ensureCapacity(
      requested: drafts.length,
      maxActiveProducts: maxActiveProducts,
    );
    final now = DateTime.now().toUtc();
    final purchasedAt = DateTime.now();
    final products = drafts.map((draft) {
      final product = Product(
        id: _uuid.v4(),
        userId: userId,
        name: draft.name.trim(),
        brand: draft.brand,
        barcode: draft.barcode,
        category: draft.category,
        zoneId: draft.zoneId,
        expiryDate: draft.expiryDate,
        purchaseDate: draft.purchaseDate ?? purchasedAt,
        openedDate: draft.openedDate,
        quantity: draft.quantity,
        unit: draft.unit,
        price: draft.price,
        note: draft.note,
        imagePath: draft.imagePath,
        addMethod: draft.addMethod,
        createdAt: now,
        updatedAt: now,
        isDirty: true,
      );
      return product.copyWith(status: product.freshnessStatus);
    }).toList();
    await local.putAll(products.map(ProductEntity.fromModel).toList());
    unawaited(_pushSafely());
    return products;
  }

  Future<void> addAll(
    List<Product> products, {
    required int maxActiveProducts,
  }) async {
    if (products.isEmpty) return;
    await ensureCapacity(
      requested: products.length,
      maxActiveProducts: maxActiveProducts,
    );
    await local.putAll(
      products
          .map((p) => ProductEntity.fromModel(p.copyWith(isDirty: true)))
          .toList(),
    );
    unawaited(_pushSafely());
  }

  Future<void> update(Product product) async {
    final existing = await getById(product.id);
    final expiryChanged = existing != null &&
        (existing.expiryDate.year != product.expiryDate.year ||
            existing.expiryDate.month != product.expiryDate.month ||
            existing.expiryDate.day != product.expiryDate.day);
    final normalizedStatus =
        product.isArchived ? product.status : product.freshnessStatus;
    final updated = product.copyWith(
      status: normalizedStatus,
      notified: expiryChanged ? false : product.notified,
      updatedAt: DateTime.now().toUtc(),
      isDirty: true,
    );
    await local.upsertByUuid(ProductEntity.fromModel(updated));
    unawaited(_pushSafely());
  }

  Future<void> markConsumed(Product product) => update(
        product.copyWith(
          status: AppConstants.statusConsumed,
          consumedAt: DateTime.now().toUtc(),
        ),
      );

  Future<void> markWasted(Product product) async {
    await update(
      product.copyWith(
        status: AppConstants.statusWasted,
        consumedAt: DateTime.now().toUtc(),
      ),
    );
    final entry = WasteEntry(
      userId: userId,
      productId: product.id,
      productName: product.name,
      category: product.category,
      expiryDate: product.expiryDate,
      wastedDate: DateTime.now().toUtc(),
      reason: product.daysLeft < 0 ? 'expired' : 'other',
      estimatedValue: product.price,
      createdAt: DateTime.now().toUtc(),
    );
    if (await _canSync()) {
      try {
        await remote!.logWaste(entry);
      } catch (_) {
        // Потеря записи статистики не критична для UX.
      }
    }
  }

  Future<void> restore(Product product) => update(
        product.copyWith(
          status: product.freshnessStatus,
          consumedAt: null,
        ),
      );

  /// Мягкое удаление: помечаем и синхронизируем, физически чистим после push.
  Future<void> delete(Product product) async {
    final marked = product.copyWith(
      isDeleted: true,
      isDirty: true,
      updatedAt: DateTime.now().toUtc(),
    );
    await local.upsertByUuid(ProductEntity.fromModel(marked));
    unawaited(_pushSafely());
  }

  Future<void> markNotified(List<String> ids) => local.markNotified(ids);

  Future<Product?> findByBarcode(String barcode) async =>
      (await local.findByBarcode(userId, barcode))?.toModel();

  Future<Map<String, dynamic>?> lookupCatalog(String barcode) async {
    if (!await _isOnline()) return null;
    try {
      return await remote!.lookupBarcode(barcode);
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------ синхронизация

  Future<bool> _isOnline() async {
    if (remote == null) return false;
    final result = await _connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// Синхронизация пользовательских данных разрешена только для реальной
  /// Supabase-сессии. Локальный `local-*` id не является UUID и не должен
  /// отправляться в поле `user_id`.
  Future<bool> _canSync() async {
    if (!await _isOnline()) return false;
    return remote!.client.auth.currentUser?.id == userId;
  }

  Future<void> _pushSafely() async {
    try {
      await sync();
    } catch (_) {
      // Тихо: повторим при следующем изменении или ручном pull-to-refresh.
    }
  }

  /// Двусторонняя синхронизация: push локальных изменений, затем pull свежих.
  Future<SyncResult> sync() async {
    if (_syncing) return SyncResult.alreadyRunning;
    if (remote == null) return SyncResult.unavailable;
    final connectivity = await _connectivity.checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      return SyncResult.offline;
    }
    if (remote!.client.auth.currentUser?.id != userId) {
      return SyncResult.signedOut;
    }
    _syncing = true;
    try {
      await _push();
      await _pull();
      return SyncResult.synced;
    } finally {
      _syncing = false;
    }
  }

  Future<void> _push() async {
    final dirty = await local.getDirty(userId);
    if (dirty.isEmpty) return;

    final toDelete = dirty.where((e) => e.isDeleted).toList();
    final toUpsert = dirty.where((e) => !e.isDeleted).toList();

    if (toUpsert.isNotEmpty) {
      await remote!.upsertAll(toUpsert.map((e) => e.toModel()).toList());
      await local.upsertAllByUuid(
        toUpsert.map((e) {
          final entity = ProductEntity.fromModel(e.toModel());
          entity.isDirty = false;
          return entity;
        }).toList(),
      );
    }

    for (final entity in toDelete) {
      // Сохраняем tombstone, чтобы удаление увидели другие устройства.
      await remote!.upsert(entity.toModel());
      await local.hardDelete(entity.uuid);
    }
  }

  Future<void> _pull() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_lastSyncKey}_$userId');
    final since = raw == null ? null : DateTime.tryParse(raw);
    // Фиксируем верхнюю границу до запроса: изменения, появившиеся во время
    // pull, гарантированно попадут в следующую синхронизацию.
    final syncStartedAt = DateTime.now().toUtc();

    final remoteProducts = await remote!.fetchSince(userId, since);
    if (remoteProducts.isNotEmpty) {
      final entities = <ProductEntity>[];
      for (final product in remoteProducts) {
        if (product.isDeleted) {
          await local.hardDelete(product.id);
          continue;
        }
        final localRow = await local.getByUuid(product.id);
        // Локальные несинхронизированные правки приоритетнее серверных.
        if (localRow != null &&
            localRow.isDirty &&
            localRow.updatedAt.isAfter(product.updatedAt)) {
          continue;
        }
        entities.add(ProductEntity.fromModel(product));
      }
      if (entities.isNotEmpty) await local.upsertAllByUuid(entities);
    }

    await prefs.setString(
      '${_lastSyncKey}_$userId',
      syncStartedAt.toIso8601String(),
    );
  }

  Future<List<WasteEntry>> fetchWasteStats({DateTime? since}) async {
    if (!await _canSync()) return [];
    try {
      return await remote!.fetchWaste(userId, since: since);
    } catch (_) {
      return [];
    }
  }
}

class ProductDraft {
  const ProductDraft({
    required this.name,
    required this.expiryDate,
    this.zoneId = AppConstants.zoneFridge,
    this.brand,
    this.barcode,
    this.category,
    this.purchaseDate,
    this.openedDate,
    this.quantity = 1,
    this.unit = 'pcs',
    this.price,
    this.note,
    this.imagePath,
    this.addMethod = AppConstants.addManual,
  });

  final String name;
  final DateTime expiryDate;
  final String zoneId;
  final String? brand;
  final String? barcode;
  final String? category;
  final DateTime? purchaseDate;
  final DateTime? openedDate;
  final int quantity;
  final String unit;
  final double? price;
  final String? note;
  final String? imagePath;
  final String addMethod;
}

class ProductLimitException implements Exception {
  const ProductLimitException({
    required this.limit,
    required this.requested,
    required this.available,
  });

  final int limit;
  final int requested;
  final int available;

  @override
  String toString() {
    if (available == 0) {
      return 'Достигнут лимит: $limit продуктов.';
    }
    return 'Можно добавить ещё $available из $requested продуктов.';
  }
}

enum SyncResult {
  synced,
  offline,
  signedOut,
  unavailable,
  alreadyRunning,
}
