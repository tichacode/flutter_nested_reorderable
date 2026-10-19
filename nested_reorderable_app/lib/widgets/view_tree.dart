// -----------------------------------------------------------------------
// view_tree.dart
//
// Read-only tree renderer used by PackDetailPage when NOT editing.
// This is a straight recursive widget: every "nested" row draws a
// rounded box around its own children (which may again contain nested
// boxes), and every "item" row draws a simple flat box. That recursion
// is exactly what produces the box-inside-a-box look from the wireframe.
// -----------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../models/item_node.dart';

/// Renders the children of [node] (a Pack or a Nest) read-only.
/// Call this with the Pack itself as [node] to draw everything under it.
class PackTreeView extends StatelessWidget {
  final ItemNode node;

  const PackTreeView({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    if (node.children.isEmpty) {
      final primary = Theme.of(context).colorScheme.primary;
      return 
      // const SizedBox.shrink();
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
        return _LeafBox(name: child.name);
      case ItemType.nested:
      case ItemType.pack:
        return _NestedBox(
          name: child.name,
          child: PackTreeView(node: child),
        );
    }
  }
}

/// A "Nest" row: rounded outline, title on top, children indented inside.
class _NestedBox extends StatelessWidget {
  final String name;
  final Widget child;

  const _NestedBox({required this.name, required this.child});

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset("icon_in_app/icon_nest.png", color: Colors.grey.shade600, height: 30,),
              const SizedBox(width: 10,),
              Text(
                name,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ]
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// A leaf "Item" row: simple flat bordered box, no children.
class _LeafBox extends StatelessWidget {
  final String name;

  const _LeafBox({required this.name});

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Image.asset("icon_in_app/icon_leaf.png", color: Colors.grey.shade600, height: 30,),
          const SizedBox(width: 10,),
          Text(
            name,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ]
      )
    );
  }
}
