import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/utils/date_utils.dart';
import '../../data/models/product_resolution.dart';
import '../../services/ocr_service.dart';

class DateScanScreen extends StatefulWidget {
  const DateScanScreen({super.key});

  @override
  State<DateScanScreen> createState() => _DateScanScreenState();
}

class _DateScanScreenState extends State<DateScanScreen> {
  CameraController? _camera;
  bool _loading = true;
  bool _processing = false;
  String? _error;
  ExpiryScanResult? _result;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('Камера не найдена');
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _camera = controller;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось открыть камеру: $e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _captureBurst() async {
    final camera = _camera;
    if (camera == null || _processing) return;
    setState(() {
      _processing = true;
      _result = null;
      _error = null;
    });
    final paths = <String>[];
    try {
      for (var i = 0; i < 3; i++) {
        final shot = await camera.takePicture();
        paths.add(shot.path);
        if (i < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 180));
        }
      }
      final result = await OcrService.instance.scanExpiry(paths);
      if (!mounted) return;
      setState(() {
        _result = result;
        _processing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось распознать дату: $e';
        _processing = false;
      });
    } finally {
      for (final path in paths) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сканирование срока')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _camera == null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ))
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_camera != null) CameraPreview(_camera!),
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          height: 116,
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2),
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 24,
                      child: _buildBottomCard(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildBottomCard() {
    final result = _result;
    return Card(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (result?.expiryDate != null ||
                result?.suggestedName != null) ...[
              const Icon(Icons.verified_rounded, color: Colors.green, size: 34),
              const SizedBox(height: 6),
              if (result!.suggestedName != null)
                Text(result.suggestedName!,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center),
              if (result.expiryDate != null)
                Text('Годен до ${AppDateUtils.fullDate(result.expiryDate!)}'),
              if (result.openingDays != null)
                Text('После вскрытия: ${result.openingDays} дн.'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _processing ? null : _captureBurst,
                      child: const Text('Переснять'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, result),
                      child: const Text('Использовать'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                result == null
                    ? 'Наведите рамку на название или «годен до» и держите камеру неподвижно'
                    : 'Текст не найден. Попробуйте ближе и без бликов.',
                textAlign: TextAlign.center,
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _processing ? null : _captureBurst,
                icon: _processing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.document_scanner_outlined),
                label: Text(_processing ? 'Читаем 3 кадра…' : 'Считать дату'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
