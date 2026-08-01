import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/product_matcher.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/product_repository.dart';
import '../../providers/core_providers.dart';
import '../../providers/settings_providers.dart';
import 'receipt_scan_screen.dart';

/// Импорт QR фискального чека через разрешённый серверный шлюз. Приложение не
/// обращается к неофициальным endpoint ФНС и не хранит учётные данные в APK.
class FiscalReceiptScanScreen extends ConsumerStatefulWidget {
  const FiscalReceiptScanScreen({super.key, this.initialQr});

  final String? initialQr;

  @override
  ConsumerState<FiscalReceiptScanScreen> createState() =>
      _FiscalReceiptScanScreenState();
}

class _FiscalReceiptScanScreenState
    extends ConsumerState<FiscalReceiptScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _loading = false;
  bool _handled = false;
  String? _qr;
  List<_FiscalItem>? _items;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (widget.initialQr != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _resolve(widget.initialQr!));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    _handled = true;
    await _controller.stop();
    await _resolve(raw);
  }

  Future<void> _resolve(String raw) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _qr = raw;
      _message = null;
    });
    final rows = await ref
        .read(productResolutionServiceProvider)
        .resolveFiscalReceipt(raw);
    if (!mounted) return;
    if (rows.isEmpty) {
      setState(() {
        _loading = false;
        _items = const [];
        _message = 'Официальный шлюз получения позиций чека пока не настроен. '
            'QR распознан, но список покупок безопаснее считать с фотографии.';
      });
      return;
    }
    setState(() {
      _loading = false;
      _items = [
        for (final row in rows) _FiscalItem.fromMap(row),
      ];
    });
  }

  Future<void> _save() async {
    final selected = _items?.where((e) => e.selected).toList() ?? [];
    if (selected.isEmpty) return;
    setState(() => _loading = true);
    try {
      final limit = ref.read(userProfileProvider).productLimit;
      await ref.read(productRepositoryProvider).addMany(
        [
          for (final item in selected)
            ProductDraft(
              name: item.name,
              category: item.category,
              zoneId: ProductMatcher.recommendZone(item.category),
              expiryDate: DateTime.now().add(Duration(
                days: ProductMatcher.estimateShelfLife(
                  item.category,
                  ProductMatcher.recommendZone(item.category),
                ),
              )),
              quantity: item.quantity,
              unit: item.unit,
              price: item.price,
              addMethod: AppConstants.addOcr,
            ),
        ],
        maxActiveProducts: limit,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Не удалось сохранить покупки: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('QR кассового чека')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : items == null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(controller: _controller, onDetect: _onDetect),
                    Center(
                      child: Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 2),
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 20,
                      right: 20,
                      bottom: 30,
                      child: Text(
                        'Наведите камеру на QR внизу кассового чека',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                )
              : _buildResult(items),
      bottomNavigationBar: items != null && items.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(
                      'Добавить выбранные (${items.where((e) => e.selected).length})'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildResult(List<_FiscalItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 52),
              const SizedBox(height: 14),
              Text(_message ?? 'Позиции не найдены',
                  textAlign: TextAlign.center),
              if (_qr != null) ...[
                const SizedBox(height: 8),
                Text('QR сохранён в текущем сеансе',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const ReceiptScanScreen()),
                ),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Сканировать фотографию чека'),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: items.length,
      itemBuilder: (_, index) {
        final item = items[index];
        return CheckboxListTile(
          value: item.selected,
          onChanged: (value) => setState(() => item.selected = value ?? false),
          title: Text(item.name),
          subtitle: Text([
            if (item.price != null) '${item.price!.toStringAsFixed(2)} ₽',
            if (item.quantity > 1) '${item.quantity} ${item.unit}',
          ].join(' · ')),
        );
      },
    );
  }
}

class _FiscalItem {
  _FiscalItem({
    required this.name,
    required this.category,
    this.price,
    this.quantity = 1,
    this.unit = 'pcs',
  });

  factory _FiscalItem.fromMap(Map<String, dynamic> row) {
    final name =
        (row['name'] ?? row['product_name'] ?? 'Позиция чека').toString();
    return _FiscalItem(
      name: name,
      category: row['category']?.toString() ??
          ProductMatcher.inferCategory(name).category,
      price: (row['price'] as num?)?.toDouble(),
      quantity: (row['quantity'] as num?)?.toInt() ?? 1,
      unit: row['unit']?.toString() ?? 'pcs',
    );
  }

  final String name;
  final String category;
  final double? price;
  final int quantity;
  final String unit;
  bool selected = true;
}
