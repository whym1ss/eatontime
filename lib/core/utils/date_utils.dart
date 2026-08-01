import 'package:intl/intl.dart';

class AppDateUtils {
  static final DateFormat _dateFormat = DateFormat('dd MMM', 'ru');
  static final DateFormat _fullDateFormat = DateFormat('dd MMMM yyyy', 'ru');
  static final DateFormat _isoFormat = DateFormat('yyyy-MM-dd');

  /// "30 июл"
  static String shortDate(DateTime date) => _dateFormat.format(date);

  /// "30 июля 2026"
  static String fullDate(DateTime date) => _fullDateFormat.format(date);

  /// "2026-07-30"
  static String isoDate(DateTime date) => _isoFormat.format(date);

  /// Полночь локального календарного дня без компонента времени.
  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// Разница между календарными днями, не зависящая от времени суток.
  static int calendarDaysBetween(DateTime from, DateTime to) =>
      dateOnly(to).difference(dateOnly(from)).inDays;

  static int daysUntil(DateTime date, {DateTime? from}) =>
      calendarDaysBetween(from ?? DateTime.now(), date);

  /// Human-readable days remaining
  static String daysRemaining(int days) {
    if (days < 0) return 'просрочено';
    if (days == 0) return 'сегодня';
    if (days == 1) return 'завтра';
    if (days >= 7 && days < 14) return '${days ~/ 7} нед.';
    if (days >= 14) return '${days ~/ 7} нед.';
    return '$days дн.';
  }

  /// Human-readable "bought X days ago"
  static String daysSince(DateTime date) {
    final days = calendarDaysBetween(date, DateTime.now());
    if (days < 0) return 'в будущем';
    if (days == 0) return 'сегодня';
    if (days == 1) return 'вчера';
    return '$days дн. назад';
  }
}
