import '../utils/product_matcher.dart';

/// Разбор голосовой команды вида
/// «молоко до пятницы», «добавь курицу на 3 дня», «яйца в морозилку».
class VoiceParser {
  static VoiceCommand parse(String phrase) {
    var text = phrase.toLowerCase().trim();

    // Убираем командные слова.
    for (final prefix in _commandWords) {
      text = text.replaceAll(_wholeWord(RegExp.escape(prefix)), ' ');
    }

    final zone = _extractZone(text);
    final expiry = _extractExpiry(text);

    var name = text;
    for (final pattern in _stripPatterns) {
      name = name.replaceAll(pattern, ' ');
    }
    name = name.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

    final category = ProductMatcher.inferCategory(name).category;
    final (qty, unit) = ProductMatcher.extractQuantity(text);

    final resolvedExpiry = expiry ??
        DateTime.now().add(
          Duration(
            days: ProductMatcher.estimateShelfLife(
              category,
              zone ?? 'fridge',
            ),
          ),
        );

    return VoiceCommand(
      name: _capitalize(name),
      zoneId: zone ?? 'fridge',
      expiryDate: resolvedExpiry,
      category: category,
      quantity: qty,
      unit: unit,
      hadExplicitDate: expiry != null,
    );
  }

  static String? _extractZone(String text) {
    if (RegExp(r'морозил|заморо|freezer').hasMatch(text)) return 'freezer';
    if (RegExp(r'шкаф|полк|кладов|pantry').hasMatch(text)) return 'pantry';
    if (RegExp(r'холодильник|fridge').hasMatch(text)) return 'fridge';
    return null;
  }

  static DateTime? _extractExpiry(String text) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (_wholeWord('сегодня').hasMatch(text)) return today;
    if (_wholeWord('завтра').hasMatch(text)) {
      return today.add(const Duration(days: 1));
    }
    if (RegExp(r'послезавтра').hasMatch(text)) {
      return today.add(const Duration(days: 2));
    }

    // «на 5 дней», «через 3 дня», «на 2 недели», «на месяц»
    final rel = RegExp(
            r'(?:на|через)\s+(\d+)\s*(день|дня|дней|недел[а-яё]*|месяц[а-яё]*)')
        .firstMatch(text);
    if (rel != null) {
      final n = int.parse(rel.group(1)!);
      final unit = rel.group(2)!;
      if (unit.startsWith('недел')) {
        return today.add(Duration(days: n * 7));
      }
      if (unit.startsWith('месяц')) {
        return DateTime(today.year, today.month + n, today.day);
      }
      return today.add(Duration(days: n));
    }

    if (RegExp(r'на\s+недел').hasMatch(text)) {
      return today.add(const Duration(days: 7));
    }
    if (RegExp(r'на\s+месяц').hasMatch(text)) {
      return DateTime(today.year, today.month + 1, today.day);
    }

    // «до пятницы»
    for (final entry in _weekdays.entries) {
      if (RegExp('до\\s+${entry.key}').hasMatch(text)) {
        var delta = entry.value - today.weekday;
        if (delta <= 0) delta += 7;
        return today.add(Duration(days: delta));
      }
    }

    // «до 15 августа»
    final dateMatch =
        RegExp(r'до\s+(\d{1,2})\s+(' + _months.keys.join('|') + r')')
            .firstMatch(text);
    if (dateMatch != null) {
      final day = int.parse(dateMatch.group(1)!);
      final monthText = dateMatch.group(2)!;
      final month = _months.entries
          .firstWhere(
            (entry) => RegExp('^(?:${entry.key})\$').hasMatch(monthText),
          )
          .value;
      var year = today.year;
      final candidate = DateTime(year, month, day);
      if (candidate.isBefore(today)) year++;
      return DateTime(year, month, day);
    }

    // «до 15.08» / «до 15.08.2026»
    final numeric = RegExp(r'до\s+(\d{1,2})[.\-/](\d{1,2})(?:[.\-/](\d{2,4}))?')
        .firstMatch(text);
    if (numeric != null) {
      final day = int.parse(numeric.group(1)!);
      final month = int.parse(numeric.group(2)!);
      final rawYear = numeric.group(3);
      var year = rawYear == null
          ? today.year
          : (rawYear.length == 2
              ? 2000 + int.parse(rawYear)
              : int.parse(rawYear));
      if (rawYear == null && DateTime(year, month, day).isBefore(today)) {
        year++;
      }
      return DateTime(year, month, day);
    }

    return null;
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Dart treats `\b` and `\w` as ASCII-only, so explicit boundaries are
  /// required for Russian words.
  static RegExp _wholeWord(String expression) => RegExp(
        '(?<![a-zа-яё])(?:$expression)(?![a-zа-яё])',
        caseSensitive: false,
      );

  static const _commandWords = [
    'добавь',
    'добавить',
    'запиши',
    'записать',
    'положи',
    'положил',
    'купил',
    'купила',
    'купили',
    'внеси',
    'сохрани',
  ];

  static final _stripPatterns = [
    _wholeWord(
      r'(?:в|во|на)\s+(?:морозилк[а-яё]*|холодильник[а-яё]*|шкаф[а-яё]*|полк[а-яё]*|кладов[а-яё]*)',
    ),
    _wholeWord(
      r'(?:до|на|через)\s+\d+\s*(?:день|дня|дней|недел[а-яё]*|месяц[а-яё]*)',
    ),
    _wholeWord(r'до\s+\d{1,2}[.\-/]\d{1,2}(?:[.\-/]\d{2,4})?'),
    _wholeWord(r'до\s+\d{1,2}\s+[а-яё]+'),
    _wholeWord(r'до\s+[а-яё]+'),
    _wholeWord(r'(?:сегодня|завтра|послезавтра)'),
    _wholeWord(r'на\s+(?:недел[а-яё]*|месяц[а-яё]*)'),
  ];

  static const _weekdays = {
    'понедельник[а-яё]*': DateTime.monday,
    'вторник[а-яё]*': DateTime.tuesday,
    'сред[а-яё]+': DateTime.wednesday,
    'четверг[а-яё]*': DateTime.thursday,
    'пятниц[а-яё]+': DateTime.friday,
    'суббот[а-яё]+': DateTime.saturday,
    'воскресень[а-яё]+': DateTime.sunday,
  };

  static const _months = {
    'январ[а-яё]*': 1,
    'феврал[а-яё]*': 2,
    'март[а-яё]*': 3,
    'апрел[а-яё]*': 4,
    'ма[йяюе]': 5,
    'июн[а-яё]*': 6,
    'июл[а-яё]*': 7,
    'август[а-яё]*': 8,
    'сентябр[а-яё]*': 9,
    'октябр[а-яё]*': 10,
    'ноябр[а-яё]*': 11,
    'декабр[а-яё]*': 12,
  };
}

class VoiceCommand {
  const VoiceCommand({
    required this.name,
    required this.zoneId,
    required this.expiryDate,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.hadExplicitDate,
  });

  final String name;
  final String zoneId;
  final DateTime expiryDate;
  final String category;
  final int quantity;
  final String unit;
  final bool hadExplicitDate;

  bool get isValid => name.trim().length >= 2;
}
