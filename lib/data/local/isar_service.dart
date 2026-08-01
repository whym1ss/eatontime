import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'product_entity.dart';

/// Обёртка над Isar: единая точка инициализации и доступа к БД.
class IsarService {
  IsarService._(this.isar);

  final Isar isar;

  static IsarService? _instance;

  static IsarService get instance {
    final i = _instance;
    if (i == null) {
      throw StateError(
          'IsarService не инициализирован. Вызовите IsarService.open() в main().');
    }
    return i;
  }

  static bool get isReady => _instance != null;

  static Future<IsarService> open() async {
    if (_instance != null) return _instance!;
    final dir = await getApplicationDocumentsDirectory();
    final isar = await Isar.open(
      [ProductEntitySchema],
      directory: dir.path,
      name: 'eat_on_time',
    );
    _instance = IsarService._(isar);
    return _instance!;
  }

  /// Для фонового изолята (workmanager): открывает существующий инстанс либо новый.
  static Future<Isar> openBackground() async {
    final existing = Isar.getInstance('eat_on_time');
    if (existing != null) return existing;
    final dir = await getApplicationDocumentsDirectory();
    return Isar.open(
      [ProductEntitySchema],
      directory: dir.path,
      name: 'eat_on_time',
    );
  }

  Future<void> clear() => isar.writeTxn(() => isar.clear());

  Future<void> close() async {
    await isar.close();
    _instance = null;
  }
}
