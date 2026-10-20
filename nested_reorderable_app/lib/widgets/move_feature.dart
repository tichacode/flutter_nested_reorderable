// -----------------------------------------------------------------------
// move_feature.dart
//
// Contains every feature related with move node
//
// -----------------------------------------------------------------------

import '../models/item_node.dart';

// ---------------------------------------------------------------------
// Move session + tree-walking helpers
// ---------------------------------------------------------------------

// (parent, index) pair - the result of findParentAndIndex
class ParentIndex {
  final ItemNode parent;
  final int index;
  ParentIndex(this.parent, this.index);
}

/// Tracks an in-progress "Move to" session for one node.
/// picking a "Move here" slot only updates [pendingParentId] / [pendingIndex] here;
/// nothing is written to the database until the checkmark is tapped.
class MoveSession {
  final ItemNode node;
  final int originalParentId;
  final int originalIndex;
  final Set<int> excludedIds; // node's own id + every descendant's id : node can't move in to descendant
  final int nestSpan; // How many nest-levels node's own subtree spans, counting itself
  
  // set when selected slot
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

  // The slot that would put the node back exactly where it already
  bool isNoOp(int parentId, int index) =>
      parentId == originalParentId && index == originalIndex;
}

// return set of node's own id + every descendant's id.
Set<int> collectSubtreeIds(ItemNode node) {
  final ids = <int>{node.id};
  for (final child in node.children) {
    ids.addAll(collectSubtreeIds(child));
  }
  return ids;
}

// return How many nest-levels deep node's own subtree goes, counting itself
int nestSpanOf(ItemNode node) {
  if (node.type != ItemType.nested) return 0;
  var deepestChild = 0;
  for (final child in node.children) {
    final span = nestSpanOf(child);
    if (span > deepestChild) deepestChild = span;
  }
  return 1 + deepestChild;
}

// Finds childId's current parent and its index within that parent
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

// Finds any node by id, anywhere under root (root included).
ItemNode? findNode(ItemNode root, int id) {
  if (root.id == id) return root;
  for (final child in root.children) {
    final found = findNode(child, id);
    if (found != null) return found;
  }
  return null;
}
