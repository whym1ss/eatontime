import 'package:eat_on_time/core/utils/date_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppDateUtils', () {
    test('compares calendar days instead of elapsed 24-hour periods', () {
      final lateToday = DateTime(2026, 7, 29, 23, 59);
      final earlyTomorrow = DateTime(2026, 7, 30, 0, 1);

      expect(
        AppDateUtils.calendarDaysBetween(lateToday, earlyTomorrow),
        1,
      );
      expect(AppDateUtils.calendarDaysBetween(lateToday, lateToday), 0);
    });

    test('formats future dates without negative day counts', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));

      expect(AppDateUtils.daysSince(tomorrow), 'в будущем');
    });
  });
}
