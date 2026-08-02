import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../core/utils/product_matcher.dart';
import '../data/models/product_resolution.dart';

/// Распознавание текста чека и извлечение позиций.
class OcrService {
  OcrService._();

  static final OcrService instance = OcrService._();

  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  /// Возвращает распознанные строки-позиции чека.
  Future<List<ReceiptItem>> scanReceipt(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(input);

    final lines = <String>[
      for (final block in result.blocks)
        for (final line in block.lines) line.text,
    ];
    // Одинаковые позиции не удаляем: в чеке это могут быть разные покупки,
    // а пользователь сможет снять лишнюю галочку перед сохранением.
    return parseReceiptLines(lines);
  }

  /// Собирает товарные позиции из строк OCR. Метод открыт для unit-тестов и
  /// для повторного разбора текста без обращения к камере.
  static List<ReceiptItem> parseReceiptLines(Iterable<String> rawLines) {
    final items = <ReceiptItem>[];
    final pendingNameParts = <String>[];

    void clearPending() => pendingNameParts.clear();

    void addItem({
      required String name,
      required double price,
      int? quantity,
      String? unit,
    }) {
      final cleanName = _cleanProductName(name);
      if (!_isLikelyProductFragment(cleanName)) return;
      final match = ProductMatcher.inferCategory(cleanName);
      final extracted = ProductMatcher.extractQuantity(cleanName);
      items.add(
        ReceiptItem(
          name: cleanName,
          price: price,
          category: match.category,
          confidence: match.confidence,
          quantity: quantity ?? extracted.$1,
          unit: unit ?? extracted.$2,
        ),
      );
    }

    for (final rawLine in rawLines) {
      final line = _normalizeReceiptLine(rawLine);
      if (line.isEmpty) continue;

      final parsed = ProductMatcher.parseReceiptLine(line);
      if (parsed != null && parsed.price != null) {
        final name = [...pendingNameParts, parsed.productName].join(' ');
        addItem(
          name: name,
          price: parsed.price!,
          quantity: parsed.quantity,
          unit: parsed.unit,
        );
        clearPending();
        continue;
      }

      final calculation = _parseCalculationLine(line);
      if (calculation != null) {
        if (pendingNameParts.isNotEmpty) {
          final pendingName = pendingNameParts.join(' ');
          final extracted = ProductMatcher.extractQuantity(pendingName);
          addItem(
            name: pendingName,
            price: calculation.total,
            quantity: calculation.quantity ?? extracted.$1,
            unit: calculation.unit ?? extracted.$2,
          );
        }
        clearPending();
        continue;
      }

      final standalonePrice = _parseStandalonePrice(line);
      if (standalonePrice != null) {
        if (pendingNameParts.isNotEmpty) {
          addItem(
            name: pendingNameParts.join(' '),
            price: standalonePrice,
          );
        }
        clearPending();
        continue;
      }

      if (ProductMatcher.isReceiptMetadata(line)) {
        clearPending();
        continue;
      }

      if (_isMeasureContinuation(line) && pendingNameParts.isNotEmpty) {
        pendingNameParts.add(line);
        continue;
      }

      if (_isLikelyProductFragment(line)) {
        // Чековые принтеры обычно переносят название не более чем на три
        // строки. Ограничение не дает заголовку магазина прилипнуть к товару.
        if (pendingNameParts.length == 3) pendingNameParts.removeAt(0);
        pendingNameParts.add(line);
      } else {
        clearPending();
      }
    }

    return items;
  }

  /// Просто весь распознанный текст — для отладки/ручного разбора.
  Future<String> rawText(String imagePath) async {
    final result =
        await _recognizer.processImage(InputImage.fromFilePath(imagePath));
    return result.text;
  }

  /// Ищет срок годности на нескольких кадрах. Повторение одной даты повышает
  /// уверенность и защищает от случайных чисел на упаковке.
  Future<ExpiryScanResult> scanExpiry(List<String> imagePaths) async {
    final votes = <DateTime, int>{};
    final nameVotes = <String, int>{};
    var contextualHits = 0;
    int? openingDays;
    String? storageText;
    for (final path in imagePaths) {
      final text = await rawText(path);
      final normalized = text
          .replaceAll('О', '0')
          .replaceAll('O', '0')
          .replaceAll(RegExp(r'[|I]'), '1');
      final hasContext = RegExp(
        r'годен|употребить|срок|best\s*before|use\s*by|exp(?:iry)?',
        caseSensitive: false,
      ).hasMatch(normalized);
      if (hasContext) contextualHits++;
      for (final date in _extractDates(normalized)) {
        votes[date] = (votes[date] ?? 0) + 1 + (hasContext ? 1 : 0);
      }
      openingDays ??= _extractOpeningDays(normalized);
      storageText ??= normalized;
      final likelyName = _extractLikelyProductName(text);
      if (likelyName != null) {
        nameVotes[likelyName] = (nameVotes[likelyName] ?? 0) + 1;
      }
    }
    final suggestedName = nameVotes.entries.isEmpty
        ? null
        : (nameVotes.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
    final category = suggestedName == null
        ? null
        : ProductMatcher.inferCategory(suggestedName).category;
    final quantity = suggestedName == null
        ? (1, 'pcs')
        : ProductMatcher.extractQuantity(suggestedName);
    final zone = _extractStorageZone(storageText ?? '') ??
        (category == null ? null : ProductMatcher.recommendZone(category));
    if (votes.isEmpty) {
      return ExpiryScanResult(
        openingDays: openingDays,
        suggestedName: suggestedName,
        category: category,
        zoneId: zone,
        quantity: quantity.$1,
        unit: quantity.$2,
        confidence: suggestedName == null ? 0 : 0.55,
      );
    }

    final ranked = votes.entries.toList()
      ..sort((a, b) {
        final byVotes = b.value.compareTo(a.value);
        return byVotes != 0 ? byVotes : b.key.compareTo(a.key);
      });
    final best = ranked.first;
    final totalFrames = imagePaths.isEmpty ? 1 : imagePaths.length;
    final repeated = best.value >= 2;
    final confidence =
        ((best.value / (totalFrames * 2)) + (contextualHits > 0 ? 0.25 : 0.05))
            .clamp(0.0, 0.98);
    return ExpiryScanResult(
      expiryDate: repeated || contextualHits > 0 ? best.key : null,
      openingDays: openingDays,
      suggestedName: suggestedName,
      category: category,
      zoneId: zone,
      quantity: quantity.$1,
      unit: quantity.$2,
      confidence: confidence,
      candidates: ranked.map((e) => e.key).take(4).toList(),
    );
  }

  Iterable<DateTime> _extractDates(String text) sync* {
    final now = DateTime.now();
    final earliest = DateTime(now.year - 1, 1, 1);
    final latest = DateTime(now.year + 6, 12, 31);
    final seen = <String>{};

    for (final match in RegExp(
      r'(?<!\d)(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{2,4})(?!\d)',
    ).allMatches(text)) {
      final day = int.tryParse(match.group(1)!);
      final month = int.tryParse(match.group(2)!);
      var year = int.tryParse(match.group(3)!);
      if (day == null || month == null || year == null) continue;
      if (year < 100) year += 2000;
      final date = _validDate(year, month, day);
      if (date != null && !date.isBefore(earliest) && !date.isAfter(latest)) {
        final key = '${date.year}-${date.month}-${date.day}';
        if (seen.add(key)) yield date;
      }
    }
    for (final match in RegExp(
      r'(?<!\d)(20\d{2})[.\-/](\d{1,2})[.\-/](\d{1,2})(?!\d)',
    ).allMatches(text)) {
      final date = _validDate(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
      if (date != null && !date.isBefore(earliest) && !date.isAfter(latest)) {
        final key = '${date.year}-${date.month}-${date.day}';
        if (seen.add(key)) yield date;
      }
    }
  }

  DateTime? _validDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final value = DateTime(year, month, day);
    return value.year == year && value.month == month && value.day == day
        ? value
        : null;
  }

  int? _extractOpeningDays(String text) {
    final match = RegExp(
      r'(?:после\s+вскрытия|вскрыт(?:ия|ую)|after\s+opening)[^\d]{0,35}(\d{1,3})\s*(?:сут|дн|day)',
      caseSensitive: false,
    ).firstMatch(text);
    final days = int.tryParse(match?.group(1) ?? '');
    return days == null || days < 1 || days > 365 ? null : days;
  }

  String? _extractLikelyProductName(String text) {
    final candidates = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.length >= 3 && line.length <= 70)
        .where((line) => RegExp(r'[A-Za-zА-Яа-яЁё]{3,}').hasMatch(line))
        .where((line) => !RegExp(
              r'годен|срок|изготов|хранить|состав|пищев|энергет|белк|жир|углев|телефон|www\.|штрих|масса\s*нетто|best\s*before|exp',
              caseSensitive: false,
            ).hasMatch(line))
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final aScore = _nameScore(a);
      final bScore = _nameScore(b);
      return bScore.compareTo(aScore);
    });
    return candidates.first;
  }

  int _nameScore(String line) {
    var score = RegExp(r'[A-Za-zА-Яа-яЁё]').allMatches(line).length;
    if (ProductMatcher.inferCategory(line).category != 'other') score += 25;
    if (RegExp(r'\d{3,}').hasMatch(line)) score -= 12;
    if (line == line.toUpperCase()) score += 3;
    return score;
  }

  String? _extractStorageZone(String text) {
    if (RegExp(r'заморож|морозиль|−18|-18', caseSensitive: false)
        .hasMatch(text)) {
      return 'freezer';
    }
    if (RegExp(r'холодиль|\+\s*[2-8]\s*\.\.\s*\+', caseSensitive: false)
        .hasMatch(text)) {
      return 'fridge';
    }
    if (RegExp(r'сухом\s+месте|комнатной\s+температур', caseSensitive: false)
        .hasMatch(text)) {
      return 'pantry';
    }
    return null;
  }

  static String _normalizeReceiptLine(String line) => line
      .replaceAll(RegExp(r'[\u00a0\t|]+'), ' ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  static String _cleanProductName(String value) => value
      .replaceFirst(RegExp(r'^\s*\d{1,3}\s*[.)]\s*'), '')
      .replaceFirst(
        RegExp(r'^(?:товар|позиция)\s*\d*\s*[:.)-]?\s*', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'\s+\d{8,14}\s*$'), '')
      .replaceAll(
          RegExp(r'\s+[\[({]?[мmппт][\])}]?\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceAll(RegExp(r'^[\s,;:.\-]+|[\s,;:.\-]+$'), '')
      .trim();

  static bool _isLikelyProductFragment(String value) {
    final line = _cleanProductName(value);
    if (line.length < 2 || line.length > 110) return false;
    if (ProductMatcher.isReceiptMetadata(line)) return false;
    if (!RegExp(r'[A-Za-zА-Яа-яЁё]{2,}').hasMatch(line)) return false;
    if (RegExp(r'^[A-ZА-ЯЁ]{1,3}\s*[:№#]').hasMatch(line)) return false;
    if (RegExp(r'^\d{5,}\s+[A-Za-zА-Яа-яЁё]').hasMatch(line)) return false;
    if (line.split(RegExp(r'\s+')).length > 14) return false;
    return true;
  }

  static bool _isMeasureContinuation(String value) => RegExp(
        r'^\d+(?:[.,]\d+)?\s*(?:г|гр|кг|мл|л|шт|штук[а-яё]*|'
        r'упак(?:овк[а-яё]*)?)\.?$',
        caseSensitive: false,
      ).hasMatch(value);

  static _ReceiptCalculation? _parseCalculationLine(String value) {
    final match = RegExp(
      r'^\s*(\d+(?:[.,]\d{1,3})?)\s*'
      r'(шт(?:ук[а-яё]*)?|кг|г|л|мл)?\s*[xх×*]\s*'
      r'(\d+(?:[.,]\d{1,2})?)'
      r'(?:(?:\s*(?:=|:)\s*|\s+)(\d+(?:[.,]\d{1,2})?))?'
      r'\s*(?:₽|руб(?:ль|ля|лей|\.)?)?\s*$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;

    final rawQuantity = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    final unitPrice = double.tryParse(match.group(3)!.replaceAll(',', '.'));
    final printedTotal = double.tryParse(
      (match.group(4) ?? '').replaceAll(',', '.'),
    );
    if (rawQuantity == null ||
        unitPrice == null ||
        rawQuantity <= 0 ||
        unitPrice <= 0) {
      return null;
    }
    final wholeQuantity = rawQuantity == rawQuantity.roundToDouble() &&
            rawQuantity >= 1 &&
            rawQuantity <= 999
        ? rawQuantity.round()
        : null;
    final printedUnit = match.group(2)?.toLowerCase();
    final unit = printedUnit == null
        ? null
        : printedUnit.startsWith('шт')
            ? 'pcs'
            : printedUnit == 'гр'
                ? 'g'
                : printedUnit;
    return _ReceiptCalculation(
      total: printedTotal ?? rawQuantity * unitPrice,
      quantity: wholeQuantity,
      unit: unit,
    );
  }

  static double? _parseStandalonePrice(String value) {
    final match = RegExp(
      r'^\s*(?:=|стоимость\s*:?\s*)?'
      r'(\d{1,7}(?:[.,]\d{2}))\s*(?:₽|руб(?:ль|ля|лей|\.)?)?\s*$|'
      r'^\s*(?:=|стоимость\s*:?\s*)?'
      r'(\d{1,7})\s*(?:₽|руб(?:ль|ля|лей|\.)?)\s*$',
      caseSensitive: false,
    ).firstMatch(value);
    final raw = match?.group(1) ?? match?.group(2);
    final price = double.tryParse((raw ?? '').replaceAll(',', '.'));
    return price == null || price <= 0 ? null : price;
  }

  Future<void> dispose() => _recognizer.close();
}

class _ReceiptCalculation {
  const _ReceiptCalculation({
    required this.total,
    this.quantity,
    this.unit,
  });

  final double total;
  final int? quantity;
  final String? unit;
}

class ReceiptItem {
  ReceiptItem({
    required this.name,
    required this.category,
    required this.confidence,
    required this.quantity,
    required this.unit,
    this.price,
    this.selected = true,
  });

  String name;
  final double? price;
  String category;
  double confidence;
  final int quantity;
  final String unit;
  bool selected;
}
