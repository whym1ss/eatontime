import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/themes/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/product_labels.dart';
import '../../core/utils/product_matcher.dart';
import '../../data/models/product.dart';
import '../../data/models/product_resolution.dart';
import '../../data/models/user_profile.dart';
import '../../providers/core_providers.dart';
import '../../providers/product_providers.dart';
import '../../providers/settings_providers.dart';
import 'date_scan_screen.dart';

/// Экран добавления / редактирования продукта.
class AddProductScreen extends ConsumerStatefulWidget {
  const AddProductScreen({
    super.key,
    this.initialName,
    this.initialBrand,
    this.initialBarcode,
    this.initialExpiry,
    this.initialCategory,
    this.initialZoneId,
    this.initialQuantity,
    this.initialUnit,
    this.initialPrice,
    this.initialNote,
    this.initialSource,
    this.initialConfidence,
    this.initialOpeningDays,
    this.initialOpened = false,
    this.recallWarnings = const [],
    this.addMethod = AppConstants.addManual,
    this.editing,
  });

  final String? initialName;
  final String? initialBrand;
  final String? initialBarcode;
  final DateTime? initialExpiry;
  final String? initialCategory;
  final String? initialZoneId;
  final int? initialQuantity;
  final String? initialUnit;
  final double? initialPrice;
  final String? initialNote;
  final ProductDataSource? initialSource;
  final double? initialConfidence;
  final int? initialOpeningDays;
  final bool initialOpened;
  final List<String> recallWarnings;
  final String addMethod;
  final Product? editing;

  @override
  ConsumerState<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends ConsumerState<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _brandController;
  late final TextEditingController _priceController;
  late final TextEditingController _noteController;
  late final TextEditingController _quantityController;
  late final TextEditingController _customCategoryController;
  late final TextEditingController _openingDaysController;

  late String _zoneId;
  late DateTime _expiryDate;
  late DateTime _sealedExpiryDate;
  String? _category;
  String _unit = 'pcs';
  bool _saving = false;
  bool _expiryTouched = false;
  bool _categoryTouched = false;
  bool _quantityTouched = false;
  DateTime? _openedDate;
  late int _openingDays;
  ProductDataSource? _expirySource;
  bool _duplicateExists = false;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _nameController = TextEditingController(
      text: editing?.name ?? widget.initialName ?? '',
    );
    _brandController = TextEditingController(
      text: editing?.brand ?? widget.initialBrand ?? '',
    );
    _priceController = TextEditingController(
      text: editing?.price?.toStringAsFixed(2) ??
          widget.initialPrice?.toStringAsFixed(2) ??
          '',
    );
    _noteController =
        TextEditingController(text: editing?.note ?? widget.initialNote ?? '');
    _quantityController = TextEditingController(
      text: '${editing?.quantity ?? widget.initialQuantity ?? 1}',
    );
    _quantityTouched = editing != null || widget.initialQuantity != null;
    _zoneId =
        editing?.zoneId ?? widget.initialZoneId ?? AppConstants.zoneFridge;
    _category = editing?.category ?? widget.initialCategory;
    _customCategoryController = TextEditingController(
      text: _category != null &&
              !ProductLabels.categories.containsKey(_category) &&
              _category != 'other'
          ? _category
          : '',
    );
    _categoryTouched =
        editing?.category != null || widget.initialCategory != null;
    _unit = editing?.unit ?? widget.initialUnit ?? 'pcs';
    _expiryDate = editing?.expiryDate ??
        widget.initialExpiry ??
        DateTime.now().add(const Duration(days: 7));
    _expiryTouched = editing != null || widget.initialExpiry != null;
    _openedDate =
        editing?.openedDate ?? (widget.initialOpened ? DateTime.now() : null);
    _openingDays = widget.initialOpeningDays ??
        editing?.afterOpeningStorageDays ??
        ProductMatcher.estimateAfterOpening(_category ?? 'other');
    _openingDaysController = TextEditingController(text: '$_openingDays');

    if (!_expiryTouched && _category != null) {
      final days = ProductMatcher.estimateShelfLife(_category!, _zoneId);
      _expiryDate = DateTime.now().add(Duration(days: days));
    }
    _sealedExpiryDate = _expiryDate;
    _expiryDate = _effectiveOpenedExpiry(_sealedExpiryDate);

    if (editing == null &&
        _category == null &&
        _nameController.text.isNotEmpty) {
      _applySuggestions(_nameController.text);
    }
    if (editing == null && widget.initialBarcode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final existing = await ref
            .read(productRepositoryProvider)
            .findByBarcode(widget.initialBarcode!);
        if (mounted && existing != null) {
          setState(() => _duplicateExists = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _priceController.dispose();
    _noteController.dispose();
    _quantityController.dispose();
    _customCategoryController.dispose();
    _openingDaysController.dispose();
    super.dispose();
  }

  /// Подставляет категорию и срок по названию продукта.
  void _applySuggestions(String name) {
    if (name.trim().length < 3) return;
    final match = ProductMatcher.inferCategory(name);
    final (qty, unit) = ProductMatcher.extractQuantity(name);
    setState(() {
      if (!_categoryTouched) _category = match.category;
      if (!_quantityTouched && unit != 'pcs') {
        _unit = unit;
        _quantityController.text = '$qty';
      }
      if (!_expiryTouched) {
        final days = ProductMatcher.estimateShelfLife(
          _category ?? match.category,
          _zoneId,
        );
        _sealedExpiryDate = DateTime.now().add(Duration(days: days));
        _expiryDate = _effectiveOpenedExpiry(_sealedExpiryDate);
      }
    });
  }

  void _onZoneChanged(String zone) {
    setState(() {
      _zoneId = zone;
      if (!_expiryTouched && _category != null) {
        final days = ProductMatcher.estimateShelfLife(_category!, zone);
        _sealedExpiryDate = DateTime.now().add(Duration(days: days));
        _expiryDate = _effectiveOpenedExpiry(_sealedExpiryDate);
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _sealedExpiryDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      helpText: 'Годен до',
    );
    if (picked != null) {
      setState(() {
        _sealedExpiryDate = picked;
        _expiryDate = _effectiveOpenedExpiry(picked);
        _expiryTouched = true;
      });
    }
  }

  void _shiftExpiry(int days) {
    setState(() {
      _sealedExpiryDate = DateTime.now().add(Duration(days: days));
      _expiryDate = _effectiveOpenedExpiry(_sealedExpiryDate);
      _expiryTouched = true;
    });
  }

  Future<void> _scanDate() async {
    final result = await Navigator.of(context).push<ExpiryScanResult>(
      MaterialPageRoute(builder: (_) => const DateScanScreen()),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (_nameController.text.trim().isEmpty && result.suggestedName != null) {
        _nameController.text = result.suggestedName!;
      }
      if (!_categoryTouched && result.category != null) {
        _category = result.category;
      }
      if (result.zoneId != null) _zoneId = result.zoneId!;
      if (!_quantityTouched && result.unit != 'pcs') {
        _quantityController.text = '${result.quantity}';
        _unit = result.unit;
      }
      if (result.expiryDate != null) {
        _sealedExpiryDate = result.expiryDate!;
        _expiryDate = _effectiveOpenedExpiry(_sealedExpiryDate);
        _expiryTouched = true;
        _expirySource = ProductDataSource.packageOcr;
      }
      if (result.openingDays != null) {
        _openingDays = result.openingDays!;
        _openingDaysController.text = '$_openingDays';
        _expiryDate = _effectiveOpenedExpiry(_sealedExpiryDate);
      }
    });
  }

  void _toggleOpened(bool value) {
    setState(() {
      _openedDate = value ? DateTime.now() : null;
      _expiryDate = _effectiveOpenedExpiry(_sealedExpiryDate);
      if (value) _expiryTouched = true;
    });
  }

  DateTime _effectiveOpenedExpiry(DateTime sealedExpiry) {
    final opened = _openedDate;
    if (opened == null) return sealedExpiry;
    final afterOpening = opened.add(Duration(days: _openingDays));
    return afterOpening.isBefore(sealedExpiry) ? afterOpening : sealedExpiry;
  }

  void _updateOpeningDays(String raw) {
    final days = int.tryParse(raw.trim());
    if (days == null || days < 1 || days > 365) return;
    setState(() {
      _openingDays = days;
      _expiryDate = _effectiveOpenedExpiry(_sealedExpiryDate);
    });
  }

  String? get _categoryPickerValue {
    final category = _category;
    if (category == null) return null;
    return ProductLabels.categories.containsKey(category) ? category : 'other';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final repo = ref.read(productRepositoryProvider);
    final productLimit = ref.read(userProfileProvider).productLimit;
    final price = double.tryParse(_priceController.text.replaceAll(',', '.'));
    final quantity = int.tryParse(_quantityController.text) ?? 1;
    final brand = _brandController.text.trim();
    final note = _noteController.text.trim();

    try {
      if (widget.editing != null) {
        await repo.update(
          widget.editing!.copyWith(
            name: _nameController.text.trim(),
            brand: brand.isEmpty ? null : brand,
            category: _category,
            zoneId: _zoneId,
            expiryDate: _expiryDate,
            quantity: quantity,
            unit: _unit,
            price: price,
            note: note.isEmpty ? null : note,
            openedDate: _openedDate,
          ),
        );
      } else {
        await repo.add(
          name: _nameController.text.trim(),
          brand: brand.isEmpty ? null : brand,
          barcode: widget.initialBarcode,
          category: _category,
          zoneId: _zoneId,
          expiryDate: _expiryDate,
          quantity: quantity,
          unit: _unit,
          price: price,
          note: note.isEmpty ? null : note,
          openedDate: _openedDate,
          addMethod: widget.addMethod,
          maxActiveProducts: productLimit,
        );
      }
      if (widget.initialBarcode != null) {
        await ref.read(productResolutionServiceProvider).submitCatalogFeedback(
              barcode: widget.initialBarcode!,
              name: _nameController.text.trim(),
              brand: brand.isEmpty ? null : brand,
              category: _category,
              zoneId: _zoneId,
            );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editing != null;
    final limitReached = ref.watch(productLimitReachedProvider);
    final blocked = !isEditing && limitReached;
    final daysLeft = AppDateUtils.daysUntil(_expiryDate);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Редактировать' : 'Новый продукт'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            if (widget.initialSource != null)
              _SourceBanner(
                source: widget.initialSource!,
                confidence: widget.initialConfidence ?? 0.5,
              ),
            if (_duplicateExists)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.content_copy_rounded),
                  title: Text('Такой продукт уже есть'),
                  subtitle: Text('Новый экземпляр будет добавлен отдельно.'),
                ),
              ),
            for (final warning in widget.recallWarnings)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded),
                  title: const Text('Предупреждение об отзыве партии'),
                  subtitle: Text(warning),
                ),
              ),
            if (blocked)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Достигнут лимит бесплатного тарифа '
                    '(${AppConstants.maxFreeProducts} продуктов). '
                    'Удалите что-нибудь или оформите Premium.',
                  ),
                ),
              ),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Название *',
                prefixIcon: Icon(Icons.label_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) => _validateName(v),
              onChanged: _applySuggestions,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _brandController,
              decoration: const InputDecoration(
                labelText: 'Бренд',
                prefixIcon: Icon(Icons.storefront_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              key: ValueKey(_categoryPickerValue),
              initialValue: _categoryPickerValue,
              decoration: const InputDecoration(
                labelText: 'Категория',
                prefixIcon: Icon(Icons.category_outlined),
                border: OutlineInputBorder(),
              ),
              items: [
                for (final entry in ProductLabels.categories.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
              onChanged: (value) {
                setState(() {
                  if (value == 'other') {
                    final custom = _customCategoryController.text.trim();
                    _category = custom.isEmpty ? 'other' : custom;
                  } else {
                    _category = value;
                  }
                  _categoryTouched = true;
                  if (!_expiryTouched && value != null) {
                    final days =
                        ProductMatcher.estimateShelfLife(value, _zoneId);
                    _sealedExpiryDate =
                        DateTime.now().add(Duration(days: days));
                    _expiryDate = _effectiveOpenedExpiry(_sealedExpiryDate);
                  }
                });
              },
            ),
            if (_categoryPickerValue == 'other') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _customCategoryController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Своя категория',
                  hintText: 'Например, детское питание',
                  prefixIcon: Icon(Icons.edit_outlined),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isNotEmpty && text.length < 2) {
                    return 'Минимум 2 символа';
                  }
                  if (text.length > 40) return 'Не больше 40 символов';
                  return null;
                },
                onChanged: (value) => setState(() {
                  final custom = value.trim();
                  _category = custom.isEmpty ? 'other' : custom;
                  _categoryTouched = true;
                }),
              ),
            ],
            const SizedBox(height: 20),
            Text('Где хранится', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: AppConstants.zoneFridge,
                  label: Text('Холод.'),
                  icon: Icon(Icons.kitchen),
                ),
                ButtonSegment(
                  value: AppConstants.zoneFreezer,
                  label: Text('Мороз.'),
                  icon: Icon(Icons.ac_unit),
                ),
                ButtonSegment(
                  value: AppConstants.zonePantry,
                  label: Text('Шкаф'),
                  icon: Icon(Icons.shelves),
                ),
              ],
              selected: {_zoneId},
              onSelectionChanged: (s) => _onZoneChanged(s.first),
            ),
            const SizedBox(height: 20),
            Text('Годен до', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(
                  Icons.event,
                  color: AppTheme.statusColor(
                    daysLeft < 0
                        ? AppConstants.statusExpired
                        : daysLeft <= 1
                            ? AppConstants.statusCritical
                            : daysLeft <= 3
                                ? AppConstants.statusExpiringSoon
                                : AppConstants.statusFresh,
                  ),
                ),
                title: Text(AppDateUtils.fullDate(_expiryDate)),
                subtitle: Text(AppDateUtils.daysRemaining(daysLeft)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _scanDate,
              icon: const Icon(Icons.document_scanner_outlined),
              label: Text(
                _expirySource == ProductDataSource.packageOcr
                    ? 'Упаковка распознана · переснять'
                    : 'Считать упаковку и дату',
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final preset in const [
                  (1, '1 день'),
                  (3, '3 дня'),
                  (7, 'Неделя'),
                  (30, 'Месяц'),
                  (180, 'Полгода'),
                ])
                  ActionChip(
                    label: Text(preset.$2),
                    onPressed: () => _shiftExpiry(preset.$1),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    value: _openedDate != null,
                    onChanged: _toggleOpened,
                    secondary: const Icon(Icons.inventory_2_outlined),
                    title: const Text('Упаковка уже вскрыта'),
                    subtitle: Text('После вскрытия хранить $_openingDays дн.'),
                  ),
                  if (_openedDate != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Row(
                        children: [
                          const Expanded(child: Text('Срок после вскрытия')),
                          SizedBox(
                            width: 120,
                            child: TextFormField(
                              controller: _openingDaysController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.end,
                              decoration: const InputDecoration(
                                labelText: 'Дней',
                                suffixText: 'дн.',
                              ),
                              validator: (raw) {
                                final days = int.tryParse(raw?.trim() ?? '');
                                if (days == null || days < 1) {
                                  return 'От 1';
                                }
                                if (days > 365) return 'До 365';
                                return null;
                              },
                              onChanged: _updateOpeningDays,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    validator: _validateQuantity,
                    onChanged: (_) => _quantityTouched = true,
                    decoration: const InputDecoration(
                      labelText: 'Кол-во',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: const InputDecoration(
                      labelText: 'Единица',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'pcs', child: Text('шт')),
                      DropdownMenuItem(value: 'kg', child: Text('кг')),
                      DropdownMenuItem(value: 'g', child: Text('г')),
                      DropdownMenuItem(value: 'l', child: Text('л')),
                      DropdownMenuItem(value: 'ml', child: Text('мл')),
                    ],
                    onChanged: (v) => setState(() {
                      _unit = v ?? 'pcs';
                      _quantityTouched = true;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _priceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Цена',
                      suffixText: '₽',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validatePrice,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _noteController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Заметка',
                prefixIcon: Icon(Icons.notes),
                border: OutlineInputBorder(),
              ),
            ),
            if (_category != null) ...[
              const SizedBox(height: 16),
              _SmartTipsCard(
                tips: ProductMatcher.smartTips(
                  _category!,
                  zoneId: _zoneId,
                  daysLeft: AppDateUtils.daysUntil(_expiryDate),
                  duplicate: _duplicateExists,
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: (_saving || blocked) ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(isEditing ? 'Сохранить' : 'Добавить'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ),
      ),
    );
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Введите название';
    if (name.length < 2) return 'Минимум 2 символа';
    if (name.length > 80) return 'Не больше 80 символов';
    return null;
  }

  String? _validateQuantity(String? value) {
    final quantity = int.tryParse(value?.trim() ?? '');
    if (quantity == null) return 'Введите число';
    if (quantity < 1) return 'Минимум 1';
    if (quantity > 9999) return 'Слишком много';
    return null;
  }

  String? _validatePrice(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    final price = double.tryParse(raw.replaceAll(',', '.'));
    if (price == null) return 'Неверная цена';
    if (price < 0) return 'Не может быть меньше 0';
    if (price > 99999999) return 'Слишком большая сумма';
    return null;
  }
}

class _SourceBanner extends StatelessWidget {
  const _SourceBanner({required this.source, required this.confidence});

  final ProductDataSource source;
  final double confidence;

  @override
  Widget build(BuildContext context) {
    final confident = confidence >= 0.85;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ListTile(
        leading: Icon(
          confident ? Icons.auto_awesome_rounded : Icons.fact_check_outlined,
          color: confident
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.tertiary,
        ),
        title: Text(source.label),
        subtitle: Text(
          confident
              ? 'Поля заполнены автоматически'
              : 'Проверьте автоматически заполненные поля',
        ),
        trailing: Text('${(confidence * 100).round()}%'),
      ),
    );
  }
}

class _SmartTipsCard extends StatelessWidget {
  const _SmartTipsCard({required this.tips});

  final List<String> tips;

  @override
  Widget build(BuildContext context) {
    if (tips.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded,
                    color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Умные подсказки',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            for (final tip in tips)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text('• $tip'),
              ),
          ],
        ),
      ),
    );
  }
}
