import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/constants/app_constants.dart';
import '../../core/themes/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/voice_parser.dart';
import '../../data/models/user_profile.dart';
import '../../providers/core_providers.dart';
import '../../providers/settings_providers.dart';
import 'add_product_screen.dart';

/// Голосовой ввод: «молоко до пятницы» → готовая карточка продукта.
class VoiceAddScreen extends ConsumerStatefulWidget {
  const VoiceAddScreen({super.key});

  @override
  ConsumerState<VoiceAddScreen> createState() => _VoiceAddScreenState();
}

class _VoiceAddScreenState extends ConsumerState<VoiceAddScreen> {
  final SpeechToText _speech = SpeechToText();
  final TextEditingController _transcriptController = TextEditingController();

  bool _available = false;
  bool _listening = false;
  bool _saving = false;
  String _transcript = '';
  String? _localeId;
  String? _error;
  VoiceCommand? _command;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final available = await _speech.initialize(
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _error = e.errorMsg;
            _listening = false;
          });
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (!mounted) return;
            setState(() {
              _listening = false;
              _parseTranscript();
            });
          }
        },
      );
      if (!mounted) return;
      String? localeId;
      if (available) {
        final locales = await _speech.locales();
        for (final locale in locales) {
          final normalized = locale.localeId.toLowerCase().replaceAll('-', '_');
          if (normalized == 'ru_ru') {
            localeId = locale.localeId;
            break;
          }
          if (localeId == null && normalized.startsWith('ru')) {
            localeId = locale.localeId;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _available = available;
        _localeId = localeId;
        if (!available) _error = 'Распознавание речи недоступно';
      });
      if (available) _startListening();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _startListening() async {
    if (!_available || _listening) return;
    setState(() {
      _listening = true;
      _error = null;
      _transcript = '';
      _transcriptController.clear();
      _command = null;
    });

    await _speech.listen(
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        onDevice: false,
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(seconds: 30),
        autoPunctuation: true,
        localeId: _localeId,
      ),
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _transcript = result.recognizedWords;
          _transcriptController.value = TextEditingValue(
            text: _transcript,
            selection: TextSelection.collapsed(offset: _transcript.length),
          );
          if (result.finalResult && _transcript.trim().isNotEmpty) {
            _parseTranscript();
            _listening = false;
          }
        });
      },
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _parseTranscript();
    });
  }

  void _parseTranscript() {
    final text = _transcriptController.text.trim();
    _transcript = text;
    _command = text.isEmpty ? null : VoiceParser.parse(text);
  }

  Future<void> _save() async {
    final command = _command;
    if (command == null || !command.isValid || _saving) return;

    setState(() => _saving = true);
    try {
      await ref.read(productRepositoryProvider).add(
            name: command.name,
            category: command.category,
            zoneId: command.zoneId,
            expiryDate: command.expiryDate,
            quantity: command.quantity,
            unit: command.unit,
            addMethod: AppConstants.addVoice,
            maxActiveProducts: ref.read(userProfileProvider).productLimit,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось добавить: $e')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('«${command.name}» добавлен')),
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _transcriptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final command = _command;

    return Scaffold(
      appBar: AppBar(title: const Text('Голосовой ввод')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Text(
              _listening
                  ? 'Слушаю…'
                  : command != null
                      ? 'Распознано'
                      : 'Нажмите на микрофон и скажите, что купили',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Например: «молоко до пятницы» или «курица на 3 дня в морозилку»',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: _listening ? _stopListening : _startListening,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: _listening ? 128 : 108,
                  height: _listening ? 128 : 108,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (_listening
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.primaryContainer)
                        .withValues(alpha: _listening ? 1 : 0.6),
                  ),
                  child: Icon(
                    _listening ? Icons.mic : Icons.mic_none,
                    size: 48,
                    color: _listening
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            if (_transcript.isNotEmpty || !_listening)
              TextField(
                controller: _transcriptController,
                enabled: !_listening,
                textAlign: TextAlign.center,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Что услышало приложение',
                  hintText: 'Можно исправить текст вручную',
                  prefixIcon: Icon(Icons.edit_outlined),
                ),
                onChanged: (_) => setState(_parseTranscript),
                onSubmitted: (_) => setState(_parseTranscript),
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const Spacer(),
            if (command != null && command.isValid) ...[
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        command.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            AppTheme.zoneIcon(command.zoneId),
                            size: 16,
                            color: AppTheme.zoneColor(command.zoneId),
                          ),
                          const SizedBox(width: 6),
                          Text(AppTheme.zoneLabel(command.zoneId)),
                          const SizedBox(width: 16),
                          const Icon(Icons.event, size: 16),
                          const SizedBox(width: 6),
                          Text(AppDateUtils.fullDate(command.expiryDate)),
                        ],
                      ),
                      if (!command.hadExplicitDate) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Срок предложен автоматически — проверьте перед сохранением.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => AddProductScreen(
                                    initialName: command.name,
                                    initialExpiry: command.expiryDate,
                                    initialCategory: command.category,
                                    initialZoneId: command.zoneId,
                                    initialQuantity: command.quantity,
                                    initialUnit: command.unit,
                                    addMethod: AppConstants.addVoice,
                                  ),
                                ),
                              ),
                      icon: const Icon(Icons.tune),
                      label: const Text('Уточнить'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(_saving ? 'Добавляем…' : 'Добавить'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
