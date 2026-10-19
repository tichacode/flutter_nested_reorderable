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
// This replaces the earlier drag-and-drop version of this file.
// Repositioning (same level OR a different level) now all goes through
// the same "Move to" flow, so there's no ReorderableListView here
// anymore at all.
//
// Nothing in this file talks to the database. Every action (tap a
// kebab, tap "Add new", tap a "Move here" slot) calls back up to
// PackDetailPage, which owns the one in-memory copy of the whole Pack
// tree and is the only place that calls DatabaseHelper. That's a
// deliberate change from the drag-based version, where each level kept
// its own local list - once a move can land anywhere in the tree (not
// just among same-level siblings), the state needs one single owner.
// -----------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/item_node.dart';
import 'view_tree.dart';

// ---------------------------------------------------------------------
// Move session + tree-walking helpers
// ---------------------------------------------------------------------

/// Just a (parent, index) pair - the result of [findParentAndIndex].
class ParentIndex {
  final ItemNode parent;
  final int index;
  ParentIndex(this.parent, this.index);
}

/// Tracks an in-progress "Move to" session for one node.
///
/// Created when the user taps "Move to" on a row's kebab menu, cleared
/// when they confirm (checkmark) or cancel (X). Lives in
/// PackDetailPage's state - picking a "Move here" slot only updates
/// [pendingParentId] / [pendingIndex] here; nothing is written to the
/// database until the checkmark is tapped.
class MoveSession {
  final ItemNode node;
  final int originalParentId;
  final int originalIndex;

  /// node's own id, plus every descendant's id - a node can never be
  /// moved into itself or its own subtree.
  final Set<int> excludedIds;

  /// How many nest-levels node's own subtree spans (0 if node is an
  /// Item - items never consume nest-depth "budget").
  final int nestSpan;

  int? pendingParentId;
  int? pendingIndex;

  MoveSession({
    required this.node,
    required this.originalParentId,
    required this.originalIndex,
    required this.excludedIds,
    required this.nestSpan,
  });

  bool get hasPendingDestination =>
      pendingParentId != null && pendingIndex != null;

  bool isPending(int parentId, int index) =>
      pendingParentId == parentId && pendingIndex == index;

  /// The slot that would put the node back exactly where it already
  /// is - not a real move, so it's never offered.
  bool isNoOp(int parentId, int index) =>
      parentId == originalParentId && index == originalIndex;
}

/// node's own id plus every descendant's id.
Set<int> collectSubtreeIds(ItemNode node) {
  final ids = <int>{node.id};
  for (final child in node.children) {
    ids.addAll(collectSubtreeIds(child));
  }
  return ids;
}

/// How many nest-levels deep node's own subtree goes, counting itself
/// if it is a Nest. Items always return 0.
int nestSpanOf(ItemNode node) {
  if (node.type != ItemType.nested) return 0;
  var deepestChild = 0;
  for (final child in node.children) {
    final span = nestSpanOf(child);
    if (span > deepestChild) deepestChild = span;
  }
  return 1 + deepestChild;
}

/// Finds childId's current parent and its index within that parent's
/// children list, searching the whole tree under root.
ParentIndex? findParentAndIndex(ItemNode root, int childId) {
  for (var i = 0; i < root.children.length; i++) {
    if (root.children[i].id == childId) {
      return ParentIndex(root, i);
    }
  }
  for (final child in root.children) {
    final found = findParentAndIndex(child, childId);
    if (found != null) return found;
  }
  return null;
}

/// Finds any node by id, anywhere under root (root included).
ItemNode? findNode(ItemNode root, int id) {
  if (root.id == id) return root;
  for (final child in root.children) {
    final found = findNode(child, id);
    if (found != null) return found;
  }
  return null;
}

// ---------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------

/// Renders one level of the tree: parent's children, either as normal
/// editable rows (with kebab menus) or as "Move here" slots, depending
/// on [moveSession]. Call this with the Pack itself as [parent]
/// (depth: 0) to draw the whole editable tree.
class EditableLevel extends StatelessWidget {
  final ItemNode parent;

  /// Depth of parent itself (0 for the Pack, 1-4 for a Nest).
  final int depth;

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
      // Nothing under here can ever be a legal destination - it's
      // either inside the node being moved, or already deep enough
      // that adding the moved subtree would break the nest-depth
      // limit. Just show it read-only and dimmed, reusing the same
      // recursive renderer the view-mode screen uses.
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
        // The node being moved - render it read-only and dimmed, in
        // its original spot, but don't count it toward slot indices.
        rows.add(
          Opacity(
            opacity: 0.45,
            child: IgnorePointer(
              child: child.type == ItemType.item
                  ? _LeafLabel(name: child.name)
                  : _NestLabelBox(
                      name: child.name,
                      child: PackTreeView(node: child),
                    ),
            ),
          ),
        );
      } else {
        rows.add(
          child.type == ItemType.item
              ? _LeafLabel(name: child.name)
              : _NestLabelBox(
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

/// One row in normal (non-move) edit mode: name + kebab menu, with its
/// own nested EditableLevel underneath if it's a Nest.
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

  Widget _getIcon(ItemType type) {
    if (type == ItemType.item) {
      return Image.asset("icon_in_app/icon_leaf.png", color: Colors.grey.shade600, height: 30,);
    } else if (type == ItemType.nested) {
      return Image.asset("icon_in_app/icon_nest.png", color: Colors.grey.shade600, height: 30,);
    } else {
      return const SizedBox(height: 0,);
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.primary;

    final header = Row(
      children: [
        _getIcon(node.type),
        const SizedBox(width: 10,),
        Expanded(
          child: Text(
            node.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          tooltip: 'Options',
          onPressed: () => onKebabTap(node),
        ),
      ],
    );

    if (node.type == ItemType.item) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: header,
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 12),
          EditableLevel(
            parent: node,
            depth: depth + 1,
            moveSession: null,
            onAddChild: onAddChild,
            onKebabTap: onKebabTap,
            onSelectSlot: onSelectSlot,
          ),
        ],
      ),
    );
  }
}

/// A tappable "Move here" placeholder row. Turns green once selected
/// as the pending destination.
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

/// A leaf Item's label while in move mode (no kebab).
class _LeafLabel extends StatelessWidget {
  final String name;
  const _LeafLabel({required this.name});

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
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold))
        ]
      ),
    );
  }
}

/// A Nest's title + border while in move mode (no kebab), wrapping its
/// own children (slots, or a dimmed read-only view if off-limits).
class _NestLabelBox extends StatelessWidget {
  final String name;
  final Widget child;
  const _NestLabelBox({required this.name, required this.child});

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Image.asset("icon_in_app/icon_nest.png", color: Colors.grey.shade600, height: 30,),
              const SizedBox(width: 10,),
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            ]
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
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
