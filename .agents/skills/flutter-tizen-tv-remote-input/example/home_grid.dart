// home_grid.dart
// 4x3 grid wrapped in a FocusTraversalGroup so the D-pad walks tiles
// in reading order. The first tile autofocuses on screen entry.

import 'package:flutter/material.dart';

import 'remote_button.dart';

class HomeGrid extends StatelessWidget {
  const HomeGrid({
    super.key,
    required this.items,
    required this.onTileSelected,
  });

  final List<String> items; // 12 entries
  final ValueChanged<int> onTileSelected;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: GridView.builder(
        padding: const EdgeInsets.all(24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 16 / 9,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) {
          return FocusTraversalOrder(
            order: NumericFocusOrder(i.toDouble()),
            child: RemoteButton(
              autofocus: i == 0,
              label: items[i],
              onPressed: () => onTileSelected(i),
            ),
          );
        },
      ),
    );
  }
}
