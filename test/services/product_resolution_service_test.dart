import 'package:eat_on_time/data/repositories/product_repository.dart';
import 'package:eat_on_time/services/product_resolution_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockProductRepository extends Mock implements ProductRepository {}

class _MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  late ProductResolutionService service;

  setUp(() {
    service = ProductResolutionService(
      repository: _MockProductRepository(),
      preferences: _MockSharedPreferences(),
    );
  });

  test('parses EAN barcode', () {
    final code = service.parseCode('4601234567890');

    expect(code.gtin, '4601234567890');
    expect(code.isFiscalReceipt, isFalse);
  });

  test('parses compact GS1 Data Matrix with scanner prefix', () {
    final code = service.parseCode(
      ']d201046012345678901725123110LOT42\u001d21ABC',
    );

    expect(code.gtin, '04601234567890');
    expect(code.expiryDate, DateTime(2025, 12, 31));
    expect(code.batch, 'LOT42');
    expect(code.serial, 'ABC');
  });

  test('parses GS1 Digital Link', () {
    final code = service.parseCode(
      'https://id.gs1.org/01/04601234567890/17/251231/10/LOT42',
    );

    expect(code.gtin, '04601234567890');
    expect(code.expiryDate, DateTime(2025, 12, 31));
    expect(code.batch, 'LOT42');
  });

  test('parses fiscal receipt QR metadata', () {
    const raw = 't=20260802T1234&s=123.45&fn=9999078900012345&i=456&fp=789&n=1';
    final receipt = service.parseFiscalReceiptQr(raw);
    final code = service.parseCode(raw);

    expect(receipt, isNotNull);
    expect(receipt!.dateTime, DateTime(2026, 8, 2, 12, 34));
    expect(receipt.total, 123.45);
    expect(receipt.fiscalDocument, '456');
    expect(code.isFiscalReceipt, isTrue);
  });
}
