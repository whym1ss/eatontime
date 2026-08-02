import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/product_matcher.dart';
import '../data/models/product_resolution.dart';
import '../data/repositories/product_repository.dart';

/// Объединяет локальную историю, каталог Eat on Time, серверные источники
/// (Национальный каталог/отзывы) и Open Food Facts. Любой внешний источник
/// может быть недоступен — сканирование всё равно продолжится офлайн.
class ProductResolutionService {
  ProductResolutionService({
    required this.repository,
    required this.preferences,
    this.supabase,
  });

  final ProductRepository repository;
  final SharedPreferences preferences;
  final SupabaseClient? supabase;

  static const _cacheKey = 'smart_product_cache_v1';
  static const _maxCacheEntries = 80;

  Future<ResolvedProductDraft> resolve(String rawCode) async {
    final parsed = parseCode(rawCode);
    final lookupCode = parsed.gtin ?? rawCode.trim();
    ResolvedProductDraft result = ResolvedProductDraft(
      code: parsed,
      expiryDate: parsed.expiryDate == null
          ? null
          : ResolvedField(
              value: parsed.expiryDate!,
              source: ProductDataSource.dataMatrix,
              confidence: 0.98,
              exact: true,
            ),
      batch: parsed.batch,
    );

    final existing = await repository.findByBarcode(lookupCode);
    if (existing != null) {
      result = _merge(
        result,
        _fromMap(
          {
            'name': existing.name,
            'brand': existing.brand,
            'category': existing.category,
            'zone_id': existing.zoneId,
            'default_days': existing.expiryDate
                .difference(existing.purchaseDate ?? existing.createdAt)
                .inDays,
          },
          parsed,
          ProductDataSource.localHistory,
          0.96,
        ),
      );
    }

    final catalog = await repository.lookupCatalog(lookupCode);
    if (catalog != null) {
      result = _merge(
        result,
        _fromMap(
          catalog,
          parsed,
          ProductDataSource.eatOnTimeCatalog,
          0.92,
        ),
      );
    }

    final cached = _readCache(lookupCode);
    if (cached != null) result = _merge(result, cached);

    if (existing == null || result.name == null) {
      final official = await _resolveThroughBackend(parsed);
      if (official != null) result = _merge(result, official);
    }

    if (_isRetailBarcode(lookupCode) && result.name == null) {
      final openFoodFacts = await _lookupOpenFoodFacts(parsed);
      if (openFoodFacts != null) result = _merge(result, openFoodFacts);
    }

    final guessedName = result.name?.value ?? 'Новый продукт';
    final categoryGuess = result.category?.value == null
        ? ProductMatcher.inferCategory(guessedName)
        : null;
    final category = result.category?.value ?? categoryGuess!.category;
    result = _merge(
      result,
      ResolvedProductDraft(
        code: parsed,
        category: result.category == null
            ? ResolvedField(
                value: category,
                source: ProductDataSource.heuristic,
                confidence: categoryGuess!.confidence,
              )
            : null,
        zoneId: ResolvedField(
          value: ProductMatcher.recommendZone(category),
          source: ProductDataSource.heuristic,
          confidence: 0.75,
        ),
        defaultDays: result.defaultDays ??
            ProductMatcher.estimateShelfLife(
              category,
              ProductMatcher.recommendZone(category),
            ),
        openingDays:
            result.openingDays ?? ProductMatcher.estimateAfterOpening(category),
      ),
    );

    final warnings = await _lookupRecalls(parsed);
    if (warnings.isNotEmpty) {
      result = result.copyWith(recallWarnings: warnings);
    }
    _writeCache(lookupCode, result);
    return result;
  }

  ParsedScanCode parseCode(String raw) {
    final value = raw.trim();
    if (parseFiscalReceiptQr(value) != null) {
      return ParsedScanCode(raw: value, isFiscalReceipt: true);
    }

    String? gtin;
    DateTime? expiry;
    String? batch;
    String? serial;
    if (RegExp(r'^\d{8,14}$').hasMatch(value)) gtin = normalizeGtin(value);

    final digitalLink = _parseGs1DigitalLink(value);
    gtin ??= digitalLink.gtin;
    expiry ??= digitalLink.expiry;
    batch ??= digitalLink.batch;
    serial ??= digitalLink.serial;

    final aiGtin = RegExp(r'\(01\)(\d{14})').firstMatch(value);
    if (aiGtin != null) gtin ??= aiGtin.group(1);
    final aiExpiry = RegExp(r'\(17\)(\d{6})').firstMatch(value);
    final aiBestBefore = RegExp(r'\(15\)(\d{6})').firstMatch(value);
    if (aiExpiry != null) {
      expiry = _parseGs1Date(aiExpiry.group(1)!);
    } else if (aiBestBefore != null) {
      expiry ??= _parseGs1Date(aiBestBefore.group(1)!);
    }
    final aiBatch = RegExp(r'\(10\)([^()\u001d]+)').firstMatch(value);
    final aiSerial = RegExp(r'\(21\)([^()\u001d]+)').firstMatch(value);
    batch ??= aiBatch?.group(1);
    serial ??= aiSerial?.group(1);

    final compact = _parseCompactGs1(value);
    gtin ??= compact.gtin;
    expiry ??= compact.expiry;
    batch ??= compact.batch;
    serial ??= compact.serial;
    return ParsedScanCode(
      raw: value,
      gtin: gtin,
      expiryDate: expiry,
      batch: batch,
      serial: serial,
    );
  }

  String normalizeGtin(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  FiscalReceiptData? parseFiscalReceiptQr(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final params = <String, String>{};
    final uri = Uri.tryParse(value);
    if (uri != null) params.addAll(uri.queryParameters);
    final query = value.contains('?') ? value.split('?').last : value;
    try {
      params.addAll(Uri.splitQueryString(query));
    } catch (_) {
      // Необычная кодировка будет проверена регулярными выражениями ниже.
    }
    final normalized = <String, String>{
      for (final entry in params.entries) entry.key.toLowerCase(): entry.value,
    };
    final timestamp = normalized['t'];
    final fiscalDrive = normalized['fn'];
    if (timestamp == null || fiscalDrive == null) return null;
    final dateMatch =
        RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})$', caseSensitive: false)
            .firstMatch(timestamp);
    DateTime? dateTime;
    if (dateMatch != null) {
      final values = [
        for (var i = 1; i <= 5; i++) int.tryParse(dateMatch.group(i)!),
      ];
      if (values.every((value) => value != null)) {
        final candidate = DateTime(
          values[0]!,
          values[1]!,
          values[2]!,
          values[3]!,
          values[4]!,
        );
        if (candidate.year == values[0] &&
            candidate.month == values[1] &&
            candidate.day == values[2]) {
          dateTime = candidate;
        }
      }
    }
    return FiscalReceiptData(
      raw: value,
      dateTime: dateTime,
      total: double.tryParse((normalized['s'] ?? '').replaceAll(',', '.')),
      fiscalDrive: fiscalDrive,
      fiscalDocument: normalized['i'],
      fiscalSign: normalized['fp'],
      operationType: int.tryParse(normalized['n'] ?? ''),
    );
  }

  ({String? gtin, DateTime? expiry, String? batch, String? serial})
      _parseGs1DigitalLink(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      return (gtin: null, expiry: null, batch: null, serial: null);
    }
    final fields = <String, String>{};
    final segments = uri.pathSegments.map(Uri.decodeComponent).toList();
    for (var index = 0; index + 1 < segments.length; index += 2) {
      final ai = segments[index];
      if (!RegExp(r'^\d{2,4}$').hasMatch(ai)) continue;
      fields[ai] = segments[index + 1];
    }
    final expiryRaw = fields['17'] ?? fields['15'];
    return (
      gtin: fields['01'] == null ? null : normalizeGtin(fields['01']!),
      expiry: expiryRaw == null ? null : _parseGs1Date(expiryRaw),
      batch: fields['10'],
      serial: fields['21'],
    );
  }

  ({String? gtin, DateTime? expiry, String? batch, String? serial})
      _parseCompactGs1(String value) {
    var payload = value
        .replaceFirst(RegExp(r'^\][A-Za-z]\d'), '')
        .replaceFirst(RegExp(r'^\u001d+'), '');
    String? gtin;
    DateTime? expiry;
    String? batch;
    String? serial;
    var cursor = 0;
    while (cursor < payload.length) {
      if (payload.codeUnitAt(cursor) == 29) {
        cursor++;
        continue;
      }
      if (cursor + 2 > payload.length) break;
      final ai = payload.substring(cursor, cursor + 2);
      if (ai == '01') {
        if (cursor + 16 > payload.length) break;
        final rawGtin = payload.substring(cursor + 2, cursor + 16);
        if (!RegExp(r'^\d{14}$').hasMatch(rawGtin)) break;
        gtin = normalizeGtin(rawGtin);
        cursor += 16;
        continue;
      }
      if (const {'11', '13', '15', '16', '17'}.contains(ai)) {
        if (cursor + 8 > payload.length) break;
        final rawDate = payload.substring(cursor + 2, cursor + 8);
        if (!RegExp(r'^\d{6}$').hasMatch(rawDate)) break;
        final parsed = _parseGs1Date(rawDate);
        if (ai == '17' || (ai == '15' && expiry == null)) expiry = parsed;
        cursor += 8;
        continue;
      }
      if (ai == '10' || ai == '21') {
        final start = cursor + 2;
        final separator = payload.indexOf('\u001d', start);
        final end = separator < 0 ? payload.length : separator;
        final field = payload.substring(start, end);
        if (ai == '10') batch = field;
        if (ai == '21') serial = field;
        cursor = separator < 0 ? payload.length : separator + 1;
        continue;
      }
      break;
    }
    return (gtin: gtin, expiry: expiry, batch: batch, serial: serial);
  }

  Future<List<Map<String, dynamic>>> resolveFiscalReceipt(String qr) async {
    final client = supabase;
    if (client == null) return const [];
    try {
      final response = await client.functions.invoke('receipt-resolve',
          body: {'qr': qr}).timeout(const Duration(seconds: 10));
      final data = response.data;
      final rawItems = data is Map ? data['items'] : null;
      if (rawItems is! List) return const [];
      return rawItems
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> submitCatalogFeedback({
    required String barcode,
    required String name,
    String? brand,
    String? category,
    String? zoneId,
  }) async {
    final client = supabase;
    if (client == null || barcode.isEmpty) return;
    try {
      await client.functions.invoke(
        'catalog-feedback',
        body: {
          'barcode': barcode,
          'name': name,
          'brand': brand,
          'category': category,
          'zone_id': zoneId,
        },
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Обратная связь улучшает общий каталог, но не влияет на сохранение.
    }
  }

  Future<ResolvedProductDraft?> _resolveThroughBackend(
    ParsedScanCode code,
  ) async {
    final client = supabase;
    if (client == null || code.gtin == null) return null;
    try {
      final response = await client.functions.invoke(
        'product-resolve',
        body: {
          'gtin': code.gtin,
          'raw_code': code.raw,
          'batch': code.batch,
        },
      ).timeout(const Duration(seconds: 7));
      if (response.data is! Map) return null;
      final map = Map<String, dynamic>.from(response.data as Map);
      final product = map['product'] is Map
          ? Map<String, dynamic>.from(map['product'] as Map)
          : map;
      final source = map['source'] == 'crpt'
          ? ProductDataSource.honestSign
          : ProductDataSource.eatOnTimeCatalog;
      return _fromMap(product, code, source, 0.94);
    } catch (_) {
      return null;
    }
  }

  Future<ResolvedProductDraft?> _lookupOpenFoodFacts(
    ParsedScanCode code,
  ) async {
    final gtin = code.gtin;
    if (gtin == null) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final uri = Uri.https(
        'world.openfoodfacts.org',
        '/api/v3/product/$gtin',
        {
          'fields':
              'code,product_name_ru,product_name,brands,categories_tags,quantity,image_front_small_url'
        },
      );
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'EatOnTime/1.0 (https://github.com/whym1ss/eatontime)',
      );
      final response =
          await request.close().timeout(const Duration(seconds: 6));
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await utf8.decoder.bind(response).join();
      final json = jsonDecode(body);
      if (json is! Map || json['product'] is! Map) return null;
      final product = Map<String, dynamic>.from(json['product'] as Map);
      final name = _nonEmpty(product['product_name_ru']) ??
          _nonEmpty(product['product_name']);
      if (name == null) return null;
      final category = _offCategory(product['categories_tags'], name);
      final quantity = _parseQuantity(_nonEmpty(product['quantity']));
      return ResolvedProductDraft(
        code: code,
        name: ResolvedField(
          value: name,
          source: ProductDataSource.openFoodFacts,
          confidence: 0.86,
        ),
        brand: _nonEmpty(product['brands']) == null
            ? null
            : ResolvedField(
                value: _nonEmpty(product['brands'])!,
                source: ProductDataSource.openFoodFacts,
                confidence: 0.82,
              ),
        category: ResolvedField(
          value: category,
          source: ProductDataSource.openFoodFacts,
          confidence: 0.78,
        ),
        quantity: quantity.$1,
        unit: quantity.$2,
        imageUrl: _nonEmpty(product['image_front_small_url']),
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<String>> _lookupRecalls(ParsedScanCode code) async {
    final client = supabase;
    if (client == null || code.gtin == null) return const [];
    try {
      final response = await client.functions.invoke(
        'recall-check',
        body: {'gtin': code.gtin, 'batch': code.batch},
      ).timeout(const Duration(seconds: 5));
      final data = response.data;
      final warnings = data is Map ? data['warnings'] : null;
      if (warnings is! List) return const [];
      return warnings
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  ResolvedProductDraft _fromMap(
    Map<String, dynamic> map,
    ParsedScanCode code,
    ProductDataSource source,
    double confidence,
  ) {
    final name = _nonEmpty(map['name'] ?? map['product_name']);
    final brand = _nonEmpty(map['brand'] ?? map['brands']);
    final category = _nonEmpty(map['category']);
    final zone = _nonEmpty(map['zone_id']);
    return ResolvedProductDraft(
      code: code,
      name: name == null
          ? null
          : ResolvedField(value: name, source: source, confidence: confidence),
      brand: brand == null
          ? null
          : ResolvedField(value: brand, source: source, confidence: confidence),
      category: category == null
          ? null
          : ResolvedField(
              value: category, source: source, confidence: confidence),
      zoneId: zone == null
          ? null
          : ResolvedField(value: zone, source: source, confidence: confidence),
      defaultDays: (map['default_days'] as num?)?.toInt(),
      openingDays: (map['opening_days'] as num?)?.toInt(),
      imageUrl: _nonEmpty(map['image_url']),
    );
  }

  ResolvedProductDraft _merge(
    ResolvedProductDraft preferred,
    ResolvedProductDraft fallback,
  ) =>
      preferred.copyWith(
        name: preferred.name ?? fallback.name,
        brand: preferred.brand ?? fallback.brand,
        category: preferred.category ?? fallback.category,
        zoneId: preferred.zoneId ?? fallback.zoneId,
        expiryDate: preferred.expiryDate ?? fallback.expiryDate,
        defaultDays: preferred.defaultDays ?? fallback.defaultDays,
        openingDays: preferred.openingDays ?? fallback.openingDays,
        quantity:
            preferred.quantity != 1 ? preferred.quantity : fallback.quantity,
        unit: preferred.unit != 'pcs' ? preferred.unit : fallback.unit,
        imageUrl: preferred.imageUrl ?? fallback.imageUrl,
        batch: preferred.batch ?? fallback.batch,
        recallWarnings: preferred.recallWarnings.isNotEmpty
            ? preferred.recallWarnings
            : fallback.recallWarnings,
      );

  ResolvedProductDraft? _readCache(String code) {
    try {
      final raw = preferences.getString(_cacheKey);
      if (raw == null) return null;
      final root = jsonDecode(raw);
      if (root is! Map || root[code] is! Map) return null;
      final entry = Map<String, dynamic>.from(root[code] as Map);
      final updated = DateTime.tryParse(entry['updated_at']?.toString() ?? '');
      if (updated == null || DateTime.now().difference(updated).inDays > 30) {
        return null;
      }
      return _fromMap(
        entry,
        ParsedScanCode(raw: code, gtin: code),
        ProductDataSource.eatOnTimeCatalog,
        0.8,
      );
    } catch (_) {
      return null;
    }
  }

  void _writeCache(String code, ResolvedProductDraft value) {
    if (value.name == null) return;
    try {
      final raw = preferences.getString(_cacheKey);
      final root = raw == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
      root.remove(code);
      root[code] = {
        'name': value.name?.value,
        'brand': value.brand?.value,
        'category': value.category?.value,
        'zone_id': value.zoneId?.value,
        'default_days': value.defaultDays,
        'opening_days': value.openingDays,
        'image_url': value.imageUrl,
        'updated_at': DateTime.now().toIso8601String(),
      };
      while (root.length > _maxCacheEntries) {
        root.remove(root.keys.first);
      }
      unawaited(preferences.setString(_cacheKey, jsonEncode(root)));
    } catch (_) {
      // Повреждённый кэш не должен ломать сканирование.
    }
  }

  bool _isRetailBarcode(String code) => RegExp(r'^\d{8,14}$').hasMatch(code);

  String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  DateTime? _parseGs1Date(String value) {
    if (value.length != 6) return null;
    final year = 2000 + (int.tryParse(value.substring(0, 2)) ?? -1);
    final month = int.tryParse(value.substring(2, 4));
    var day = int.tryParse(value.substring(4, 6));
    if (month == null || day == null || month < 1 || month > 12) return null;
    if (day == 0) day = DateTime(year, month + 1, 0).day;
    try {
      final date = DateTime(year, month, day);
      if (date.month != month || date.day != day) return null;
      return date;
    } catch (_) {
      return null;
    }
  }

  String _offCategory(Object? tags, String name) {
    final text = '$tags $name'.toLowerCase();
    const map = {
      'dairy': ['dair', 'milk', 'cheese', 'yogurt', 'молоч', 'сыр'],
      'meat': ['meat', 'poultry', 'sausage', 'мяс', 'колбас'],
      'fish': ['fish', 'seafood', 'рыб'],
      'vegetables': ['vegetable', 'овощ'],
      'fruits': ['fruit', 'фрукт'],
      'beverages': ['beverage', 'drink', 'напит'],
      'frozen': ['frozen', 'заморож'],
      'grains': ['bread', 'cereal', 'pasta', 'хлеб', 'круп'],
      'condiments': ['sauce', 'condiment', 'соус'],
      'canned': ['canned', 'preserve', 'консерв'],
    };
    for (final entry in map.entries) {
      if (entry.value.any(text.contains)) return entry.key;
    }
    return ProductMatcher.inferCategory(name).category;
  }

  (int, String) _parseQuantity(String? raw) {
    if (raw == null) return (1, 'pcs');
    final match = RegExp(r'(\d+(?:[.,]\d+)?)\s*(kg|кг|g|г|ml|мл|l|л)',
            caseSensitive: false)
        .firstMatch(raw);
    if (match == null) return (1, 'pcs');
    final amount = double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 1;
    final token = match.group(2)!.toLowerCase();
    var unit = switch (token) {
      'кг' || 'kg' => 'kg',
      'г' || 'g' => 'g',
      'мл' || 'ml' => 'ml',
      _ => 'l',
    };
    var normalizedAmount = amount;
    if (amount < 1 && unit == 'kg') {
      normalizedAmount = amount * 1000;
      unit = 'g';
    } else if (amount < 1 && unit == 'l') {
      normalizedAmount = amount * 1000;
      unit = 'ml';
    }
    return (normalizedAmount.round().clamp(1, 1000000), unit);
  }
}
