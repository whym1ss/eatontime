import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/product_labels.dart';
import '../../data/models/product_resolution.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/product_repository.dart';
import '../../providers/core_providers.dart';
import '../../providers/settings_providers.dart';
import 'add_product_screen.dart';
import 'fiscal_receipt_scan_screen.dart';
import 'receipt_scan_screen.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
  );

  bool _handling = false;
  bool _batchMode = false;
  final List<ResolvedProductDraft> _batch = [];
  final Set<String> _seen = {};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (raw == null || raw.isEmpty) return;
    if (_batchMode && !_seen.add(raw)) {
      _showMessage('Этот код уже в списке');
      return;
    }

    setState(() => _handling = true);
    await _controller.stop();
    final resolver = ref.read(productResolutionServiceProvider);
    final parsed = resolver.parseCode(raw);

    if (parsed.isFiscalReceipt) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FiscalReceiptScanScreen(initialQr: raw),
        ),
      );
      if (!mounted) return;
      setState(() => _handling = false);
      await _controller.start();
      return;
    }

    final resolved = await resolver.resolve(raw);
    if (!mounted) return;
    if (_batchMode) {
      setState(() {
        _batch.add(resolved);
        _handling = false;
      });
      _showMessage('${resolved.name?.value ?? 'Код'} добавлен в пакет');
      await _controller.start();
      return;
    }

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddProductScreen(
          initialName: resolved.name?.value,
          initialBrand: resolved.brand?.value,
          initialBarcode: resolved.code.gtin ?? resolved.code.raw,
          initialCategory: resolved.category?.value,
          initialZoneId: resolved.zoneId?.value,
          initialExpiry: resolved.suggestedExpiry(DateTime.now()),
          initialQuantity: resolved.quantity,
          initialUnit: resolved.unit,
          initialSource: resolved.primarySource,
          initialConfidence: resolved.confidence,
          initialOpeningDays: resolved.openingDays,
          recallWarnings: resolved.recallWarnings,
          addMethod: AppConstants.addBarcode,
        ),
      ),
    );

    if (!mounted) return;
    if (saved == true) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _handling = false);
    await _controller.start();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _finishBatch() async {
    if (_batch.isEmpty) return;
    await _controller.stop();
    if (!mounted) return;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.94,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Пакет · ${_batch.length}',
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: _batch.length,
                itemBuilder: (_, index) {
                  final item = _batch[index];
                  return ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(item.name?.value ?? 'Неизвестный продукт'),
                    subtitle: Text(
                      '${ProductLabels.category(item.category?.value ?? 'other')} · ${item.primarySource.label}',
                    ),
                    trailing: item.recallWarnings.isEmpty
                        ? const Icon(Icons.check_circle_outline,
                            color: Colors.green)
                        : const Icon(Icons.warning_amber_rounded,
                            color: Colors.red),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(sheetContext, true),
                icon: const Icon(Icons.inventory_2_outlined),
                label: Text('Добавить ${_batch.length} продуктов'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      if (mounted) await _controller.start();
      return;
    }

    final warnings = _batch.expand((e) => e.recallWarnings).toList();
    if (warnings.isNotEmpty && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: const Text('Есть предупреждения'),
          content: Text(warnings.join('\n\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Вернуться'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Всё равно добавить'),
            ),
          ],
        ),
      );
      if (proceed != true) {
        await _controller.start();
        return;
      }
    }

    try {
      final repo = ref.read(productRepositoryProvider);
      final limit = ref.read(userProfileProvider).productLimit;
      await repo.addMany(
        [
          for (final item in _batch)
            ProductDraft(
              name: item.name?.value ?? 'Новый продукт',
              brand: item.brand?.value,
              barcode: item.code.gtin ?? item.code.raw,
              category: item.category?.value,
              zoneId: item.zoneId?.value ?? AppConstants.zoneFridge,
              expiryDate: item.suggestedExpiry(DateTime.now()),
              quantity: item.quantity,
              unit: item.unit,
              addMethod: AppConstants.addBarcode,
            ),
        ],
        maxActiveProducts: limit,
      );
      for (final item in _batch) {
        unawaited(
            ref.read(productResolutionServiceProvider).submitCatalogFeedback(
                  barcode: item.code.gtin ?? item.code.raw,
                  name: item.name?.value ?? 'Новый продукт',
                  brand: item.brand?.value,
                  category: item.category?.value,
                  zoneId: item.zoneId?.value,
                ));
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Не удалось добавить пакет: $e');
      await _controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_batchMode ? 'Разобрать пакет' : 'Умное сканирование'),
        actions: [
          IconButton(
            tooltip: 'Серийное сканирование',
            icon:
                Icon(_batchMode ? Icons.layers_rounded : Icons.layers_outlined),
            onPressed: _handling
                ? null
                : () => setState(() {
                      _batchMode = !_batchMode;
                      if (!_batchMode) {
                        _batch.clear();
                        _seen.clear();
                      }
                    }),
          ),
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => Center(
              child: Text('Нет доступа к камере\n${error.errorCode.name}',
                  textAlign: TextAlign.center),
            ),
          ),
          const _ScannerOverlay(),
          if (_handling)
            Container(
              color: Colors.black54,
              child: const Center(child: CircularProgressIndicator()),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Text(
                      _batchMode
                          ? 'Сканируйте упаковки подряд · найдено ${_batch.length}'
                          : 'Штрихкод, QR или Data Matrix',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_batchMode && _batch.isNotEmpty)
                  FilledButton.icon(
                    onPressed: _handling ? null : _finishBatch,
                    icon: const Icon(Icons.check_rounded),
                    label: Text('Проверить пакет (${_batch.length})'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ReceiptScanScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.receipt_long),
                          label: const Text('Чек'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AddProductScreen(),
                            ),
                          ),
                          icon: const Icon(Icons.edit),
                          label: const Text('Вручную'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlay extends StatefulWidget {
  const _ScannerOverlay();

  @override
  State<_ScannerOverlay> createState() => _ScannerOverlayState();
}

class _ScannerOverlayState extends State<_ScannerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: 280,
          height: 190,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ),
              AnimatedBuilder(
                animation: _animation,
                builder: (_, __) => Positioned(
                  left: 16,
                  right: 16,
                  top: 15 + 155 * _animation.value,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: const Color(0xFF70E1A1),
                      boxShadow: const [
                        BoxShadow(color: Color(0x9970E1A1), blurRadius: 8),
                      ],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
