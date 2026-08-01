import 'package:freezed_annotation/freezed_annotation.dart';

part 'storage_zone.freezed.dart';
part 'storage_zone.g.dart';

@freezed
class StorageZone with _$StorageZone {
  const factory StorageZone({
    required String id,
    required String name,
    @Default(0) int order,
    @Default(true) bool isDefault,
  }) = _StorageZone;

  factory StorageZone.fromJson(Map<String, dynamic> json) =>
      _$StorageZoneFromJson(json);

  static const List<StorageZone> defaults = [
    StorageZone(id: 'fridge', name: 'Холодильник', order: 0),
    StorageZone(id: 'freezer', name: 'Морозилка', order: 1),
    StorageZone(id: 'pantry', name: 'Шкаф', order: 2),
  ];
}
