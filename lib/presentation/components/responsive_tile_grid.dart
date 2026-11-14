import 'package:flutter/material.dart';

import '../design_system/app_tokens.dart';

/// Lays out tiles in as many columns as fit (1 on narrow phones, up to
/// [maxColumns] on tablets) with 8dp gutters.
class ResponsiveTileGrid extends StatelessWidget {
  const ResponsiveTileGrid({
    super.key,
    required this.children,
    this.minTileWidth = 160,
    this.maxColumns = 4,
  });

  final List<Widget> children;
  final double minTileWidth;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final available = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : minTileWidth;
      var columns = (available / minTileWidth).floor();
      if (columns < 1) columns = 1;
      if (columns > maxColumns) columns = maxColumns;
      final tileWidth =
          (available - AppSpacing.sm * (columns - 1)) / columns;
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final child in children)
            SizedBox(width: tileWidth, child: child),
        ],
      );
    },
  );
}
