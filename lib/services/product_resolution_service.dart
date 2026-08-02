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
  static const _connectTimeout = Duration(seconds: 4);
  static const _requestTimeout = Duration(seconds: 6);
  static const _responseTimeout = Duration(seconds: 5);
  static const _maxResponseBytes = 512 * 1024;
  static const _openFoodFactsFields =
      'code,product_name_ru,abbreviated_product_name_ru,generic_name_ru,'
      'product_name,product_name_en,generic_name,brands,brands_tags,'
      'categories,categories_tags,quantity,product_quantity,'
      'product_quantity_unit,image_front_small_url';

  Future<ResolvedProductDraft> resolve(String rawCode) async {
    final parsed = parseCode(rawCode);
    final lookupCode = parsed.gtin ?? rawCode.trim();
    final lookupCandidates = parsed.gtin != null || _isRetailBarcode(lookupCode)
        ? gtinLookupCandidates(lookupCode)
        : <String>[lookupCode];
    if (lookupCandidates.isEmpty) lookupCandidates.add(lookupCode);
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

    var existing = await repository.findByBarcode(lookupCandidates.first);
    for (final candidate in lookupCandidates.skip(1)) {
      if (existing != null) break;
      existing = await repository.findByBarcode(candidate);
    }
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

    var catalog = await repository.lookupCatalog(lookupCandidates.first);
    for (final candidate in lookupCandidates.skip(1)) {
      if (catalog != null) break;
      catalog = await repository.lookupCatalog(candidate);
    }
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

    ResolvedProductDraft? cached;
    for (final candidate in lookupCandidates) {
      cached ??= _readCache(candidate);
      if (cached != null) break;
    }
    if (cached != null) result = _merge(result, cached);

    if (existing == null || result.name == null) {
      final official = await _resolveThroughBackend(parsed);
      if (official != null) result = _merge(result, official);
    }

    if (lookupCandidates.any(_isRetailBarcode) &&
        (result.name == null ||
            result.brand == null ||
            result.category == null)) {
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
    _writeCache(lookupCandidates.first, result);
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

  /// Returns equivalent retail barcode representations without dropping the
  /// scanner value. Local history can contain UPC/EAN/GTIN with a different
  /// number of leading zeroes, so all safe leading-zero variants are checked.
  List<String> gtinLookupCandidates(String value) {
    final digits = normalizeGtin(value);
    if (digits.isEmpty || digits.length > 14) return <String>[];

    final candidates = <String>{digits};
    final withoutLeadingZeroes = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (const {8, 12, 13, 14}.contains(withoutLeadingZeroes.length)) {
      candidates.add(withoutLeadingZeroes);
    }

    // The same GTIN can be stored as UPC-A, EAN-13 or GTIN-14. Only leading
    // zeroes are added; significant digits and the check digit stay intact.
    if (digits.length <= 12) candidates.add(digits.padLeft(13, '0'));
    if (digits.length <= 13) candidates.add(digits.padLeft(14, '0'));

    return candidates
        .where((candidate) => const {8, 12, 13, 14}.contains(candidate.length))
        .toList(growable: true);
  }

  /// GS1 modulo-10 validation. Parsing stays lenient so a mistyped code can
  /// still match local history, while public network lookups use valid GTINs.
  bool isValidGtin(String value) {
    final digits = value.trim();
    if (!RegExp(r'^\d+$').hasMatch(digits)) return false;
    if (!const {8, 12, 13, 14}.contains(digits.length)) return false;
    var sum = 0;
    for (var index = digits.length - 2, position = 1;
        index >= 0;
        index--, position++) {
      final digit = int.parse(digits[index]);
      sum += digit * (position.isOdd ? 3 : 1);
    }
    final expected = (10 - (sum % 10)) % 10;
    return expected == int.parse(digits[digits.length - 1]);
  }

  /// Mirrors Open Food Facts' documented leading-zero normalization.
  String normalizeOpenFoodFactsBarcode(String value) {
    final digits = normalizeGtin(value);
    if (digits.isEmpty) return '';
    final significant = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (significant.length <= 7) return significant.padLeft(8, '0');
    if (significant.length >= 9 && significant.length <= 12) {
      return significant.padLeft(13, '0');
    }
    return significant;
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
    final validCandidates = gtinLookupCandidates(gtin).where(isValidGtin);
    if (validCandidates.isEmpty) return null;
    final barcode = normalizeOpenFoodFactsBarcode(validCandidates.first);
    final client = HttpClient()
      ..connectionTimeout = _connectTimeout
      ..idleTimeout = _responseTimeout;
    try {
      final v3 = Uri.https(
        'world.openfoodfacts.org',
        '/api/v3/product/$barcode',
        {
          'lc': 'ru',
          'cc': 'ru',
          'tags_lc': 'ru',
          'fields': _openFoodFactsFields,
        },
      );
      final first = await _getOpenFoodFactsJson(client, v3);
      if (first.$1 == HttpStatus.ok) {
        final parsed = parseOpenFoodFactsPayload(first.$2, code);
        if (parsed != null) return parsed;
      }
      // A 404 is a definitive "not found". Rate-limit/service-unavailable
      // responses are not retried so the app remains a polite API client.
      if (const {
        HttpStatus.notFound,
        HttpStatus.tooManyRequests,
        HttpStatus.serviceUnavailable,
      }.contains(first.$1)) {
        return null;
      }

      // v2 is deprecated but remains an officially documented compatibility
      // endpoint. It is attempted once only when v3 returned no usable record.
      final v2 = Uri.https(
        'world.openfoodfacts.org',
        '/api/v2/product/$barcode.json',
        {'fields': _openFoodFactsFields},
      );
      final fallback = await _getOpenFoodFactsJson(client, v2);
      if (fallback.$1 != HttpStatus.ok) return null;
      return parseOpenFoodFactsPayload(fallback.$2, code);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<(int, Object?)> _getOpenFoodFactsJson(
    HttpClient client,
    Uri uri,
  ) =>
      _readOpenFoodFactsJson(client, uri).timeout(_requestTimeout);

  Future<(int, Object?)> _readOpenFoodFactsJson(
    HttpClient client,
    Uri uri,
  ) async {
    final request = await client.getUrl(uri).timeout(_connectTimeout);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'EatOnTime/1.1.0 (https://github.com/whym1ss/eatontime)',
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(_requestTimeout);
    if (response.statusCode != HttpStatus.ok) {
      return (response.statusCode, null);
    }

    final bytes = <int>[];
    await for (final chunk in response.timeout(_responseTimeout)) {
      if (bytes.length + chunk.length > _maxResponseBytes) {
        throw const FormatException('Open Food Facts response is too large');
      }
      bytes.addAll(chunk);
    }
    final payload = jsonDecode(utf8.decode(bytes));
    return (response.statusCode, payload);
  }

  /// Converts either the documented v3 or v2 payload to an app draft. This is
  /// intentionally pure so malformed community data cannot pollute local data.
  ResolvedProductDraft? parseOpenFoodFactsPayload(
    Object? payload,
    ParsedScanCode code,
  ) {
    if (payload is! Map) return null;
    final root = Map<String, dynamic>.from(payload);
    final status = root['status'];
    final successful = status is num && status == 1 ||
        status is String &&
            (status == '1' || status.toLowerCase().startsWith('success'));
    if (!successful) return null;
    if (root['product'] is! Map) return null;
    final product = Map<String, dynamic>.from(root['product'] as Map);

    final responseCode = _nonEmpty(product['code'] ?? root['code']);
    if (code.gtin != null &&
        (responseCode == null ||
            !_barcodesEquivalent(code.gtin!, responseCode))) {
      return null;
    }

    final name = _validProductName(_firstText(product, const [
      'product_name_ru',
      'abbreviated_product_name_ru',
      'generic_name_ru',
      'product_name',
      'product_name_en',
      'generic_name',
    ]));
    if (name == null) return null;
    final brand = _validBrand(_firstText(product, const ['brands']));
    final categorySource = [
      product['categories_tags_ru'],
      product['categories_tags'],
      product['categories_ru'],
      product['categories'],
    ];
    final category = _offCategory(categorySource, name);
    final quantity = _parseOffQuantity(product);
    return ResolvedProductDraft(
      code: code,
      name: ResolvedField(
        value: name,
        source: ProductDataSource.openFoodFacts,
        confidence: 0.86,
      ),
      brand: brand == null
          ? null
          : ResolvedField(
              value: brand,
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
      imageUrl: _safeImageUrl(product['image_front_small_url']),
    );
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

  String? _firstText(Map<String, dynamic> product, List<String> keys) {
    final localizedKeys = keys.where((key) => key.endsWith('_ru')).toList();
    for (final key in localizedKeys) {
      final value = _nonEmpty(product[key]);
      if (value != null) return value;
    }
    // Some imports use regional suffixes such as product_name_ru-RU.
    final localizedPrefixes = localizedKeys
        .map((key) => '${key.substring(0, key.length - 3)}_ru')
        .toSet();
    for (final prefix in localizedPrefixes) {
      for (final entry in product.entries) {
        if (entry.key.startsWith(prefix)) {
          final value = _nonEmpty(entry.value);
          if (value != null) return value;
        }
      }
    }
    for (final key in keys.where((key) => !key.endsWith('_ru'))) {
      final value = _nonEmpty(product[key]);
      if (value != null) return value;
    }
    return null;
  }

  String? _validProductName(String? raw) {
    final value = _cleanSingleLine(raw);
    if (value == null || value.length < 2 || value.length > 160) return null;
    if (!RegExp(r'[A-Za-zА-Яа-яЁё]', unicode: true).hasMatch(value)) {
      return null;
    }
    final normalized = value.toLowerCase();
    const placeholders = {
      'unknown',
      'unnamed',
      'product',
      'food',
      'not available',
      'n/a',
      'неизвестно',
      'без названия',
      'продукт',
      'товар',
    };
    if (placeholders.contains(normalized)) return null;
    return value;
  }

  String? _validBrand(String? raw) {
    final value = _cleanSingleLine(raw);
    if (value == null || value.length > 120) return null;
    return RegExp(r'[A-Za-zА-Яа-яЁё0-9]', unicode: true).hasMatch(value)
        ? value
        : null;
  }

  String? _cleanSingleLine(String? raw) {
    if (raw == null) return null;
    final value = raw
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return value.isEmpty ? null : value;
  }

  bool _barcodesEquivalent(String left, String right) {
    final leftDigits = left.trim();
    final rightDigits = right.trim();
    if (!RegExp(r'^\d{8,14}$').hasMatch(leftDigits) ||
        !RegExp(r'^\d{8,14}$').hasMatch(rightDigits)) {
      return false;
    }
    return normalizeOpenFoodFactsBarcode(leftDigits) ==
        normalizeOpenFoodFactsBarcode(rightDigits);
  }

  String? _safeImageUrl(Object? raw) {
    final value = _nonEmpty(raw);
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri.toString();
  }

  (int, String) _parseOffQuantity(Map<String, dynamic> product) {
    final displayQuantity = _parseQuantity(_nonEmpty(product['quantity']));
    if (displayQuantity.$2 != 'pcs' || displayQuantity.$1 != 1) {
      return displayQuantity;
    }
    final amount = _nonEmpty(product['product_quantity']);
    final unit = _nonEmpty(product['product_quantity_unit']);
    if (amount == null || unit == null) return displayQuantity;
    return _parseQuantity('$amount $unit');
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
    const russianMap = {
      'dairy': ['молоч', 'молоко', 'сыр', 'йогурт', 'кефир', 'творог'],
      'meat': ['мяс', 'птица', 'колбас', 'сосиск', 'ветчин'],
      'fish': ['рыб', 'морепродукт'],
      'vegetables': ['овощ'],
      'fruits': ['фрукт', 'ягод'],
      'beverages': ['напит', 'сок', 'вода'],
      'frozen': ['заморож'],
      'grains': ['хлеб', 'круп', 'макарон', 'зернов'],
      'condiments': ['соус', 'приправа'],
      'canned': ['консерв', 'пресерв'],
    };
    for (final entry in map.entries) {
      if (entry.value.any(text.contains)) return entry.key;
    }
    for (final entry in russianMap.entries) {
      if (entry.value.any(text.contains)) return entry.key;
    }
    return ProductMatcher.inferCategory(name).category;
  }

  (int, String) _parseQuantity(String? raw) {
    if (raw == null) return (1, 'pcs');
    final normalized =
        raw.toLowerCase().replaceAll('\u00a0', ' ').replaceAll('×', 'x');
    const unitPattern =
        r'(kg|кг|kilograms?|kilogrammes?|mg|мг|grams?|grammes?|гр|gr|g|г|milliliters?|millilitres?|ml|мл|centiliters?|centilitres?|cl|сл|deciliters?|decilitres?|dl|дл|liters?|litres?|l|л)';
    final pack = RegExp(
      '(\\d+(?:[.,]\\d+)?)\\s*[xх]\\s*'
      '(\\d+(?:[.,]\\d+)?)\\s*$unitPattern',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (pack != null) {
      final count = _parseDecimal(pack.group(1)) ?? 1;
      final amount = _parseDecimal(pack.group(2)) ?? 1;
      return _normalizeQuantity(count * amount, pack.group(3)!);
    }

    final measurement = RegExp(
      '(\\d+(?:[.,]\\d+)?)\\s*$unitPattern',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (measurement != null) {
      final amount = _parseDecimal(measurement.group(1)) ?? 1;
      return _normalizeQuantity(amount, measurement.group(2)!);
    }

    final pieces = RegExp(
      r'(\d+)\s*(?:pcs?|pieces?|шт\.?|штук|яиц)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (pieces != null) {
      return (int.parse(pieces.group(1)!).clamp(1, 1000000), 'pcs');
    }
    return (1, 'pcs');
  }

  double? _parseDecimal(String? raw) =>
      double.tryParse((raw ?? '').replaceAll(',', '.'));

  (int, String) _normalizeQuantity(double amount, String rawUnit) {
    final token = rawUnit.toLowerCase();
    var normalizedAmount = amount;
    var unit = 'pcs';
    if (const {'kg', 'кг', 'kilogram', 'kilograms', 'kilogramme', 'kilogrammes'}
        .contains(token)) {
      if (amount == amount.roundToDouble()) {
        unit = 'kg';
      } else {
        normalizedAmount = amount * 1000;
        unit = 'g';
      }
    } else if (const {'mg', 'мг'}.contains(token)) {
      normalizedAmount = amount / 1000;
      unit = 'g';
    } else if (const {
      'g',
      'gr',
      'grams',
      'gram',
      'gramme',
      'grammes',
      'г',
      'гр',
    }.contains(token)) {
      unit = 'g';
    } else if (const {
      'l',
      'л',
      'liter',
      'liters',
      'litre',
      'litres',
    }.contains(token)) {
      if (amount == amount.roundToDouble()) {
        unit = 'l';
      } else {
        normalizedAmount = amount * 1000;
        unit = 'ml';
      }
    } else if (const {
      'cl',
      'сл',
      'centiliter',
      'centiliters',
      'centilitre',
      'centilitres',
    }.contains(token)) {
      normalizedAmount = amount * 10;
      unit = 'ml';
    } else if (const {
      'dl',
      'дл',
      'deciliter',
      'deciliters',
      'decilitre',
      'decilitres',
    }.contains(token)) {
      normalizedAmount = amount * 100;
      unit = 'ml';
    } else {
      unit = 'ml';
    }
    return (normalizedAmount.round().clamp(1, 1000000), unit);
  }
}
