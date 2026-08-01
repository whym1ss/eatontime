import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/themes/app_theme.dart';

/// Каркас приложения с нижней навигацией и выразительным быстрым добавлением.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.kitchen_outlined),
      selectedIcon: Icon(Icons.kitchen_rounded),
      label: 'Продукты',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights_rounded),
      label: 'Статистика',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings_rounded),
      label: 'Настройки',
    ),
  ];

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final onHome = navigationShell.currentIndex == 0;

    return Scaffold(
      body: navigationShell,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: onHome
          ? FloatingActionButton.extended(
              heroTag: 'main-add-button',
              onPressed: () => _showAddSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить'),
            ).animate().fadeIn(duration: AppTheme.motionMedium).scale(
                begin: const Offset(0.88, 0.88),
                end: const Offset(1, 1),
                duration: AppTheme.motionMedium,
                curve: Curves.easeOutBack,
              )
          : null,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _goBranch,
          destinations: _destinations,
        ),
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    const methods = [
      _AddMethod(
        icon: Icons.edit_note_rounded,
        title: 'Вручную',
        subtitle: 'Название и срок',
        color: Color(0xFF4D8B5A),
        route: '/add',
      ),
      _AddMethod(
        icon: Icons.qr_code_scanner_rounded,
        title: 'Штрихкод',
        subtitle: 'Найдём продукт',
        color: Color(0xFF4B8FB6),
        route: '/scan',
      ),
      _AddMethod(
        icon: Icons.receipt_long_rounded,
        title: 'Чек',
        subtitle: 'Сразу все покупки',
        color: Color(0xFFE08C3D),
        route: '/scan/receipt',
      ),
      _AddMethod(
        icon: Icons.graphic_eq_rounded,
        title: 'Голосом',
        subtitle: 'Скажите одной фразой',
        color: Color(0xFF856BC0),
        route: '/add/voice',
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Как добавим?',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Выберите самый удобный способ',
              style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: methods.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.12,
              ),
              itemBuilder: (context, index) {
                final method = methods[index];
                final tile = _AddMethodTile(
                  method: method,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.push(method.route);
                  },
                );

                if (MediaQuery.disableAnimationsOf(context)) return tile;
                return tile
                    .animate(delay: Duration(milliseconds: index * 55))
                    .fadeIn(
                      duration: AppTheme.motionMedium,
                      curve: Curves.easeOutCubic,
                    )
                    .scale(
                      begin: const Offset(0.94, 0.94),
                      end: const Offset(1, 1),
                      duration: AppTheme.motionMedium,
                      curve: Curves.easeOutCubic,
                    );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AddMethod {
  const _AddMethod({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String route;
}

class _AddMethodTile extends StatelessWidget {
  const _AddMethodTile({required this.method, required this.onTap});

  final _AddMethod method;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: method.color.withValues(alpha: 0.11),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        side: BorderSide(color: method.color.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: method.color.withValues(alpha: 0.17),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(method.icon, color: method.color, size: 24),
              ),
              const Spacer(),
              Text(method.title,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                method.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
