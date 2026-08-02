import 'package:eat_on_time/data/repositories/product_repository.dart';
import 'package:eat_on_time/data/models/product_resolution.dart';
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

  test('builds leading-zero lookup candidates without changing the scan', () {
    final candidates = service.gtinLookupCandidates('034000470693');

    expect(candidates.first, '034000470693');
    expect(candidates, contains('0034000470693'));
    expect(candidates, contains('00034000470693'));
    expect(
      service.normalizeOpenFoodFactsBarcode('00034000470693'),
      '0034000470693',
    );
  });

  test('validates GS1 check digit before a public lookup', () {
    expect(service.isValidGtin('3017624010701'), isTrue);
    expect(service.isValidGtin('3017624010702'), isFalse);
    expect(service.isValidGtin('code:3017624010701'), isFalse);
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

  test('parses localized Open Food Facts product and package quantity', () {
    const code = ParsedScanCode(
      raw: '034000470693',
      gtin: '034000470693',
    );
    final result = service.parseOpenFoodFactsPayload(
      {
        'status': 'success',
        'product': {
          'code': '0034000470693',
          'product_name_ru-RU': '  Молоко   ультрапастеризованное  ',
          'product_name': 'Milk',
          'brands': 'Добрая ферма',
          'categories_tags': ['ru:молочные-продукты'],
          'quantity': '6 × 0,25 л',
          'image_front_small_url':
              'https://images.openfoodfacts.org/product.jpg',
        },
      },
      code,
    );

    expect(result, isNotNull);
    expect(result!.name!.value, 'Молоко ультрапастеризованное');
    expect(result.brand!.value, 'Добрая ферма');
    expect(result.category!.value, 'dairy');
    expect(result.quantity, 1500);
    expect(result.unit, 'ml');
    expect(result.imageUrl, startsWith('https://'));
  });

  test('uses structured Open Food Facts quantity when display text is absent',
      () {
    const code = ParsedScanCode(
      raw: '3017624010701',
      gtin: '3017624010701',
    );
    final result = service.parseOpenFoodFactsPayload(
      {
        'status': 1,
        'product': {
          'code': '3017624010701',
          'product_name': 'Hazelnut spread',
          'product_quantity': '1.5',
          'product_quantity_unit': 'kg',
        },
      },
      code,
    );

    expect(result, isNotNull);
    expect(result!.quantity, 1500);
    expect(result.unit, 'g');
  });

  test('rejects not-found, placeholder, and mismatched OFF records', () {
    const code = ParsedScanCode(
      raw: '3017624010701',
      gtin: '3017624010701',
    );

    expect(
      service.parseOpenFoodFactsPayload(
        {'status': 0, 'product': <String, dynamic>{}},
        code,
      ),
      isNull,
    );
    expect(
      service.parseOpenFoodFactsPayload(
        {
          'product': {'code': '3017624010701', 'product_name': 'Spread'},
        },
        code,
      ),
      isNull,
    );
    expect(
      service.parseOpenFoodFactsPayload(
        {
          'status': 'success',
          'product': {'product_name': 'Spread'},
        },
        code,
      ),
      isNull,
    );
    expect(
      service.parseOpenFoodFactsPayload(
        {
          'status': 'success',
          'product': {'code': '3017624010701', 'product_name': 'Product'},
        },
        code,
      ),
      isNull,
    );
    expect(
      service.parseOpenFoodFactsPayload(
        {
          'status': 'success',
          'product': {'code': '5449000000996', 'product_name': 'Cola'},
        },
        code,
      ),
      isNull,
    );
  });
}
