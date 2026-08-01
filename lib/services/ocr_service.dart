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

    final items = <ReceiptItem>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final parsed = _parseLine(line.text);
        if (parsed != null) items.add(parsed);
      }
    }
    // Одинаковые позиции не удаляем: в чеке это могут быть разные покупки,
    // а пользователь сможет снять лишнюю галочку перед сохранением.
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

  ReceiptItem? _parseLine(String rawLine) {
    final line = rawLine.trim();
    if (line.length < 3) return null;
    if (_noiseWords.any((w) => line.toUpperCase().contains(w))) return null;

    final parsed = ProductMatcher.parseReceiptLine(line);
    final name = (parsed?.productName ?? line).trim();

    // Отбрасываем строки без букв (чистые числа, коды).
    if (!RegExp(r'[A-Za-zА-Яа-я]{3,}').hasMatch(name)) return null;

    final cleanName = name
        .replaceAll(RegExp(r'^\d+\s*[xх×]\s*'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    if (cleanName.length < 3) return null;

    final match = ProductMatcher.inferCategory(cleanName);
    final (qty, unit) = ProductMatcher.extractQuantity(cleanName);

    return ReceiptItem(
      name: cleanName,
      price: parsed?.price,
      category: match.category,
      confidence: match.confidence,
      quantity: qty,
      unit: unit,
    );
  }

  Future<void> dispose() => _recognizer.close();

  static const _noiseWords = [
    'ИТОГО',
    'ИТОГ',
    'СУММА',
    'НАЛИЧНЫМИ',
    'КАРТОЙ',
    'СДАЧА',
    'НДС',
    'ККТ',
    'ИНН',
    'ФН',
    'ФД',
    'ФП',
    'КАССИР',
    'ЧЕК',
    'СМЕНА',
    'TOTAL',
    'SUBTOTAL',
    'CASH',
    'CARD',
    'CHANGE',
    'TAX',
    'ТЕЛ',
    'АДРЕС',
    'СПАСИБО',
    'ДОБРО ПОЖАЛОВАТЬ',
    'СКИДКА',
  ];
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
