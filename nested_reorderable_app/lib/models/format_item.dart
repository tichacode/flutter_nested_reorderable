// -----------------------------------------------------------------------
// format_item.dart
//
// Keep reusable format in one place
// -----------------------------------------------------------------------

import 'package:flutter/material.dart';

final iconNest = Image.asset("icon_in_app/icon_nest.png", color: Colors.grey.shade600, height: 30,);
final iconLeaf = Image.asset("icon_in_app/icon_leaf.png", color: Colors.grey.shade600, height: 30,);


/// A "Nest" row: rounded outline, title on top, children indented inside.
class NestedBox extends StatelessWidget {
  final String name;
  final Widget child;
  final List<Widget>? addWidget;


  const NestedBox({required this.name, required this.child, this.addWidget});

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.primary;
    List<Widget> widgetItems = [
      iconNest,
      const SizedBox(width: 10,),
      Expanded(
        child: Text(
          name,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        )
      ),
    ];

    if (addWidget != null) {
      widgetItems.addAll(addWidget ?? []);
    }

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
            children: widgetItems
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// A leaf "Item" row: simple flat bordered box, no children.
class LeafBox extends StatelessWidget {
  final String name;
  final List<Widget>? addWidget;

  const LeafBox({required this.name, this.addWidget});

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.primary;
    List<Widget> widgetItems = [
      iconLeaf,
      const SizedBox(width: 10,),
      Expanded(
        child: Text(
          name,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        )
      ),
    ];

    if (addWidget != null) {
      widgetItems.addAll(addWidget ?? []);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: widgetItems
      )
    );
  }
}