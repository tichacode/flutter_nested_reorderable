// -----------------------------------------------------------------------
// edit_tree.dart
//
// Editable recursive tree used by PackDetailPage while in "edit mode".
//
// Two render modes, chosen by whether a MoveSession is active:
//   - normal mode (moveSession == null): each row shows a kebab menu
//     ("Move to" / "Delete"), plus an "Add new" tile at the end of
//     every level.
//   - move mode   (moveSession != null): the node being moved (and
//     everything inside it) is greyed out and non-interactive. Every
//     OTHER valid position in the whole Pack - at every nesting level -
//     renders as a tappable "Move here" slot. Kebabs and "Add new"
//     tiles are hidden everywhere while a move is in progress, since
//     picking a destination (or cancelling) is the only thing to do.
//
// -----------------------------------------------------------------------

import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/item_node.dart';
import '../models/format_item.dart';
import 'view_tree.dart';
import 'move_feature.dart';

// Renders one level of the tree
// editable rows (with kebab menus) or as "Move here" slots, depending on moveSession
// Call this with the Pack itself as parent (depth: 0) to draw the whole editable tree.
class EditableLevel extends StatelessWidget {
  final ItemNode parent;
  final int depth; // Depth of parent itself (0 for the Pack, 1-4 for a Nest).
  final MoveSession? moveSession;
  final void Function(ItemNode parent, int depth) onAddChild;
  final void Function(ItemNode node) onKebabTap;
  final void Function(int parentId, int index) onSelectSlot;

  const EditableLevel({
    super.key,
    required this.parent,
    required this.depth,
    required this.moveSession,
    required this.onAddChild,
    required this.onKebabTap,
    required this.onSelectSlot,
  });

  @override
  Widget build(BuildContext context) {
    final session = moveSession;
    if (session == null) return _buildNormal();

    final offLimits = session.excludedIds.contains(parent.id) ||
        (session.node.type == ItemType.nested &&
            depth + session.nestSpan > kMaxNestDepth);

    if (offLimits) {
      // Nothing under here can ever be a legal destination. Just show it read-only and dimmed
      return Opacity(
        opacity: 0.45,
        child: IgnorePointer(child: PackTreeView(node: parent)),
      );
    }

    return _buildMoveSlots(session);
  }

  Widget _buildNormal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in parent.children) ...[
          _NormalRow(
            node: child,
            depth: depth,
            onAddChild: onAddChild,
            onKebabTap: onKebabTap,
            onSelectSlot: onSelectSlot,
          ),
          const SizedBox(height: 12),
        ],
        _AddNewTile(onTap: () => onAddChild(parent, depth)),
      ],
    );
  }

  Widget _buildMoveSlots(MoveSession session) {
    final rows = <Widget>[];
    var reducedIndex = 0;

    rows.add(_slot(session, reducedIndex));
    for (final child in parent.children) {
      if (session.excludedIds.contains(child.id)) {
        // in its original spot, but don't count it toward slot indices.
        rows.add(
          Opacity(
            opacity: 0.45,
            child: IgnorePointer(
              child: child.type == ItemType.item
                  ? LeafBox(name: child.name)
                  : NestedBox(
                      name: child.name,
                      child: PackTreeView(node: child),
                    ),
            ),
          ),
        );
      } else {
        rows.add(
          child.type == ItemType.item
              ? LeafBox(name: child.name)
              : NestedBox(
                  name: child.name,
                  child: EditableLevel(
                    parent: child,
                    depth: depth + 1,
                    moveSession: session,
                    onAddChild: onAddChild,
                    onKebabTap: onKebabTap,
                    onSelectSlot: onSelectSlot,
                  ),
                ),
        );
        reducedIndex += 1;
        rows.add(_slot(session, reducedIndex));
      }
      rows.add(const SizedBox(height: 12));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _slot(MoveSession session, int index) {
    if (session.isNoOp(parent.id, index)) return const SizedBox.shrink();
    return _MoveSlotTile(
      selected: session.isPending(parent.id, index),
      onTap: () => onSelectSlot(parent.id, index),
    );
  }
}

// edit mode: name + kebab menu
class _NormalRow extends StatelessWidget {
  final ItemNode node;
  final int depth; // depth of the container this row lives IN
  final void Function(ItemNode parent, int depth) onAddChild;
  final void Function(ItemNode node) onKebabTap;
  final void Function(int parentId, int index) onSelectSlot;

  const _NormalRow({
    required this.node,
    required this.depth,
    required this.onAddChild,
    required this.onKebabTap,
    required this.onSelectSlot,
  });

  @override
  Widget build(BuildContext context) {
    if (node.type == ItemType.item) {
      return LeafBox(
        name: node.name, 
        addWidget: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Options',
            onPressed: () => onKebabTap(node),
          )
        ],);
    }

    return NestedBox(
      name: node.name, 
      addWidget: [
        IconButton(
          icon: const Icon(Icons.more_vert),
          tooltip: 'Options',
          onPressed: () => onKebabTap(node),
        )
      ],
      child: EditableLevel(
        parent: node,
        depth: depth + 1,
        moveSession: null,
        onAddChild: onAddChild,
        onKebabTap: onKebabTap,
        onSelectSlot: onSelectSlot,
      ),
    );
  }
}

// A tappable "Move here" placeholder row. Turns green once selected as the pending destination.
class _MoveSlotTile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _MoveSlotTile({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        SizedBox(height: 10,),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: selected ? Colors.green.shade300 : null,
              border: Border.all(
                color: selected ? Colors.green.shade700 : primary.withOpacity(0.4),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              'Move here',
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Colors.black : Colors.grey.shade600,
              ),
            ),
          ),
        ),
        SizedBox(height: 10,),
      ]
    );
  }
}

class _AddNewTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AddNewTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text('Add new', style: TextStyle(color: Colors.grey.shade600)),
      ),
    );
  }
}
