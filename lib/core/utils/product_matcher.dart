/// Matches OCR/barcode/voice input to product catalog entries
class ProductMatcher {
  /// Fuzzy-match a product name against category keywords
  /// Returns best-guess category and confidence
  static CategoryMatch inferCategory(String productName) {
    final name = productName.toLowerCase().trim();

    // Растительное масло иначе перехватывается молочной категорией из-за
    // общего корня «масл» (нужного для сливочного масла).
    if (RegExp(r'(?:подсолнеч|оливков|растительн|льнян)[а-яё]*\s+масл')
            .hasMatch(name) ||
        RegExp(r'масл[а-яё]*\s+(?:подсолнеч|оливков|растительн|льнян)')
            .hasMatch(name)) {
      return CategoryMatch('condiments', 0.8);
    }

    // Check each category's keywords
    for (final entry in _categoryKeywords.entries) {
      if (entry.value.any((keyword) => name.contains(keyword))) {
        return CategoryMatch(entry.key, 0.7);
      }
    }

    return CategoryMatch('other', 0.3);
  }

  /// Estimate shelf life in days by category and storage zone
  static int estimateShelfLife(String category, String zoneId) {
    final categoryDefaults = _shelfLifeByCategory[category];
    if (categoryDefaults != null) {
      final days = categoryDefaults[zoneId];
      if (days != null && days > 0) return days;
    }
    // Fallback per zone
    return _zoneFallback[zoneId] ?? 7;
  }

  /// Наиболее безопасное типичное место хранения. Пользователь всегда может
  /// изменить его, после чего срок пересчитывается.
  static String recommendZone(String category) => switch (category) {
        'grains' || 'canned' || 'condiments' || 'beverages' => 'pantry',
        'frozen' => 'freezer',
        _ => 'fridge',
      };

  /// Ориентировочный срок после вскрытия. Используется только как подсказка,
  /// если OCR/каталог не дали точное значение.
  static int estimateAfterOpening(String category) =>
      _afterOpeningDays[category] ?? 3;

  /// Короткие контекстные действия после добавления продукта.
  static List<String> smartTips(
    String category, {
    required String zoneId,
    int? daysLeft,
    bool duplicate = false,
  }) {
    final tips = <String>[];
    if (duplicate) tips.add('Такой продукт уже есть — поставьте новый за ним.');
    if (daysLeft != null && daysLeft <= 3) {
      tips.add('Поставьте ближе к краю, чтобы использовать первым.');
    }
    if ((category == 'meat' || category == 'fish') && zoneId != 'freezer') {
      tips.add('Если не съедите за 1–2 дня, заморозьте часть.');
    }
    if (category == 'vegetables') {
      tips.add('Подойдёт для салата, супа или овощного рагу.');
    } else if (category == 'fruits') {
      tips.add('Используйте в смузи, каше или быстрой выпечке.');
    } else if (category == 'dairy') {
      tips.add('Можно добавить в омлет, соус или выпечку.');
    } else if (category == 'meat' || category == 'fish') {
      tips.add('Запланируйте горячее блюдо на ближайшие дни.');
    }
    return tips.take(3).toList();
  }

  /// Parse a receipt item printed on one line.
  ///
  /// A price is deliberately required: arbitrary OCR text from the header and
  /// footer must never turn into products. Multi-line positions are assembled
  /// by [OcrService] before they get here.
  static ReceiptLine? parseReceiptLine(String line) {
    final normalized = line
        .replaceAll(RegExp(r'[\u00a0\t]+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    if (normalized.length < 4 || isReceiptMetadata(normalized)) return null;

    // Integer prices are accepted only with an explicit currency sign. This
    // keeps package sizes and receipt numbers from being interpreted as money.
    final pricePattern = RegExp(
      r'(?<!\d)(\d{1,7}(?:[.,]\d{2}))\s*(?:₽|руб(?:ль|ля|лей|\.)?)?\s*$|'
      r'(?<!\d)(\d{1,7})\s*(?:₽|руб(?:ль|ля|лей|\.)?)\s*$',
      caseSensitive: false,
    );
    final match = pricePattern.firstMatch(normalized);
    if (match == null) return null;

    final rawPrice = match.group(1) ?? match.group(2);
    final price = double.tryParse(rawPrice!.replaceAll(',', '.'));
    if (price == null || price <= 0) return null;

    var productName = normalized.substring(0, match.start).trim();
    final calculation = RegExp(
      r'(\d+(?:[.,]\d{1,3})?)\s*(шт(?:ук[а-яё]*)?)?\s*[xх×*]\s*'
      r'\d+(?:[.,]\d{1,2})',
      caseSensitive: false,
    ).firstMatch(productName);
    final calculatedQuantity = double.tryParse(
      (calculation?.group(1) ?? '').replaceAll(',', '.'),
    );

    productName = productName
        .replaceAll(
          RegExp(
            r'(?:^|\s+)\d+(?:[.,]\d{1,3})?\s*(?:шт(?:ук[а-яё]*)?)?\s*'
            r'[xх×*]\s*\d+(?:[.,]\d{1,2})\s*(?:=)?\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'(?:^|\s+)\d+(?:[.,]\d{1,3})?\s*(?:шт(?:ук[а-яё]*)?)?\s*'
            r'[xх×*]\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s*[=:]\s*$'), '')
        .replaceFirst(RegExp(r'^\s*\d{1,3}\s*[.)]\s*'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    if (productName.length < 2 ||
        !RegExp(r'[A-Za-zА-Яа-яЁё]{2,}').hasMatch(productName) ||
        isReceiptMetadata(productName)) {
      return null;
    }

    final extracted = extractQuantity(productName);
    final hasWholeCalculatedQuantity = calculatedQuantity != null &&
        calculatedQuantity == calculatedQuantity.roundToDouble() &&
        calculatedQuantity >= 1 &&
        calculatedQuantity <= 999;
    final quantity =
        hasWholeCalculatedQuantity ? calculatedQuantity.round() : extracted.$1;
    final unit = calculation?.group(2) != null ? 'pcs' : extracted.$2;

    return ReceiptLine(
      productName: productName,
      price: price,
      quantity: quantity,
      unit: unit,
    );
  }

  /// Whether a line belongs to receipt metadata rather than a purchased item.
  static bool isReceiptMetadata(String line) {
    final value = line
        .replaceAll(RegExp(r'[\u00a0\t]+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    if (value.isEmpty || !RegExp(r'[A-Za-zА-Яа-яЁё]').hasMatch(value)) {
      return true;
    }

    return RegExp(
      r'(?:^|\s)(?:ооо|пао|ао|ип)\s|'
      r'магазин|супермаркет|гипермаркет|торгов(?:ая|ой)\s+сет|'
      r'кассов(?:ый|ого)\s+чек|товарн(?:ый|ого)\s+чек|чек\s*№|'
      r'(?:^|\s)(?:инн|кпп|ккт|рн\s*ккт|зн\s*ккт|фн|фд|фпд?|фискальн[а-яё]*)\s*[:№#]?|'
      r'кассир|оператор|смена\s*[:№#]?|приход|возврат\s+прихода|'
      r'итог|итого|всего|подытог|сумма\s+(?:чека|покупки)|'
      r'оплат|наличн|безналичн|банк(?:овская)?\s+карт|картой|сдача|'
      r'ндс|налог|сно|система\s+налогооблож|'
      r'скидк|бонус|балл|купон|акци[яи]|экономия|'
      r'адрес\s*[:]|место\s+расчет|\b(?:ул|улица|проспект|пр-т|шоссе|пер)\.?\s+[а-яё]|'
      r'тел(?:ефон)?\s*[:+]|\+7[\s(]|e-?mail|@|https?://|www\.|\.ru(?:\s|$)|'
      r'дата\s*[:]|время\s*[:]|\d{1,2}[.\-/]\d{1,2}[.\-/]\d{2,4}\s+\d{1,2}:\d{2}|'
      r'спасибо|добро\s+пожаловать|ждем\s+вас|служба\s+поддержки|'
      r'цена\s+(?:кол|кол-во|количество)|наименовани[ея]\s+товар|'
      r'qr\s*-?\s*код|провер(?:ить|ка)\s+чек|ofd|оператор\s+фискальн|'
      r'\b(?:total|subtotal|cash|card|change|tax|receipt|cashier)\b|'
      r'thank\s+you|store\s+address|phone\s*:',
      caseSensitive: false,
    ).hasMatch(value);
  }

  /// Extract quantity and unit from product name
  /// e.g., "Молоко 1л" → (1, 'l'), "Яйца 10шт" → (10, 'pcs')
  static (int, String) extractQuantity(String name) {
    final patterns = {
      RegExp(r'(\d+)\s*л', caseSensitive: false): 'l',
      RegExp(r'(\d+)\s*мл', caseSensitive: false): 'ml',
      RegExp(r'(\d+)\s*кг', caseSensitive: false): 'kg',
      RegExp(r'(\d+)\s*г', caseSensitive: false): 'g',
      RegExp(r'(\d+)\s*шт', caseSensitive: false): 'pcs',
      RegExp(r'(\d+)\s*(?:пачк|упаковк|бутылк)[а-яё]*', caseSensitive: false):
          'pcs',
    };

    for (final entry in patterns.entries) {
      final match = entry.key.firstMatch(name);
      if (match != null) {
        final qty = int.tryParse(match.group(1)!) ?? 1;
        return (qty, entry.value);
      }
    }

    return (1, 'pcs');
  }

  static const Map<String, List<String>> _categoryKeywords = {
    'dairy': [
      'молок',
      'кефир',
      'йогурт',
      'сметан',
      'творог',
      'сыр',
      'сливк',
      'ряженк',
      'простокваш',
      'масл',
      'milk',
      'cheese',
      'yogurt',
      'cream',
    ],
    'meat': [
      'куриц',
      'говядин',
      'свинин',
      'фарш',
      'колбас',
      'сосис',
      'ветчин',
      'мяс',
      'chicken',
      'beef',
      'pork',
      'meat',
      'sausage',
    ],
    'vegetables': [
      'помидор',
      'огурц',
      'картофел',
      'морков',
      'лук',
      'капуст',
      'свекл',
      'редис',
      'кабачк',
      'баклаж',
      'перец',
      'tomato',
      'potato',
      'carrot',
    ],
    'fruits': [
      'яблок',
      'банан',
      'апельсин',
      'мандарин',
      'виноград',
      'лимон',
      'груш',
      'кив',
      'apple',
      'banana',
      'orange',
      'grape',
    ],
    'eggs': ['яйц', 'egg', 'яичн'],
    'grains': [
      'рис',
      'макарон',
      'гречк',
      'овсян',
      'круп',
      'мук',
      'хлеб',
      'rice',
      'pasta',
      'bread',
      'flour',
    ],
    'canned': ['консерв', 'can', 'тушенк', 'конфит', 'джем'],
    'frozen': [
      'заморожен',
      'морожен',
      'frozen',
      'ice cream',
      'пельмен',
      'вареник',
      'котлет',
    ],
    'condiments': [
      'соус',
      'кетчуп',
      'майонез',
      'горчиц',
      'уксус',
      'масло',
      'sauce',
      'ketchup',
      'mayo',
    ],
    'beverages': [
      'сок',
      'вод',
      'лимонад',
      'компот',
      'juice',
      'cola',
      'чай',
      'квас',
      'пив',
      'вин',
    ],
    'fish': ['рыб', 'fish', 'лосос', 'семг', 'треск', 'креветк'],
  };

  static const Map<String, Map<String, int>> _shelfLifeByCategory = {
    'dairy': {'fridge': 7, 'freezer': 90, 'pantry': 0},
    'meat': {'fridge': 3, 'freezer': 180, 'pantry': 0},
    'fish': {'fridge': 2, 'freezer': 120, 'pantry': 0},
    'vegetables': {'fridge': 7, 'freezer': 180, 'pantry': 14},
    'fruits': {'fridge': 7, 'freezer': 180, 'pantry': 5},
    'eggs': {'fridge': 21, 'freezer': 0, 'pantry': 0},
    'grains': {'fridge': 0, 'freezer': 0, 'pantry': 365},
    'canned': {'fridge': 0, 'freezer': 0, 'pantry': 730},
    'frozen': {'fridge': 0, 'freezer': 180, 'pantry': 0},
    'condiments': {'fridge': 180, 'freezer': 0, 'pantry': 365},
    'beverages': {'fridge': 30, 'freezer': 0, 'pantry': 365},
    'other': {'fridge': 7, 'freezer': 90, 'pantry': 30},
  };

  static const Map<String, int> _zoneFallback = {
    'fridge': 7,
    'freezer': 180,
    'pantry': 365,
  };

  static const Map<String, int> _afterOpeningDays = {
    'dairy': 3,
    'meat': 2,
    'fish': 1,
    'vegetables': 5,
    'fruits': 5,
    'eggs': 2,
    'canned': 2,
    'condiments': 30,
    'beverages': 3,
    'grains': 30,
    'frozen': 3,
    'other': 3,
  };
}

class CategoryMatch {
  final String category;
  final double confidence;
  CategoryMatch(this.category, this.confidence);
}

class ReceiptLine {
  final String productName;
  final double? price;
  final int quantity;
  final String unit;

  ReceiptLine({
    required this.productName,
    this.price,
    this.quantity = 1,
    this.unit = 'pcs',
  });
}
