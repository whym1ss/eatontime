import 'package:freezed_annotation/freezed_annotation.dart';

part 'waste_entry.freezed.dart';
part 'waste_entry.g.dart';

@freezed
class WasteEntry with _$WasteEntry {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory WasteEntry({
    String? id,
    required String userId,
    String? productId,
    required String productName,
    String? category,
    DateTime? expiryDate,
    required DateTime wastedDate,
    @Default('expired') String reason,
    double? estimatedValue,
    required DateTime createdAt,
  }) = _WasteEntry;

  factory WasteEntry.fromJson(Map<String, dynamic> json) =>
      _$WasteEntryFromJson(json);
}
