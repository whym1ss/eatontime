import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/themes/app_theme.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/product_labels.dart';
import '../../core/utils/product_matcher.dart';
import '../../data/models/product.dart';
import '../../providers/core_providers.dart';
import '../../providers/product_providers.dart';
import 'add_product_screen.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productByIdProvider(productId));

    if (product == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Продукт не найден')),
      );
    }

    final status = product.effectiveStatus;
    final color = AppTheme.statusColor(status);

    return Scaffold(
      appBar: AppBar(
        title: Text(product.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AddProductScreen(editing: product),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref, product),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Text(
                    AppDateUtils.daysRemaining(product.daysLeft),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'годен до ${AppDateUtils.fullDate(product.expiryDate)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: product.lifeProgress,
                      minHeight: 8,
                      backgroundColor: color.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _InfoTile(
            icon: AppTheme.zoneIcon(product.zoneId),
            iconColor: AppTheme.zoneColor(product.zoneId),
            label: 'Зона хранения',
            value: AppTheme.zoneLabel(product.zoneId),
          ),
          if (product.brand != null)
            _InfoTile(
              icon: Icons.storefront_outlined,
              label: 'Бренд',
              value: product.brand!,
            ),
          if (product.category != null)
            _InfoTile(
              icon: Icons.category_outlined,
              label: 'Категория',
              value: ProductLabels.category(product.category!),
            ),
          _InfoTile(
            icon: Icons.numbers,
            label: 'Количество',
            value: '${product.quantity} ${ProductLabels.unit(product.unit)}',
          ),
          if (product.price != null)
            _InfoTile(
              icon: Icons.payments_outlined,
              label: 'Цена',
              value: '${product.price!.toStringAsFixed(2)} ₽',
            ),
          if (product.purchaseDate != null)
            _InfoTile(
              icon: Icons.shopping_basket_outlined,
              label: 'Куплено',
              value: AppDateUtils.daysSince(product.purchaseDate!),
            ),
          if (product.openedDate != null)
            _InfoTile(
              icon: Icons.inventory_2_outlined,
              label: 'Вскрыто',
              value: AppDateUtils.daysSince(product.openedDate!),
            ),
          if (product.barcode != null)
            _InfoTile(
              icon: Icons.qr_code_2,
              label: 'Штрихкод',
              value: product.barcode!,
            ),
          _InfoTile(
            icon: Icons.add_circle_outline,
            label: 'Добавлено',
            value: ProductLabels.addMethod(product.addMethod),
          ),
          if (product.note != null && product.note!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Заметка',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 6),
                    Text(product.note!),
                  ],
                ),
              ),
            ),
          ],
          if (!product.isArchived && product.openedDate == null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _markOpened(context, ref, product),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('Открыл сегодня'),
            ),
          ],
          if (!product.isArchived && product.category != null) ...[
            const SizedBox(height: 16),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Что можно сделать',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    for (final tip in ProductMatcher.smartTips(
                      product.category!,
                      zoneId: product.zoneId,
                      daysLeft: product.daysLeft,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text('• $tip'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: product.isArchived
              ? OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(productRepositoryProvider).restore(product);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.undo),
                  label: const Text('Вернуть в список'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await ref
                              .read(productRepositoryProvider)
                              .markWasted(product);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Выбросил'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          await ref
                              .read(productRepositoryProvider)
                              .markConsumed(product);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.restaurant),
                        label: const Text('Съел'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить продукт?'),
        content:
            Text('«${product.name}» будет удалён без записи в статистику.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(productRepositoryProvider).delete(product);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _markOpened(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) async {
    final days =
        ProductMatcher.estimateAfterOpening(product.category ?? 'other');
    final now = DateTime.now();
    final afterOpening = now.add(Duration(days: days));
    final expiry = afterOpening.isBefore(product.expiryDate)
        ? afterOpening
        : product.expiryDate;
    await ref.read(productRepositoryProvider).update(
          product.copyWith(openedDate: now, expiryDate: expiry),
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Запущен срок после вскрытия: $days дн.')),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor ?? Theme.of(context).hintColor),
          const SizedBox(width: 14),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
