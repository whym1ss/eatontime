import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/themes/app_theme.dart';
import '../../data/models/product.dart';
import '../../providers/core_providers.dart';
import '../../providers/product_providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/home_skeleton.dart';
import '../widgets/product_card.dart';
import '../widgets/summary_card.dart';
import '../widgets/zone_filter_bar.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ref.read(productRepositoryProvider).sync());
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await ref.read(productRepositoryProvider).sync();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        ref.read(searchQueryProvider.notifier).state = '';
      }
    });
  }

  void _showAttention() {
    ref.read(selectedZoneProvider.notifier).state = null;
    ref.read(sortModeProvider.notifier).state = ProductSort.expiry;
    if (!_scrollController.hasClients) return;
    final target =
        235.0.clamp(0.0, _scrollController.position.maxScrollExtent).toDouble();
    _scrollController.animateTo(
      target,
      duration: AppTheme.motionSlow,
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _consume(Product product) async {
    await ref.read(productRepositoryProvider).markConsumed(product);
    if (!mounted) return;
    _showUndo('«${product.name}» съеден', product);
  }

  Future<void> _waste(Product product) async {
    await ref.read(productRepositoryProvider).markWasted(product);
    if (!mounted) return;
    _showUndo('«${product.name}» выброшен', product);
  }

  void _showUndo(String message, Product product) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
          action: SnackBarAction(
            label: 'Отменить',
            onPressed: () =>
                ref.read(productRepositoryProvider).restore(product),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final asyncProducts = ref.watch(activeProductsProvider);
    final grouped = ref.watch(groupedProductsProvider);
    final summary = ref.watch(homeSummaryProvider);
    final zones = ref.watch(zoneCountsProvider);
    final selectedZone = ref.watch(selectedZoneProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 74,
        titleSpacing: 16,
        title: AnimatedSwitcher(
          duration: AppTheme.motionFast,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _searching
              ? TextField(
                  key: const ValueKey('search'),
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Найти продукт…',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (value) =>
                      ref.read(searchQueryProvider.notifier).state = value,
                )
              : Column(
                  key: const ValueKey('title'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EAT ON TIME',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Мои продукты',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
        ),
        actions: [
          IconButton(
            tooltip: _searching ? 'Закрыть поиск' : 'Поиск',
            icon: AnimatedSwitcher(
              duration: AppTheme.motionFast,
              child: Icon(
                _searching ? Icons.close_rounded : Icons.search_rounded,
                key: ValueKey(_searching),
              ),
            ),
            onPressed: _toggleSearch,
          ),
          const SizedBox(width: 4),
          PopupMenuButton<ProductSort>(
            tooltip: 'Сортировка',
            icon: const Icon(Icons.tune_rounded),
            onSelected: (value) =>
                ref.read(sortModeProvider.notifier).state = value,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: ProductSort.expiry,
                child: Text('Сначала срочные'),
              ),
              PopupMenuItem(
                value: ProductSort.name,
                child: Text('По названию'),
              ),
              PopupMenuItem(
                value: ProductSort.added,
                child: Text('Сначала новые'),
              ),
              PopupMenuItem(
                value: ProductSort.zone,
                child: Text('По месту хранения'),
              ),
            ],
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: asyncProducts.when(
        loading: () => const HomeSkeleton(),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Не удалось загрузить продукты',
          message: '$error',
          actionLabel: 'Повторить',
          onAction: _refresh,
        ),
        data: (all) {
          if (all.isEmpty) {
            return const EmptyState(
              icon: Icons.kitchen_outlined,
              title: 'Холодильник ждёт продукты',
              message:
                  'Нажмите «Добавить» — подскажем, что съесть раньше, и вовремя напомним.',
            );
          }

          final attentionProducts = all
              .where((product) =>
                  product.freshnessStatus != AppConstants.statusFresh)
              .toList()
            ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

          return RefreshIndicator(
            onRefresh: _refresh,
            edgeOffset: 8,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SummaryCard(
                      summary: summary,
                      attentionProducts: attentionProducts,
                      onShowAttention: _showAttention,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 3),
                    child: ZoneFilterBar(
                      zones: const [
                        AppConstants.zoneFridge,
                        AppConstants.zoneFreezer,
                        AppConstants.zonePantry,
                      ],
                      counts: zones,
                      selected: selectedZone,
                      onSelect: (zone) =>
                          ref.read(selectedZoneProvider.notifier).state = zone,
                    ),
                  ),
                ),
                if (grouped.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: query.isEmpty
                          ? Icons.inventory_2_outlined
                          : Icons.search_off_rounded,
                      title: query.isEmpty
                          ? 'Здесь пока пусто'
                          : 'Ничего не найдено',
                      message: query.isEmpty
                          ? 'Выберите другое место хранения.'
                          : 'Попробуйте изменить запрос.',
                    ),
                  )
                else
                  for (final entry in grouped.entries) ...[
                    SliverToBoxAdapter(
                      child: _SectionHeader(
                        status: entry.key,
                        count: entry.value.length,
                      ),
                    ),
                    SliverList.builder(
                      itemCount: entry.value.length,
                      itemBuilder: (context, index) {
                        final product = entry.value[index];
                        return ProductCard(
                          product: product,
                          animationIndex: index,
                          onTap: () => context.push('/product/${product.id}'),
                          onConsumed: () => _consume(product),
                          onWasted: () => _waste(product),
                        );
                      },
                    ),
                  ],
                const SliverToBoxAdapter(child: SizedBox(height: 112)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.status, required this.count});

  final String status;
  final int count;

  static const _titles = {
    AppConstants.statusExpired: 'Просрочено',
    AppConstants.statusCritical: 'Съесть срочно',
    AppConstants.statusExpiringSoon: 'Скоро испортится',
    AppConstants.statusFresh: 'Свежие',
  };

  static const _subtitles = {
    AppConstants.statusExpired: 'Проверьте перед использованием',
    AppConstants.statusCritical: 'Лучше использовать сегодня',
    AppConstants.statusExpiringSoon: 'Запланируйте на ближайшие дни',
    AppConstants.statusFresh: 'Можно не торопиться',
  };

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.statusColor(status);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 7),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(AppTheme.statusIcon(status), color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _titles[status] ?? status,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '$count',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitles[status] ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
