import 'package:flutter/material.dart';

import '../../core/themes/app_theme.dart';

/// Горизонтальный ряд анимированных фильтров по месту хранения.
class ZoneFilterBar extends StatelessWidget {
  const ZoneFilterBar({
    super.key,
    required this.zones,
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final List<String> zones;
  final Map<String, int> counts;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold<int>(0, (a, b) => a + b);

    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        children: [
          _ZoneChip(
            label: 'Все',
            count: total,
            active: selected == null,
            color: Theme.of(context).colorScheme.primary,
            icon: Icons.grid_view_rounded,
            onTap: () => onSelect(null),
          ),
          for (final zone in zones)
            _ZoneChip(
              label: AppTheme.zoneLabel(zone),
              count: counts[zone] ?? 0,
              active: selected == zone,
              color: AppTheme.zoneColor(zone),
              icon: AppTheme.zoneIcon(zone),
              onTap: () => onSelect(selected == zone ? null : zone),
            ),
        ],
      ),
    );
  }
}

class _ZoneChip extends StatelessWidget {
  const _ZoneChip({
    required this.label,
    required this.count,
    required this.active,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = active ? color : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: active,
      label: '$label, $count',
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: AnimatedContainer(
              duration: AppTheme.motionFast,
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
              decoration: BoxDecoration(
                color: active ? color.withValues(alpha: 0.13) : scheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: active
                      ? color.withValues(alpha: 0.45)
                      : scheme.outlineVariant,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: foreground),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 7),
                    AnimatedContainer(
                      duration: AppTheme.motionFast,
                      constraints: const BoxConstraints(minWidth: 24),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? color.withValues(alpha: 0.16)
                            : scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$count',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
