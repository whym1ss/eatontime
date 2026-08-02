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

  /// Parse receipt line: extract product name and price
  static ReceiptLine? parseReceiptLine(String line) {
    final pricePattern = RegExp(r'(\d+[.,]\d{2})\s*$');
    final match = pricePattern.firstMatch(line.trim());
    if (match == null) return null;

    final productName = line.substring(0, match.start).trim();
    final price = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    if (productName.isEmpty) return null;

    return ReceiptLine(productName: productName, price: price);
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
  ReceiptLine({required this.productName, this.price});
}
