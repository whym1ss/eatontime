import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/themes/app_theme.dart';

/// Единое спокойное состояние для пустого списка, ошибки и отсутствия данных.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final content = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 112,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: 4,
                    top: 8,
                    child: _Blob(
                      size: 54,
                      color: scheme.secondaryContainer,
                    ),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 4,
                    child: _Blob(
                      size: 62,
                      color: scheme.primaryContainer,
                    ),
                  ),
                  Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.outlineVariant),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 22,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(icon, size: 36, color: scheme.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 20,
                  ),
            ),
            if (message != null) ...[
              const SizedBox(height: 9),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 330),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );

    if (MediaQuery.disableAnimationsOf(context)) return content;
    return content.animate().fadeIn(duration: AppTheme.motionMedium).slideY(
          begin: 0.035,
          end: 0,
          duration: AppTheme.motionSlow,
          curve: Curves.easeOutCubic,
        );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Transform.rotate(
        angle: 0.35,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(size * 0.36),
          ),
        ),
      ),
    );
  }
}
