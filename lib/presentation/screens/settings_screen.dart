import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/settings_providers.dart';
import '../../services/background_service.dart';
import '../../services/notification_service.dart';
import 'archive_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final notifier = ref.read(userProfileProvider.notifier);
    final supportsBackgroundExpiry =
        defaultTargetPlatform == TargetPlatform.android;

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          const _Section(title: 'Уведомления'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Напоминания о сроках'),
            subtitle: supportsBackgroundExpiry
                ? null
                : const Text(
                    'Фоновые проверки пока доступны только на Android'),
            value: profile.notificationsEnabled,
            onChanged: !supportsBackgroundExpiry
                ? null
                : (v) async {
                    if (v) {
                      final granted = await NotificationService.instance
                          .requestPermissions();
                      if (!granted && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Разрешите уведомления в настройках системы'),
                          ),
                        );
                        return;
                      }
                      await notifier.setNotificationsEnabled(true);
                      try {
                        await BackgroundService.schedule(
                          hour: profile.notificationHour,
                          minute: profile.notificationMinute,
                        );
                      } catch (error) {
                        await notifier.setNotificationsEnabled(false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Не удалось запланировать уведомления: $error',
                              ),
                            ),
                          );
                        }
                      }
                    } else {
                      await notifier.setNotificationsEnabled(false);
                      await BackgroundService.cancel();
                      await NotificationService.instance.cancelAll();
                    }
                  },
          ),
          ListTile(
            enabled: profile.notificationsEnabled,
            leading: const Icon(Icons.schedule),
            title: const Text('Фоновая проверка'),
            subtitle: const Text(
              'Примерно раз в час — Android может немного задержать запуск',
            ),
            trailing: const Icon(Icons.info_outline),
          ),
          ListTile(
            enabled: profile.notificationsEnabled,
            leading: const Icon(Icons.event_available_outlined),
            title: const Text('Предупреждать заранее'),
            subtitle: const Text('Можно указать часы или дни'),
            trailing: Text(_leadTimeLabel(profile.notifyHoursBefore)),
            onTap: !profile.notificationsEnabled
                ? null
                : () async {
                    final hours = await _pickNotifyHours(
                      context,
                      profile.notifyHoursBefore,
                    );
                    if (hours != null) {
                      await notifier.setNotifyHoursBefore(hours);
                    }
                  },
          ),
          ListTile(
            leading: const Icon(Icons.notification_add_outlined),
            title: const Text('Проверить уведомления'),
            subtitle: const Text('Запросить разрешение и отправить тест'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final sent =
                  await NotificationService.instance.showTestNotification();
              if (!sent) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Не удалось показать уведомление. Разрешите уведомления '
                      'для Eat on Time в настройках Android.',
                    ),
                  ),
                );
                return;
              }
              messenger.showSnackBar(
                const SnackBar(
                    content: Text('Тестовое уведомление отправлено')),
              );
            },
          ),
          const _Section(title: 'Внешний вид'),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Тема'),
            trailing: DropdownButton<String>(
              value: profile.themeMode,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'system', child: Text('Системная')),
                DropdownMenuItem(value: 'light', child: Text('Светлая')),
                DropdownMenuItem(value: 'dark', child: Text('Тёмная')),
              ],
              onChanged: (v) => v == null ? null : notifier.setThemeMode(v),
            ),
          ),
          const _Section(title: 'Данные'),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Архив'),
            subtitle: const Text('Съеденное и выброшенное'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ArchiveScreen()),
            ),
          ),
          const _Section(title: 'О приложении'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _SupportCard(
              onTap: () => _openDonationPage(context),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Источники карточек товаров'),
            subtitle:
                const Text('Eat on Time · Open Food Facts · официальные шлюзы'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Источники данных',
              children: const [
                Text(
                  'Карточки могут дополняться данными Open Food Facts '
                  '(ODbL; изображения CC BY-SA), локальной историей и '
                  'серверными официальными источниками. Срок конкретной '
                  'упаковки всегда нужно проверять по маркировке.',
                ),
              ],
            ),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Eat on Time'),
            subtitle: Text('Версия 1.1.0 · умный хранитель сроков годности'),
          ),
        ],
      ),
    );
  }

  String _leadTimeLabel(int hours) {
    if (hours % 24 == 0) {
      final days = hours ~/ 24;
      return '$days ${_plural(days, 'день', 'дня', 'дней')}';
    }
    return '$hours ${_plural(hours, 'час', 'часа', 'часов')}';
  }

  String _plural(int value, String one, String few, String many) {
    final mod10 = value % 10;
    final mod100 = value % 100;
    if (mod10 == 1 && mod100 != 11) return one;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return few;
    }
    return many;
  }

  Future<int?> _pickNotifyHours(BuildContext context, int currentHours) async {
    var unit = currentHours >= 24 && currentHours % 24 == 0 ? 'days' : 'hours';
    final initial = unit == 'days' ? currentHours ~/ 24 : currentHours;
    final controller = TextEditingController(text: '$initial');
    final formKey = GlobalKey<FormState>();
    try {
      return await showDialog<int>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Когда предупредить'),
            content: Form(
              key: formKey,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Значение'),
                      validator: (raw) {
                        final value = int.tryParse(raw?.trim() ?? '');
                        if (value == null || value < 1) return 'Минимум 1';
                        final hours = unit == 'days' ? value * 24 : value;
                        if (hours > 720) return 'Не больше 30 дней';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: unit,
                      decoration: const InputDecoration(labelText: 'Единица'),
                      items: const [
                        DropdownMenuItem(value: 'hours', child: Text('Часы')),
                        DropdownMenuItem(value: 'days', child: Text('Дни')),
                      ],
                      onChanged: (value) => setDialogState(
                        () => unit = value ?? 'hours',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  final value = int.parse(controller.text.trim());
                  Navigator.pop(
                    dialogContext,
                    unit == 'days' ? value * 24 : value,
                  );
                },
                child: const Text('Сохранить'),
              ),
            ],
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _openDonationPage(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(
      Uri.parse(AppConstants.donationUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Не удалось открыть страницу поддержки'),
        ),
      );
    }
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: 'Поддержать автора через DonationAlerts',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primaryContainer,
                  scheme.secondaryContainer,
                ],
              ),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.82),
                    shape: BoxShape.circle,
                  ),
                  child: const Text('😺', style: TextStyle(fontSize: 28)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Поддержать автора',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Поддержи пж, для тебя стараюсь',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.open_in_new_rounded,
                  color: scheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
