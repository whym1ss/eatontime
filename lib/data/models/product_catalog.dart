import 'package:freezed_annotation/freezed_annotation.dart';

part 'product_catalog.freezed.dart';
part 'product_catalog.g.dart';

@freezed
class ProductCatalog with _$ProductCatalog {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory ProductCatalog({
    String? id,
    required String name,
    String? brand,
    String? barcode,
    String? category,
    int? defaultExpiryFridge,
    int? defaultExpiryFreezer,
    int? defaultExpiryPantry,
    @Default([]) List<String> ocrKeywords,
    @Default([]) List<String> voiceAliases,
    String? imageUrl,
  }) = _ProductCatalog;

  factory ProductCatalog.fromJson(Map<String, dynamic> json) =>
      _$ProductCatalogFromJson(json);
}
