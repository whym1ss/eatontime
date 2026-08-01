import 'package:flutter/material.dart';

import '../../core/themes/app_theme.dart';
import '../../core/themes/colors.dart';
import '../../data/models/product.dart';
import '../../providers/product_providers.dart';

/// Главный блок «Сегодня»: один понятный следующий шаг вместо четырёх
/// равнозначных счётчиков.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.summary,
    required this.attentionProducts,
    this.onShowAttention,
  });

  final HomeSummary summary;
  final List<Product> attentionProducts;
  final VoidCallback? onShowAttention;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final needsAttention = summary.needsAttention > 0;
    final freshness = summary.total == 0 ? 1.0 : summary.fresh / summary.total;
    final names = attentionProducts.take(2).map((p) => p.name).toList();

    final title =
        needsAttention ? 'Съесть в первую очередь' : 'Всё под контролем';
    final description = switch (names.length) {
      0 => 'Все продукты свежие. Отличная работа!',
      1 => names.first,
      _ => '${names.first} и ${names[1]}',
    };

    final foreground = dark ? const Color(0xFFEAF7EC) : Colors.white;
    final muted = foreground.withValues(alpha: 0.78);

    return Semantics(
      container: true,
      label: '$title. $description',
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xFF1E5730), Color(0xFF173C27)]
                : const [Color(0xFF236B3A), Color(0xFF3F8B50)],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: dark ? 0.18 : 0.22),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            const Positioned(
              right: -42,
              top: -52,
              child: _GlowOrb(size: 150, opacity: 0.10),
            ),
            const Positioned(
              right: 72,
              bottom: -58,
              child: _GlowOrb(size: 126, opacity: 0.07),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  needsAttention
                                      ? Icons.wb_sunny_outlined
                                      : Icons.check_circle_outline,
                                  size: 17,
                                  color: AppColors.lime,
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  'СЕГОДНЯ',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: AppColors.lime,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: foreground,
                                fontSize: 23,
                                height: 1.08,
                              ),
                            ),
                            const SizedBox(height: 7),
                            AnimatedSwitcher(
                              duration: AppTheme.motionMedium,
                              child: Text(
                                description,
                                key: ValueKey(description),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: muted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      _FreshnessRing(
                        value: freshness,
                        foreground: foreground,
                        track: foreground.withValues(alpha: 0.16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      if (needsAttention)
                        FilledButton.icon(
                          onPressed: onShowAttention,
                          icon: const Icon(Icons.arrow_downward_rounded,
                              size: 18),
                          label: Text('Показать ${summary.needsAttention}'),
                          style: FilledButton.styleFrom(
                            foregroundColor: AppColors.primaryDark,
                            backgroundColor: Colors.white,
                            minimumSize: const Size(0, 44),
                          ),
                        )
                      else
                        _MiniFact(
                          icon: Icons.eco_outlined,
                          text: '${summary.fresh} свежих',
                          color: foreground,
                        ),
                      const Spacer(),
                      _MiniFact(
                        icon: Icons.inventory_2_outlined,
                        text: 'Всего ${summary.total}',
                        color: muted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FreshnessRing extends StatelessWidget {
  const _FreshnessRing({
    required this.value,
    required this.foreground,
    required this.track,
  });

  final double value;
  final Color foreground;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1)),
      duration: AppTheme.motionSlow,
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return SizedBox(
          width: 78,
          height: 78,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: animatedValue,
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  color: AppColors.lime,
                  backgroundColor: track,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(animatedValue * 100).round()}%',
                    style: TextStyle(
                      color: foreground,
                      fontSize: 18,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'свежо',
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.7),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniFact extends StatelessWidget {
  const _MiniFact(
      {required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: opacity),
        ),
      ),
    );
  }
}
