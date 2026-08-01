import 'package:freezed_annotation/freezed_annotation.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/date_utils.dart';

part 'product.freezed.dart';
part 'product.g.dart';

@freezed
class Product with _$Product {
  const factory Product({
    required String id,
    required String userId,
    required String name,
    String? brand,
    String? barcode,
    String? category,
    @Default(AppConstants.zoneFridge) String zoneId,
    required DateTime expiryDate,
    DateTime? purchaseDate,
    DateTime? openedDate,
    @Default(1) int quantity,
    @Default('pcs') String unit,
    double? price,
    String? note,
    String? imagePath,
    @Default(AppConstants.addManual) String addMethod,
    @Default(AppConstants.statusFresh) String status,
    @Default(false) bool notified,
    DateTime? consumedAt,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default(false) bool isDirty,
    @Default(false) bool isDeleted,
  }) = _Product;

  const Product._();

  factory Product.fromJson(Map<String, dynamic> json) =>
      _$ProductFromJson(json);

  /// Целых дней до истечения срока (может быть отрицательным).
  int get daysLeft => AppDateUtils.daysUntil(expiryDate);

  bool get isConsumed => status == AppConstants.statusConsumed;
  bool get isWasted => status == AppConstants.statusWasted;
  bool get isArchived => isConsumed || isWasted;

  /// Вычисляемый статус свежести (не учитывает съедено/выброшено).
  String get freshnessStatus {
    final d = daysLeft;
    if (d < 0) return AppConstants.statusExpired;
    if (d <= AppConstants.criticalThresholdDays) {
      return AppConstants.statusCritical;
    }
    if (d <= AppConstants.expiringSoonThresholdDays) {
      return AppConstants.statusExpiringSoon;
    }
    return AppConstants.statusFresh;
  }

  /// Итоговый статус для отображения.
  String get effectiveStatus => isArchived ? status : freshnessStatus;

  /// Доля прожитого срока хранения (0..1) для прогресс-индикатора.
  double get lifeProgress {
    final start = purchaseDate ?? createdAt;
    final total = expiryDate.difference(start).inSeconds;
    if (total <= 0) return 1.0;
    final passed = DateTime.now().difference(start).inSeconds;
    return (passed / total).clamp(0.0, 1.0);
  }

  /// Payload для Supabase (snake_case, без локальных флагов).
  Map<String, dynamic> toSupabase() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'brand': brand,
        'barcode': barcode,
        'category': category,
        'zone_id': zoneId,
        'expiry_date': expiryDate.toIso8601String(),
        'purchase_date': purchaseDate?.toIso8601String(),
        'opened_date': openedDate?.toIso8601String(),
        'quantity': quantity,
        'unit': unit,
        'price': price,
        'note': note,
        'image_path': imagePath,
        'add_method': addMethod,
        'status': status,
        'notified': notified,
        'consumed_at': consumedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'is_deleted': isDeleted,
      };

  static Product fromSupabase(Map<String, dynamic> row) => Product(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        name: row['name'] as String,
        brand: row['brand'] as String?,
        barcode: row['barcode'] as String?,
        category: row['category'] as String?,
        zoneId: (row['zone_id'] as String?) ?? AppConstants.zoneFridge,
        expiryDate: DateTime.parse(row['expiry_date'] as String),
        purchaseDate: _parseNullable(row['purchase_date']),
        openedDate: _parseNullable(row['opened_date']),
        quantity: (row['quantity'] as num?)?.toInt() ?? 1,
        unit: (row['unit'] as String?) ?? 'pcs',
        price: (row['price'] as num?)?.toDouble(),
        note: row['note'] as String?,
        imagePath: row['image_path'] as String?,
        addMethod: (row['add_method'] as String?) ?? AppConstants.addManual,
        status: (row['status'] as String?) ?? AppConstants.statusFresh,
        notified: (row['notified'] as bool?) ?? false,
        consumedAt: _parseNullable(row['consumed_at']),
        createdAt: _parseNullable(row['created_at']) ?? DateTime.now().toUtc(),
        updatedAt: _parseNullable(row['updated_at']) ?? DateTime.now().toUtc(),
        isDirty: false,
        isDeleted: (row['is_deleted'] as bool?) ?? false,
      );

  static DateTime? _parseNullable(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}
