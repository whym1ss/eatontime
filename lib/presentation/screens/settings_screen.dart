import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/product_repository.dart';
import '../../providers/core_providers.dart';
import '../../providers/product_providers.dart';
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
    final summary = ref.watch(homeSummaryProvider);
    final supportsBackgroundExpiry =
        defaultTargetPlatform == TargetPlatform.android;

    final time = TimeOfDay(
      hour: profile.notificationHour,
      minute: profile.notificationMinute,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          const _Section(title: 'Аккаунт'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(profile.displayName ?? profile.email ?? 'Гость'),
            subtitle: Text(
              profile.isPremium
                  ? 'Premium'
                  : AppConstants.billingEnabled
                      ? 'Бесплатный тариф'
                      : 'Локальный режим · без ограничений',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Продуктов в холодильнике'),
            trailing: Text(
              AppConstants.billingEnabled
                  ? '${summary.total} / ${profile.productLimit}'
                  : '${summary.total}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (AppConstants.billingEnabled && !profile.isPremium)
            ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text('Подключить Premium'),
              subtitle: const Text(
                'Без лимита продуктов, семейный доступ, экспорт',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showPremiumSheet(context, ref),
            ),
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
                      await BackgroundService.schedule(
                        hour: profile.notificationHour,
                        minute: profile.notificationMinute,
                      );
                    } else {
                      await BackgroundService.cancel();
                      await NotificationService.instance.cancelAll();
                    }
                    await notifier.setNotificationsEnabled(v);
                  },
          ),
          ListTile(
            enabled: profile.notificationsEnabled,
            leading: const Icon(Icons.schedule),
            title: const Text('Время напоминания'),
            trailing: Text(time.format(context)),
            onTap: !profile.notificationsEnabled
                ? null
                : () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: time,
                    );
                    if (picked == null) return;
                    await notifier.setNotificationTime(picked);
                    await BackgroundService.schedule(
                      hour: picked.hour,
                      minute: picked.minute,
                    );
                  },
          ),
          ListTile(
            enabled: profile.notificationsEnabled,
            leading: const Icon(Icons.event_available_outlined),
            title: const Text('Предупреждать заранее'),
            trailing: DropdownButton<int>(
              value: profile.notifyDaysBefore,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 1, child: Text('за 1 день')),
                DropdownMenuItem(value: 2, child: Text('за 2 дня')),
                DropdownMenuItem(value: 3, child: Text('за 3 дня')),
                DropdownMenuItem(value: 5, child: Text('за 5 дней')),
                DropdownMenuItem(value: 7, child: Text('за неделю')),
              ],
              onChanged: !profile.notificationsEnabled
                  ? null
                  : (v) => v == null ? null : notifier.setNotifyDaysBefore(v),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notification_add_outlined),
            title: const Text('Проверить уведомления'),
            subtitle: const Text('Отправить тестовое сообщение'),
            onTap: () async {
              await NotificationService.instance.show(
                id: 9999,
                title: 'Eat on Time',
                body: 'Уведомления работают 👌',
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
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Синхронизировать сейчас'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                final result = await ref.read(productRepositoryProvider).sync();
                messenger.showSnackBar(
                  SnackBar(content: Text(_syncMessage(result))),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Не удалось: $e')),
                );
              }
            },
          ),
          const _Section(title: 'О приложении'),
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
            subtitle: Text('Версия 1.0.0 · умный хранитель сроков годности'),
          ),
        ],
      ),
    );
  }

  String _syncMessage(SyncResult result) => switch (result) {
        SyncResult.synced => 'Данные синхронизированы',
        SyncResult.offline => 'Нет подключения к интернету',
        SyncResult.signedOut => 'Вход не выполнен — данные сохранены локально',
        SyncResult.unavailable =>
          'Supabase не настроен — данные хранятся локально',
        SyncResult.alreadyRunning => 'Синхронизация уже выполняется',
      };

  void _showPremiumSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Eat on Time Premium',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 14),
            const _Feature(
              icon: Icons.all_inclusive,
              text: 'Без лимита в '
                  '${AppConstants.maxFreeProducts} продуктов',
            ),
            const _Feature(
              icon: Icons.family_restroom,
              text: 'Общий холодильник для всей семьи',
            ),
            const _Feature(
              icon: Icons.receipt_long,
              text: 'Безлимитный скан чеков',
            ),
            const _Feature(
              icon: Icons.download_outlined,
              text: 'Экспорт статистики',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Покупки появятся в следующей версии'),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Оформить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(child: Text(text)),
        ],
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
