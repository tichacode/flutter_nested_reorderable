// -----------------------------------------------------------------------
// view_tree.dart
//
// Read-only tree renderer produces the box-inside-a-box look from the wireframe.
// -----------------------------------------------------------------------

import 'package:flutter/material.dart';
import '../models/item_node.dart';
import '../models/format_item.dart';

/// Renders the children of [node] (a Pack or a Nest) read-only.
/// Call this with the Pack itself as [node] to draw everything under it.
class PackTreeView extends StatelessWidget {
  final ItemNode node;

  const PackTreeView({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    // show when nothing inside nest
    if (node.children.isEmpty) {
      final primary = Theme.of(context).colorScheme.primary;
      return 
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: null,
          border: Border.all(
            color: primary.withOpacity(0.4),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          'Nothing is here',
          style: TextStyle(
            fontWeight: FontWeight.normal,
            color: Colors.grey.shade600,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in node.children) ...[
          _buildRow(context, child),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildRow(BuildContext context, ItemNode child) {
    switch (child.type) {
      case ItemType.none:
        return SizedBox(height: 0,);

      case ItemType.item:
        return LeafBox(name: child.name);

      case ItemType.nested:
      case ItemType.pack:
        return NestedBox(
          name: child.name,
          child: PackTreeView(node: child),
        );
    }
  }
}
