import 'package:isar/isar.dart';

import '../../core/constants/app_constants.dart';
import 'product_entity.dart';

/// Все операции чтения/записи продуктов в локальной БД.
class ProductLocalSource {
  ProductLocalSource(this.isar);

  final Isar isar;

  IsarCollection<ProductEntity> get _col => isar.productEntitys;

  QueryBuilder<ProductEntity, ProductEntity, QAfterFilterCondition> _active(
    String userId,
  ) =>
      _col.filter().userIdEqualTo(userId).isDeletedEqualTo(false);

  /// Живые (не съеденные/выброшенные) продукты, отсортированные по сроку.
  Stream<List<ProductEntity>> watchActive(String userId) {
    return _active(userId)
        .not()
        .group((q) => q
            .statusEqualTo(AppConstants.statusConsumed)
            .or()
            .statusEqualTo(AppConstants.statusWasted))
        .sortByExpiryDate()
        .watch(fireImmediately: true);
  }

  /// Архив: съедено/выброшено.
  Stream<List<ProductEntity>> watchArchive(String userId) {
    return _active(userId)
        .group((q) => q
            .statusEqualTo(AppConstants.statusConsumed)
            .or()
            .statusEqualTo(AppConstants.statusWasted))
        .sortByUpdatedAtDesc()
        .watch(fireImmediately: true);
  }

  Future<List<ProductEntity>> getActive(String userId) {
    return _active(userId)
        .not()
        .group((q) => q
            .statusEqualTo(AppConstants.statusConsumed)
            .or()
            .statusEqualTo(AppConstants.statusWasted))
        .sortByExpiryDate()
        .findAll();
  }

  Future<ProductEntity?> getByUuid(String uuid) =>
      _col.filter().uuidEqualTo(uuid).findFirst();

  Future<ProductEntity?> findByBarcode(String userId, String barcode) =>
      _active(userId).barcodeEqualTo(barcode).findFirst();

  Future<int> countActive(String userId) => _active(userId)
      .not()
      .group((q) => q
          .statusEqualTo(AppConstants.statusConsumed)
          .or()
          .statusEqualTo(AppConstants.statusWasted))
      .count();

  /// Продукты, истекающие не позже [days] дней — для уведомлений.
  Future<List<ProductEntity>> getExpiringWithin(String userId, int days) async {
    final now = DateTime.now();
    final limit =
        DateTime(now.year, now.month, now.day).add(Duration(days: days + 1));
    return _active(userId)
        .not()
        .group((q) => q
            .statusEqualTo(AppConstants.statusConsumed)
            .or()
            .statusEqualTo(AppConstants.statusWasted))
        .and()
        .expiryDateLessThan(limit)
        .sortByExpiryDate()
        .findAll();
  }

  /// Ограниченная выборка кандидатов для почасовой проверки уведомлений.
  ///
  /// Финальное решение принимает чистая политика в BackgroundService: срок
  /// трактуется как конец указанного дня. Здесь намеренно берётся небольшой
  /// запас по верхней границе, но очень старая просрочка не загружается.
  Future<List<ProductEntity>> getExpiryNotificationCandidates(
    String userId, {
    required DateTime now,
    required int notifyHoursBefore,
    required int maxExpiredAgeDays,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final horizon = now.add(Duration(hours: notifyHoursBefore));
    final upper = horizon.isAfter(tomorrow) ? horizon : tomorrow;
    final lower = today.subtract(Duration(days: maxExpiredAgeDays + 1));

    return _active(userId)
        .not()
        .group((q) => q
            .statusEqualTo(AppConstants.statusConsumed)
            .or()
            .statusEqualTo(AppConstants.statusWasted))
        .and()
        .expiryDateBetween(
          lower,
          upper,
          includeLower: false,
          includeUpper: true,
        )
        .sortByExpiryDate()
        .findAll();
  }

  Future<List<ProductEntity>> getDirty(String userId) =>
      _col.filter().userIdEqualTo(userId).isDirtyEqualTo(true).findAll();

  Future<void> put(ProductEntity entity) =>
      isar.writeTxn(() => _col.put(entity));

  Future<void> putAll(List<ProductEntity> entities) =>
      isar.writeTxn(() => _col.putAll(entities));

  /// Обновляет запись по uuid, сохраняя её isarId.
  Future<void> upsertByUuid(ProductEntity entity) async {
    await isar.writeTxn(() async {
      final existing = await _col.filter().uuidEqualTo(entity.uuid).findFirst();
      if (existing != null) entity.isarId = existing.isarId;
      await _col.put(entity);
    });
  }

  Future<void> upsertAllByUuid(List<ProductEntity> entities) async {
    await isar.writeTxn(() async {
      for (final entity in entities) {
        final existing =
            await _col.filter().uuidEqualTo(entity.uuid).findFirst();
        if (existing != null) entity.isarId = existing.isarId;
      }
      await _col.putAll(entities);
    });
  }

  Future<void> hardDelete(String uuid) async {
    await isar.writeTxn(() async {
      final existing = await _col.filter().uuidEqualTo(uuid).findFirst();
      if (existing != null) await _col.delete(existing.isarId);
    });
  }

  Future<void> markNotified(List<String> uuids) async {
    if (uuids.isEmpty) return;
    await isar.writeTxn(() async {
      for (final uuid in uuids) {
        final entity = await _col.filter().uuidEqualTo(uuid).findFirst();
        if (entity == null) continue;
        entity.notified = true;
        await _col.put(entity);
      }
    });
  }

  Future<void> clearUser(String userId) async {
    await isar.writeTxn(() async {
      await _col.filter().userIdEqualTo(userId).deleteAll();
    });
  }

  /// Перепривязывает локальные продукты к Supabase-пользователю перед первой
  /// синхронизацией. UUID продуктов сохраняются, строки помечаются dirty.
  Future<int> migrateUser(String fromUserId, String toUserId) async {
    if (fromUserId == toUserId) return 0;
    return isar.writeTxn(() async {
      final rows = await _col.filter().userIdEqualTo(fromUserId).findAll();
      if (rows.isEmpty) return 0;
      final now = DateTime.now().toUtc();
      for (final row in rows) {
        row
          ..userId = toUserId
          ..updatedAt = now
          ..isDirty = true;
      }
      await _col.putAll(rows);
      return rows.length;
    });
  }
}
