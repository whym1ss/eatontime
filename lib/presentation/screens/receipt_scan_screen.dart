import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/product_labels.dart';
import '../../core/utils/product_matcher.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/product_repository.dart';
import '../../providers/core_providers.dart';
import '../../providers/settings_providers.dart';
import '../../services/ocr_service.dart';
import 'fiscal_receipt_scan_screen.dart';

/// Скан чека: фото → OCR → список позиций → массовое добавление.
class ReceiptScanScreen extends ConsumerStatefulWidget {
  const ReceiptScanScreen({super.key});

  @override
  ConsumerState<ReceiptScanScreen> createState() => _ReceiptScanScreenState();
}

class _ReceiptScanScreenState extends ConsumerState<ReceiptScanScreen> {
  CameraController? _camera;
  bool _initializing = true;
  bool _processing = false;
  String? _error;
  List<ReceiptItem>? _items;
  String _zoneId = AppConstants.zoneFridge;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = 'Камера не найдена';
          _initializing = false;
        });
        return;
      }
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _camera = controller;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось открыть камеру: $e';
        _initializing = false;
      });
    }
  }

  Future<void> _retryCamera() async {
    await _camera?.dispose();
    if (!mounted) return;
    setState(() {
      _camera = null;
      _error = null;
      _items = null;
      _initializing = true;
    });
    await _initCamera();
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || _processing) return;

    setState(() => _processing = true);
    XFile? captured;
    try {
      captured = await camera.takePicture();
      final items = await OcrService.instance.scanReceipt(captured.path);
      if (!mounted) return;
      setState(() {
        _items = items;
        _processing = false;
      });
      if (items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось распознать позиции. Попробуйте ещё раз.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error = 'Ошибка распознавания: $e';
      });
    } finally {
      final path = captured?.path;
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {
          // Временный файл мог быть уже удалён системой.
        }
      }
    }
  }

  Future<void> _saveSelected() async {
    final items = _items?.where((i) => i.selected).toList() ?? [];
    if (items.isEmpty) return;

    setState(() => _processing = true);
    final repo = ref.read(productRepositoryProvider);
    final limit = ref.read(userProfileProvider).productLimit;

    try {
      await repo.addMany(
        [
          for (final item in items)
            ProductDraft(
              name: item.name,
              category: item.category,
              zoneId: _zoneId,
              expiryDate: DateTime.now().add(
                Duration(
                  days: ProductMatcher.estimateShelfLife(
                    item.category,
                    _zoneId,
                  ),
                ),
              ),
              quantity: item.quantity,
              unit: item.unit,
              price: item.price,
              addMethod: AppConstants.addOcr,
            ),
        ],
        maxActiveProducts: limit,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось добавить чек: $e')),
      );
      return;
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    messenger.showSnackBar(
      SnackBar(content: Text('Добавлено ${items.length} продуктов')),
    );
  }

  Future<void> _editItem(ReceiptItem item) async {
    final controller = TextEditingController(text: item.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Исправить название'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Название',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.length >= 2) Navigator.pop(dialogContext, trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.length >= 2) Navigator.pop(dialogContext, trimmed);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    final match = ProductMatcher.inferCategory(name);
    setState(() {
      item.name = name;
      item.category = match.category;
      item.confidence = match.confidence;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Скан чека'),
        actions: [
          IconButton(
            tooltip: 'QR кассового чека',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const FiscalReceiptScanScreen(),
              ),
            ),
          ),
          if (_items != null)
            TextButton(
              onPressed: () => setState(() {
                _items = null;
                _error = null;
              }),
              child: const Text('Заново'),
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _items == null ? null : _buildSaveBar(),
    );
  }

  Widget _buildBody() {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _retryCamera,
                icon: const Icon(Icons.refresh),
                label: const Text('Попробовать снова'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items != null) return _buildItemList();

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_camera != null) CameraPreview(_camera!),
        Positioned(
          left: 0,
          right: 0,
          bottom: 32,
          child: Column(
            children: [
              const Text(
                'Сфотографируйте чек целиком',
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              FloatingActionButton.large(
                onPressed: _processing ? null : _capture,
                child: _processing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Icon(Icons.camera_alt),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItemList() {
    final items = _items!;
    if (items.isEmpty) {
      return const Center(child: Text('Позиции не найдены'));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<String>(
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
            onSelectionChanged: (s) => setState(() => _zoneId = s.first),
          ),
        ),
        for (final item in items)
          CheckboxListTile(
            value: item.selected,
            onChanged: (v) => setState(() => item.selected = v ?? false),
            secondary: IconButton(
              tooltip: 'Исправить название',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editItem(item),
            ),
            title: Text(item.name),
            subtitle: Text(
              [
                if (item.price != null) '${item.price!.toStringAsFixed(2)} ₽',
                ProductLabels.category(item.category),
                '${ProductMatcher.estimateShelfLife(item.category, _zoneId)} дн.',
              ].join(' · '),
            ),
          ),
      ],
    );
  }

  Widget _buildSaveBar() {
    final count = _items?.where((i) => i.selected).length ?? 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: (count == 0 || _processing) ? null : _saveSelected,
          icon: const Icon(Icons.check),
          label: Text('Добавить ($count)'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
      ),
    );
  }
}
