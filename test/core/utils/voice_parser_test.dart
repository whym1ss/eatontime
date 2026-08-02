import 'package:eat_on_time/core/utils/voice_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoiceParser', () {
    test('parses a relative date and storage zone', () {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      final command =
          VoiceParser.parse('Добавь молоко в холодильник на 5 дней');

      expect(command.name, 'Молоко');
      expect(command.zoneId, 'fridge');
      expect(command.category, 'dairy');
      expect(command.expiryDate, start.add(const Duration(days: 5)));
      expect(command.hadExplicitDate, isTrue);
      expect(command.isValid, isTrue);
    });

    test('parses quantity and freezer', () {
      final command =
          VoiceParser.parse('Положи пельмени 2 кг в морозилку на неделю');

      expect(command.name, 'Пельмени 2 кг');
      expect(command.zoneId, 'freezer');
      expect(command.quantity, 2);
      expect(command.unit, 'kg');
      expect(command.hadExplicitDate, isTrue);
    });

    test('uses inferred shelf life without an explicit date', () {
      final before = DateTime.now();
      final command = VoiceParser.parse('Добавь курицу');
      final expected = before.add(const Duration(days: 3));

      expect(command.name, 'Курицу');
      expect(command.category, 'meat');
      expect(command.hadExplicitDate, isFalse);
      expect(command.expiryDate.year, expected.year);
      expect(command.expiryDate.month, expected.month);
      expect(command.expiryDate.day, expected.day);
    });

    test('parses Russian month names', () {
      final command = VoiceParser.parse('Добавь яблоки до 15 августа');
      final now = DateTime.now();
      final expectedYear = DateTime(now.year, 8, 15)
              .isBefore(DateTime(now.year, now.month, now.day))
          ? now.year + 1
          : now.year;

      expect(command.name, 'Яблоки');
      expect(command.expiryDate, DateTime(expectedYear, 8, 15));
      expect(command.hadExplicitDate, isTrue);
    });

    test('parses Russian weekday forms', () {
      final command = VoiceParser.parse('Добавь сыр до пятницы');

      expect(command.name, 'Сыр');
      expect(command.expiryDate.weekday, DateTime.friday);
      expect(command.hadExplicitDate, isTrue);
    });

    test('parses spoken number words for dates and quantities', () {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      final command =
          VoiceParser.parse('Добавь три пачки йогурта на пять дней');

      expect(command.name, '3 пачки йогурта');
      expect(command.quantity, 3);
      expect(command.expiryDate, start.add(const Duration(days: 5)));
      expect(command.hadExplicitDate, isTrue);
    });
  });
}
