import 'dart:io';

import 'package:eat_on_time/data/local/product_entity.dart';
import 'package:eat_on_time/data/local/product_local_source.dart';
import 'package:eat_on_time/data/repositories/product_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

void main() {
  late Directory tempDir;
  late Isar isar;
  late ProductLocalSource local;
  late ProductRepository repository;

  setUpAll(() => Isar.initializeIsarCore(download: true));

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('eat_on_time_test_');
    isar = await Isar.open(
      [ProductEntitySchema],
      directory: tempDir.path,
      name: 'test_${DateTime.now().microsecondsSinceEpoch}',
    );
    local = ProductLocalSource(isar);
    repository = ProductRepository(
      local: local,
      remote: null,
      userId: 'local-user',
    );
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('batch insert is rejected before writing when limit is exceeded',
      () async {
    await repository.add(
      name: 'Молоко',
      expiryDate: DateTime.now().add(const Duration(days: 5)),
      maxActiveProducts: 2,
    );

    await expectLater(
      repository.addMany(
        [
          ProductDraft(
            name: 'Хлеб',
            expiryDate: DateTime.now().add(const Duration(days: 3)),
          ),
          ProductDraft(
            name: 'Яблоки',
            expiryDate: DateTime.now().add(const Duration(days: 7)),
          ),
        ],
        maxActiveProducts: 2,
      ),
      throwsA(isA<ProductLimitException>()),
    );

    expect(await repository.countActive(), 1);
  });

  test('migrates local rows to a remote user and marks them dirty', () async {
    final product = await repository.add(
      name: 'Сыр',
      expiryDate: DateTime.now().add(const Duration(days: 10)),
      maxActiveProducts: 10,
    );

    expect(await local.migrateUser('local-user', 'remote-user'), 1);
    final migrated = await local.getByUuid(product.id);

    expect(migrated?.userId, 'remote-user');
    expect(migrated?.isDirty, isTrue);
    expect(await repository.countActive(), 0);
  });
}
