import 'package:isar/isar.dart';

import '../../core/constants/app_constants.dart';
import '../models/product.dart';

part 'product_entity.g.dart';

/// Локальная (offline-first) запись продукта в Isar.
@collection
class ProductEntity {
  Id isarId = Isar.autoIncrement;

  @Index(unique: true, replace: true)
  late String uuid;

  @Index()
  late String userId;

  @Index(type: IndexType.value, caseSensitive: false)
  late String name;

  String? brand;

  @Index()
  String? barcode;

  String? category;

  @Index()
  late String zoneId;

  @Index()
  late DateTime expiryDate;

  DateTime? purchaseDate;
  DateTime? openedDate;

  late int quantity;
  late String unit;
  double? price;
  String? note;
  String? imagePath;
  late String addMethod;

  @Index()
  late String status;

  late bool notified;
  DateTime? consumedAt;

  late DateTime createdAt;
  late DateTime updatedAt;

  /// Есть локальные изменения, не отправленные на сервер.
  @Index()
  late bool isDirty;

  /// Мягкое удаление — строка ждёт синхронизации удаления.
  late bool isDeleted;

  ProductEntity();

  factory ProductEntity.fromModel(Product p) => ProductEntity()
    ..uuid = p.id
    ..userId = p.userId
    ..name = p.name
    ..brand = p.brand
    ..barcode = p.barcode
    ..category = p.category
    ..zoneId = p.zoneId
    ..expiryDate = p.expiryDate
    ..purchaseDate = p.purchaseDate
    ..openedDate = p.openedDate
    ..quantity = p.quantity
    ..unit = p.unit
    ..price = p.price
    ..note = p.note
    ..imagePath = p.imagePath
    ..addMethod = p.addMethod
    ..status = p.status
    ..notified = p.notified
    ..consumedAt = p.consumedAt
    ..createdAt = p.createdAt
    ..updatedAt = p.updatedAt
    ..isDirty = p.isDirty
    ..isDeleted = p.isDeleted;

  Product toModel() => Product(
        id: uuid,
        userId: userId,
        name: name,
        brand: brand,
        barcode: barcode,
        category: category,
        zoneId: zoneId,
        expiryDate: expiryDate,
        purchaseDate: purchaseDate,
        openedDate: openedDate,
        quantity: quantity,
        unit: unit,
        price: price,
        note: note,
        imagePath: imagePath,
        addMethod: addMethod,
        status: status,
        notified: notified,
        consumedAt: consumedAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
        isDirty: isDirty,
        isDeleted: isDeleted,
      );

  /// Статус свежести, пересчитанный на текущий момент.
  @ignore
  String get freshnessStatus => toModel().freshnessStatus;

  @ignore
  bool get isArchived =>
      status == AppConstants.statusConsumed ||
      status == AppConstants.statusWasted;
}
