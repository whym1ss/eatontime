import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/constants/app_constants.dart';
import '../../core/themes/app_theme.dart';
import '../../core/themes/colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/product_labels.dart';
import '../../data/models/product.dart';

/// Карточка продукта с быстрым считыванием категории, срока и места хранения.
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onConsumed,
    this.onWasted,
    this.animationIndex = 0,
  });

  final Product product;
  final VoidCallback? onTap;
  final VoidCallback? onConsumed;
  final VoidCallback? onWasted;
  final int animationIndex;

  @override
  Widget build(BuildContext context) {
    final status = product.effectiveStatus;
    final statusColor = AppTheme.statusColor(status);
    final categoryColor = AppTheme.categoryColor(product.category);
    final theme = Theme.of(context);

    final card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.13 : 0.045,
            ),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ProductAvatar(
                  color: categoryColor,
                  icon: AppTheme.categoryIcon(product.category),
                  heroTag: 'product-avatar-${product.id}',
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                product.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  decoration: product.isArchived
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusPill(
                            days: product.daysLeft,
                            status: status,
                            color: statusColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 7,
                        runSpacing: 4,
                        children: [
                          _Meta(
                            icon: AppTheme.zoneIcon(product.zoneId),
                            text: AppTheme.zoneLabel(product.zoneId),
                            color: AppTheme.zoneColor(product.zoneId),
                          ),
                          _Meta(
                            icon: Icons.event_outlined,
                            text:
                                'до ${AppDateUtils.shortDate(product.expiryDate)}',
                          ),
                          if (product.quantity > 1 || product.unit != 'pcs')
                            _Meta(
                              icon: Icons.inventory_2_outlined,
                              text:
                                  '${product.quantity} ${ProductLabels.unit(product.unit)}',
                            ),
                        ],
                      ),
                      if (!product.isArchived) ...[
                        const SizedBox(height: 11),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: product.lifeProgress),
                          duration: AppTheme.motionSlow,
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) => ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: value,
                              minHeight: 4,
                              backgroundColor:
                                  statusColor.withValues(alpha: 0.12),
                              valueColor: AlwaysStoppedAnimation(statusColor),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final interactive = onConsumed == null && onWasted == null
        ? card
        : Dismissible(
            key: ValueKey(product.id),
            background: const _SwipeBackground(
              color: AppColors.success,
              icon: Icons.restaurant_rounded,
              label: 'Съедено',
              alignment: Alignment.centerLeft,
            ),
            secondaryBackground: const _SwipeBackground(
              color: AppColors.error,
              icon: Icons.delete_outline_rounded,
              label: 'Выброшено',
              alignment: Alignment.centerRight,
            ),
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.startToEnd) {
                onConsumed?.call();
              } else {
                onWasted?.call();
              }
              return false;
            },
            child: card,
          );

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) return interactive;

    return interactive
        .animate(
          key: ValueKey('product-motion-${product.id}'),
          delay: Duration(milliseconds: (animationIndex.clamp(0, 5)) * 32),
        )
        .fadeIn(duration: AppTheme.motionMedium, curve: Curves.easeOutCubic)
        .slideY(
          begin: 0.055,
          end: 0,
          duration: AppTheme.motionMedium,
          curve: Curves.easeOutCubic,
        );
  }
}

class _ProductAvatar extends StatelessWidget {
  const _ProductAvatar({
    required this.color,
    required this.icon,
    required this.heroTag,
  });

  final Color color;
  final IconData icon;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: heroTag,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: color, size: 25),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.days,
    required this.status,
    required this.color,
  });

  final int days;
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = switch (status) {
      AppConstants.statusConsumed => 'съедено',
      AppConstants.statusWasted => 'выброшено',
      _ => AppDateUtils.daysRemaining(days),
    };

    return AnimatedContainer(
      duration: AppTheme.motionFast,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppTheme.statusIcon(status), size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color ?? muted),
        const SizedBox(width: 3),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: muted,
                fontSize: 11.5,
              ),
        ),
      ],
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.icon,
    required this.label,
    required this.alignment,
  });

  final Color color;
  final IconData icon;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 21),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
