import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/themes/app_theme.dart';

/// Загрузка повторяет геометрию главной и не заставляет контент «прыгать».
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return ExcludeSemantics(
      child: Shimmer.fromColors(
        baseColor:
            dark ? scheme.surfaceContainerHigh : scheme.surfaceContainerLow,
        highlightColor: dark ? scheme.surfaceContainerHighest : scheme.surface,
        period: const Duration(milliseconds: 1250),
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            const _SkeletonBox(height: 205, radius: AppTheme.radiusLarge),
            const SizedBox(height: 18),
            Row(
              children: [
                for (final width in const [72.0, 118.0, 104.0]) ...[
                  _SkeletonBox(width: width, height: 42, radius: 22),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 24),
            const _SkeletonBox(width: 148, height: 18, radius: 8),
            const SizedBox(height: 12),
            for (var i = 0; i < 4; i++) ...[
              const _SkeletonBox(height: 98, radius: AppTheme.radiusMedium),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    this.width = double.infinity,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
