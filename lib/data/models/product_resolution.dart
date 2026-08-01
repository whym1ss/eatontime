enum ProductDataSource {
  localHistory,
  eatOnTimeCatalog,
  honestSign,
  openFoodFacts,
  dataMatrix,
  packageOcr,
  heuristic,
}

extension ProductDataSourceLabel on ProductDataSource {
  String get label => switch (this) {
        ProductDataSource.localHistory => 'Ваша история',
        ProductDataSource.eatOnTimeCatalog => 'Каталог Eat on Time',
        ProductDataSource.honestSign => 'Честный ЗНАК',
        ProductDataSource.openFoodFacts => 'Open Food Facts',
        ProductDataSource.dataMatrix => 'Data Matrix',
        ProductDataSource.packageOcr => 'Распознано с упаковки',
        ProductDataSource.heuristic => 'Умная подсказка',
      };
}

class ResolvedField<T> {
  const ResolvedField({
    required this.value,
    required this.source,
    required this.confidence,
    this.exact = false,
  });

  final T value;
  final ProductDataSource source;
  final double confidence;
  final bool exact;

  bool get needsConfirmation => !exact && confidence < 0.85;
}

class ParsedScanCode {
  const ParsedScanCode({
    required this.raw,
    this.gtin,
    this.expiryDate,
    this.batch,
    this.serial,
    this.isFiscalReceipt = false,
  });

  final String raw;
  final String? gtin;
  final DateTime? expiryDate;
  final String? batch;
  final String? serial;
  final bool isFiscalReceipt;
}

class ResolvedProductDraft {
  const ResolvedProductDraft({
    required this.code,
    this.name,
    this.brand,
    this.category,
    this.zoneId,
    this.expiryDate,
    this.defaultDays,
    this.openingDays,
    this.quantity = 1,
    this.unit = 'pcs',
    this.imageUrl,
    this.batch,
    this.recallWarnings = const [],
  });

  final ParsedScanCode code;
  final ResolvedField<String>? name;
  final ResolvedField<String>? brand;
  final ResolvedField<String>? category;
  final ResolvedField<String>? zoneId;
  final ResolvedField<DateTime>? expiryDate;
  final int? defaultDays;
  final int? openingDays;
  final int quantity;
  final String unit;
  final String? imageUrl;
  final String? batch;
  final List<String> recallWarnings;

  ProductDataSource get primarySource =>
      name?.source ?? category?.source ?? ProductDataSource.heuristic;

  double get confidence => name?.confidence ?? category?.confidence ?? 0.3;

  DateTime suggestedExpiry(DateTime now) =>
      expiryDate?.value ??
      now.add(Duration(
          days: defaultDays == null || defaultDays! <= 0 ? 7 : defaultDays!));

  ResolvedProductDraft copyWith({
    ResolvedField<String>? name,
    ResolvedField<String>? brand,
    ResolvedField<String>? category,
    ResolvedField<String>? zoneId,
    ResolvedField<DateTime>? expiryDate,
    int? defaultDays,
    int? openingDays,
    int? quantity,
    String? unit,
    String? imageUrl,
    String? batch,
    List<String>? recallWarnings,
  }) =>
      ResolvedProductDraft(
        code: code,
        name: name ?? this.name,
        brand: brand ?? this.brand,
        category: category ?? this.category,
        zoneId: zoneId ?? this.zoneId,
        expiryDate: expiryDate ?? this.expiryDate,
        defaultDays: defaultDays ?? this.defaultDays,
        openingDays: openingDays ?? this.openingDays,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        imageUrl: imageUrl ?? this.imageUrl,
        batch: batch ?? this.batch,
        recallWarnings: recallWarnings ?? this.recallWarnings,
      );
}

class ExpiryScanResult {
  const ExpiryScanResult({
    this.expiryDate,
    this.openingDays,
    this.suggestedName,
    this.category,
    this.zoneId,
    this.quantity = 1,
    this.unit = 'pcs',
    this.confidence = 0,
    this.candidates = const [],
  });

  final DateTime? expiryDate;
  final int? openingDays;
  final String? suggestedName;
  final String? category;
  final String? zoneId;
  final int quantity;
  final String unit;
  final double confidence;
  final List<DateTime> candidates;

  bool get isExact => expiryDate != null && confidence >= 0.75;
}
