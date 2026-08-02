import 'package:eat_on_time/services/ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OcrService receipt parsing', () {
    test('keeps products and removes fiscal and payment metadata', () {
      final items = OcrService.parseReceiptLines([
        'ООО «Ромашка»',
        'Магазин у дома',
        'Адрес: г. Москва, ул. Лесная, 5',
        'ИНН 7701234567',
        'КАССОВЫЙ ЧЕК № 183',
        '02.08.2026 15:42',
        'Молоко пастеризованное 3,2% 89,90',
        'Хлеб Бородинский',
        '2 шт x 45,00 = 90,00',
        'СКИДКА 5,00',
        'ИТОГО 179,90',
        'ОПЛАТА КАРТОЙ 179,90',
        'НДС 20% 29,98',
        'ФН: 9287440300999999',
        'ФД: 45678',
        'ФП: 1234567890',
        'www.example.ru',
        'СПАСИБО ЗА ПОКУПКУ',
      ]);

      expect(items, hasLength(2));
      expect(items[0].name, 'Молоко пастеризованное 3,2%');
      expect(items[0].price, closeTo(89.90, 0.001));
      expect(items[1].name, 'Хлеб Бородинский');
      expect(items[1].price, closeTo(90, 0.001));
      expect(items[1].quantity, 2);
      expect(items[1].unit, 'pcs');
    });

    test('joins a wrapped product name and package size', () {
      final items = OcrService.parseReceiptLines([
        'Сыр Российский',
        'сливочный 45%',
        '200 г',
        '1 x 219,99 = 219,99',
      ]);

      expect(items, hasLength(1));
      expect(items.single.name, 'Сыр Российский сливочный 45% 200 г');
      expect(items.single.price, closeTo(219.99, 0.001));
      expect(items.single.quantity, 1);
    });

    test('pairs a standalone price only with a pending product name', () {
      final items = OcrService.parseReceiptLines([
        'Кефир 1%',
        '79,50 ₽',
        '1234567890123',
        '999,99',
      ]);

      expect(items, hasLength(1));
      expect(items.single.name, 'Кефир 1%');
      expect(items.single.price, closeTo(79.50, 0.001));
    });

    test('understands a quantity calculation printed without equals sign', () {
      final items = OcrService.parseReceiptLines([
        'Творог мягкий',
        '2 x 69,90 139,80',
      ]);

      expect(items, hasLength(1));
      expect(items.single.name, 'Творог мягкий');
      expect(items.single.quantity, 2);
      expect(items.single.price, closeTo(139.80, 0.001));
    });

    test('does not emit arbitrary OCR text without a price', () {
      final items = OcrService.parseReceiptLines([
        'Рекламный текст магазина',
        'Участвуйте в розыгрыше',
        'Кассир Иванова',
      ]);

      expect(items, isEmpty);
    });
  });
}
