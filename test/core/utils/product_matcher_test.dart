import 'package:eat_on_time/core/utils/product_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProductMatcher', () {
    test('infers common Russian product categories', () {
      expect(ProductMatcher.inferCategory('Молоко 3,2%').category, 'dairy');
      expect(ProductMatcher.inferCategory('Филе курицы').category, 'meat');
      expect(ProductMatcher.inferCategory('Яблоки').category, 'fruits');
      expect(
        ProductMatcher.inferCategory('Масло оливковое').category,
        'condiments',
      );
      expect(
        ProductMatcher.inferCategory('Масло сливочное').category,
        'dairy',
      );
      expect(ProductMatcher.inferCategory('неизвестный продукт').category,
          'other');
    });

    test('uses category shelf life and zone fallback', () {
      expect(ProductMatcher.estimateShelfLife('dairy', 'fridge'), 7);
      expect(ProductMatcher.estimateShelfLife('meat', 'freezer'), 180);
      expect(ProductMatcher.estimateShelfLife('unknown', 'pantry'), 365);
    });

    test('parses receipt lines with comma and dot prices', () {
      final comma = ProductMatcher.parseReceiptLine('Молоко 89,90');
      final dot = ProductMatcher.parseReceiptLine('Хлеб 54.50');

      expect(comma?.productName, 'Молоко');
      expect(comma?.price, 89.90);
      expect(dot?.productName, 'Хлеб');
      expect(dot?.price, 54.50);
      expect(ProductMatcher.parseReceiptLine('ИТОГО'), isNull);
    });

    test('extracts quantity and normalized unit', () {
      expect(ProductMatcher.extractQuantity('Яйца 10 шт'), (10, 'pcs'));
      expect(ProductMatcher.extractQuantity('Молоко 2 л'), (2, 'l'));
      expect(ProductMatcher.extractQuantity('Сыр'), (1, 'pcs'));
    });
  });
}
