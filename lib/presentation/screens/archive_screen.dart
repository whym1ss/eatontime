import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/date_utils.dart';
import '../../providers/core_providers.dart';
import '../../providers/product_providers.dart';
import '../widgets/empty_state.dart';
import 'product_detail_screen.dart';

/// История: съеденное и выброшенное.
class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = ref.watch(archivedProductsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Архив')),
      body: archived.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.history,
              title: 'Архив пуст',
              message: 'Здесь появятся съеденные и выброшенные продукты.',
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
            itemBuilder: (context, i) {
              final p = items[i];
              final consumed = p.status == AppConstants.statusConsumed;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: (consumed ? Colors.green : Colors.red)
                      .withValues(alpha: 0.14),
                  child: Icon(
                    consumed ? Icons.restaurant : Icons.delete_outline,
                    color: consumed ? Colors.green : Colors.red,
                    size: 20,
                  ),
                ),
                title: Text(p.name),
                subtitle: Text(
                  '${consumed ? 'Съедено' : 'Выброшено'} · '
                  '${AppDateUtils.daysSince(p.consumedAt ?? p.updatedAt)}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.undo),
                  tooltip: 'Вернуть',
                  onPressed: () =>
                      ref.read(productRepositoryProvider).restore(p),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProductDetailScreen(productId: p.id),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
