import '../utils/product_matcher.dart';

/// Разбор голосовой команды вида
/// «молоко до пятницы», «добавь курицу на 3 дня», «яйца в морозилку».
class VoiceParser {
  static VoiceCommand parse(String phrase) {
    var text = _normalizeSpokenNumbers(phrase.toLowerCase().trim());

    // Убираем командные слова.
    for (final prefix in _commandWords) {
      text = text.replaceAll(_wholeWord(RegExp.escape(prefix)), ' ');
    }

    final zone = _extractZone(text);
    final expiry = _extractExpiry(text);
    final price = _extractPrice(text);
    final brand = _extractLabeledText(text, _brandLabel);
    final categoryPhrase = _extractLabeledText(text, _categoryLabel);
    final categorySelection = _resolveCategory(categoryPhrase?.value);
    final openingDays = _extractOpeningDays(text);
    final note = _extractLabeledText(text, _noteLabel);

    var name = text;
    for (final match in [
      price?.matchedText,
      brand?.matchedText,
      categoryPhrase?.matchedText,
      openingDays?.matchedText,
      note?.matchedText,
    ]) {
      if (match != null && match.isNotEmpty) {
        name = name.replaceFirst(match, ' ');
      }
    }
    for (final pattern in _stripPatterns) {
      name = name.replaceAll(pattern, ' ');
    }
    name = name
        .replaceAll(
          _wholeWord(
            r'(?:цена|стоимость|бренд|марка|производитель|категория|заметка|комментарий|примечание)',
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'^[\s,;:.\-]+|[\s,;:.\-]+$'), '')
        .trim();

    final category = categorySelection?.category ??
        ProductMatcher.inferCategory(name).category;
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
      price: price?.value,
      brand: brand == null ? null : _capitalize(brand.value),
      customCategory: categorySelection?.customCategory,
      openingDays: openingDays?.value,
      note: note == null ? null : _capitalize(note.value),
    );
  }

  static _MatchedValue<double>? _extractPrice(String text) {
    // Метка «цена» позволяет распознать и фразу без слова «рублей».
    final labeled = RegExp(
      r'(?:по\s+цене|цена|стоимость)\s*(?:составляет\s*)?'
      r'(\d{1,7}(?:[.,]\d{1,2})?)'
      r'(?:\s*(?:₽|руб(?:ль|ля|лей|\.)?))?'
      r'(?:\s+(\d{1,2})\s*коп(?:ейка|ейки|еек|\.)?)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (labeled != null) {
      final value = _moneyValue(labeled.group(1), labeled.group(2));
      if (value != null) {
        return _MatchedValue(value, labeled.group(0)!);
      }
    }

    // Без метки принимаем число только рядом с валютой, чтобы количество и
    // срок годности не превращались в цену.
    final currency = RegExp(
      r'(?<![a-zа-яё])(?:за\s+)?(\d{1,7}(?:[.,]\d{1,2})?)\s*'
      r'(?:₽|руб(?:ль|ля|лей|\.)?)'
      r'(?:\s+(\d{1,2})\s*коп(?:ейка|ейки|еек|\.)?)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (currency == null) return null;
    final value = _moneyValue(currency.group(1), currency.group(2));
    return value == null ? null : _MatchedValue(value, currency.group(0)!);
  }

  static double? _moneyValue(String? rubles, String? kopecks) {
    final base = double.tryParse((rubles ?? '').replaceAll(',', '.'));
    if (base == null || base <= 0 || base > 9999999) return null;
    final coins = int.tryParse(kopecks ?? '');
    if (coins == null) return base;
    if (coins < 0 || coins > 99 || base != base.truncateToDouble()) {
      return null;
    }
    return base + coins / 100;
  }

  static _MatchedValue<int>? _extractOpeningDays(String text) {
    final match = RegExp(
      r'(?:(?:срок\s+)?после\s+(?:вскрытия|открытия)|'
      r'вскрыт(?:ую|ой)?\s+упаковк[а-яё]*|'
      r'после\s+того\s+как\s+открою)'
      r'(?:\s+(?:хранить|хранится|хранится\s+еще|годен|срок))?'
      r'[^\d]{0,18}(\d{1,3})\s*(?:день|дня|дней|сут(?:ки|ок)?)',
      caseSensitive: false,
    ).firstMatch(text);
    final value = int.tryParse(match?.group(1) ?? '');
    if (match == null || value == null || value < 1 || value > 365) {
      return null;
    }
    return _MatchedValue(value, match.group(0)!);
  }

  static _MatchedValue<String>? _extractLabeledText(
    String text,
    RegExp label,
  ) {
    final match = label.firstMatch(text);
    if (match == null) return null;
    final valueStart = match.end;
    var valueEnd = text.length;
    final tail = text.substring(valueStart);
    final stop = _featureStop.firstMatch(tail);
    if (stop != null) valueEnd = valueStart + stop.start;

    final value = text
        .substring(valueStart, valueEnd)
        .replaceAll(RegExp(r'^[\s:;,\-«"]+|[\s:;,\.\-»"]+$'), '')
        .trim();
    if (value.isEmpty) return null;
    return _MatchedValue(value, text.substring(match.start, valueEnd));
  }

  static _CategorySelection? _resolveCategory(String? phrase) {
    if (phrase == null) return null;
    var value = phrase.toLowerCase().trim();
    value = value.replaceFirst(
      RegExp(r'^(?:другое|другая|другой|прочее)\s*[:\-]?\s*'),
      '',
    );
    final source = value.isEmpty ? phrase.toLowerCase().trim() : value;
    for (final entry in _spokenCategories.entries) {
      if (entry.value.hasMatch(source)) {
        return _CategorySelection(entry.key);
      }
    }
    if (value.isEmpty) return const _CategorySelection('other');
    return _CategorySelection('other', _capitalize(value));
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

  static String _normalizeSpokenNumbers(String text) {
    final numberWords = _numberWordValues.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final followedByUnit = RegExp(
      '(?<![a-zа-яё])((?:${numberWords.map(RegExp.escape).join('|')})'
      '(?:\\s+(?:${numberWords.map(RegExp.escape).join('|')})){0,3})'
      r'(?=\s*(?:д(?:ень|ня|ней)|недел[а-яё]*|месяц[а-яё]*|'
      r'шт(?:ук[а-яё]*)?|пачк[а-яё]*|упаковк[а-яё]*|бутылк[а-яё]*|'
      r'килограмм[а-яё]*|кг|грамм[а-яё]*|г|'
      r'литр[а-яё]*|л|миллилитр[а-яё]*|мл|'
      r'руб(?:ль|ля|лей)?|коп(?:ейка|ейки|еек)?)(?![a-zа-яё]))',
      caseSensitive: false,
    );
    return text.replaceAllMapped(
      followedByUnit,
      (match) {
        final words = match.group(1)!.toLowerCase().split(RegExp(r'\s+'));
        final value = words.fold<int>(
          0,
          (sum, word) => sum + (_numberWordValues[word] ?? 0),
        );
        return value > 0 ? value.toString() : match.group(0)!;
      },
    );
  }

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

  static const Map<String, int> _numberWordValues = {
    'девятьсот': 900,
    'восемьсот': 800,
    'семьсот': 700,
    'шестьсот': 600,
    'пятьсот': 500,
    'четыреста': 400,
    'триста': 300,
    'двести': 200,
    'сто': 100,
    'девяносто': 90,
    'восемьдесят': 80,
    'семьдесят': 70,
    'шестьдесят': 60,
    'пятьдесят': 50,
    'сорок': 40,
    'тридцать': 30,
    'двадцать': 20,
    'девятнадцать': 19,
    'восемнадцать': 18,
    'семнадцать': 17,
    'шестнадцать': 16,
    'пятнадцать': 15,
    'четырнадцать': 14,
    'тринадцать': 13,
    'двенадцать': 12,
    'одиннадцать': 11,
    'десять': 10,
    'девять': 9,
    'восемь': 8,
    'семь': 7,
    'шесть': 6,
    'пять': 5,
    'четыре': 4,
    'три': 3,
    'две': 2,
    'два': 2,
    'одну': 1,
    'одно': 1,
    'одна': 1,
    'один': 1,
  };

  static final RegExp _brandLabel = _wholeWord(
    r'(?:бренд|марка|производитель)\s*[:\-]?\s*',
  );

  static final RegExp _categoryLabel = _wholeWord(
    r'(?:категория|раздел)\s*[:\-]?\s*',
  );

  static final RegExp _noteLabel = _wholeWord(
    r'(?:заметка|комментарий|примечание)\s*[:\-]?\s*',
  );

  static final RegExp _featureStop = RegExp(
    r'(?=\s+(?:(?:по\s+цене|цена|стоимость|бренд|марка|производитель|'
    r'категория|раздел|заметка|комментарий|примечание)\s*[:\-]?|'
    r'(?:(?:срок\s+)?после\s+(?:вскрытия|открытия))|'
    r'(?:в|во|на)\s+(?:морозилк[а-яё]*|холодильник[а-яё]*|шкаф[а-яё]*|полк[а-яё]*|кладов[а-яё]*)|'
    r'(?:до|на|через)\s+\d+\s*(?:день|дня|дней|недел[а-яё]*|месяц[а-яё]*)|'
    r'до\s+(?:\d{1,2}[.\-/]|[а-яё]+)|сегодня|завтра|послезавтра|'
    r'\d{1,7}(?:[.,]\d{1,2})?\s*(?:₽|руб(?:ль|ля|лей|\.)?)))',
    caseSensitive: false,
  );

  static final Map<String, RegExp> _spokenCategories = {
    'dairy': RegExp(r'^(?:молочн[а-яё]*|молочные\s+продукты)$'),
    'meat': RegExp(r'^(?:мясо|мясн[а-яё]*|колбас[а-яё]*)$'),
    'fish': RegExp(r'^(?:рыба|рыбн[а-яё]*|морепродукт[а-яё]*)$'),
    'vegetables': RegExp(r'^(?:овощи|овощн[а-яё]*)$'),
    'fruits': RegExp(r'^(?:фрукты|фруктов[а-яё]*)$'),
    'eggs': RegExp(r'^(?:яйца|яичн[а-яё]*)$'),
    'grains': RegExp(r'^(?:крупы|бакалея|хлеб|зернов[а-яё]*)$'),
    'canned': RegExp(r'^(?:консервы|консервированн[а-яё]*)$'),
    'frozen': RegExp(r'^(?:заморозка|замороженн[а-яё]*)$'),
    'condiments': RegExp(r'^(?:соусы|приправы|соус[а-яё]*)$'),
    'beverages': RegExp(r'^(?:напитки|напиток|соки|вода)$'),
    'other': RegExp(r'^(?:другое|прочее)$'),
  };

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
    this.price,
    this.brand,
    this.customCategory,
    this.openingDays,
    this.note,
  });

  final String name;
  final String zoneId;
  final DateTime expiryDate;
  final String category;
  final int quantity;
  final String unit;
  final bool hadExplicitDate;
  final double? price;
  final String? brand;
  final String? customCategory;
  final int? openingDays;
  final String? note;

  bool get isValid => name.trim().length >= 2;
}

class _MatchedValue<T> {
  const _MatchedValue(this.value, this.matchedText);

  final T value;
  final String matchedText;
}

class _CategorySelection {
  const _CategorySelection(this.category, [this.customCategory]);

  final String category;
  final String? customCategory;
}
