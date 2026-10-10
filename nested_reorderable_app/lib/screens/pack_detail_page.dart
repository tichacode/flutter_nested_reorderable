// -----------------------------------------------------------------------
// pack_detail_page.dart
//
// Shows one Pack. Three states:
//   - view mode  (default): read-only nested boxes, via PackTreeView
//   - edit mode  (pencil icon): each row has a kebab menu (Move to /
//                Delete) plus "Add new" tiles, via EditableLevel
//   - move mode  (inside edit mode, after tapping "Move to" on a row):
//                every row's kebab disappears, and the Pack re-renders
//                with "Move here" slots at every legal position. The
//                top checkmark/X are re-purposed while this is active -
//                see _confirmMove / _cancelMove below.
//
// This page owns the single in-memory copy of the whole Pack tree.
// Add / delete / rename write to the database immediately, same as
// before. A move is different: picking a "Move here" slot only updates
// local state (MoveSession) - nothing is written to the database until
// the checkmark is tapped, and tapping X discards it with no DB write
// at all.
// -----------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/item_node.dart';
import '../widgets/edit_tree.dart';
import '../widgets/view_tree.dart';
import 'add_edit_page.dart';

class PackDetailPage extends StatefulWidget {
  final int packId;

  const PackDetailPage({super.key, required this.packId});

  @override
  State<PackDetailPage> createState() => _PackDetailPageState();
}

class _PackDetailPageState extends State<PackDetailPage> {
  final _db = DatabaseHelper.instance;

  ItemNode? _pack;
  bool _isEditing = false;
  MoveSession? _moveSession;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final pack = await _db.loadPackTree(widget.packId);
    if (!mounted) return;
    setState(() => _pack = pack);
  }

  void _exitEditMode() {
    setState(() {
      _isEditing = false;
      _moveSession = null;
    });
  }

  // --- Add / delete ------------------------------------------------------

  Future<void> _addChild(ItemNode parent, int depth) async {
    final canAddNest = depth < kMaxNestDepth;
    final allowedTypes = canAddNest
        ? const [ItemType.nested, ItemType.item]
        : const [ItemType.item];

    final result = await Navigator.push<AddNodeResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditPage(title: 'Add new', allowedTypes: allowedTypes),
      ),
    );
    if (result == null) return;

    await _db.insertNode(name: result.name, type: result.type, idParent: parent.id);
    await _reload();
  }

  Future<void> _deleteNode(ItemNode node) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${node.name}"?'),
        content: Text(
          node.type == ItemType.item
              ? 'This item will be removed.'
              : 'This will also remove everything nested inside it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _db.deleteNodeCascade(node.id);
    await _reload();
  }

  Future<void> _deletePack(ItemNode pack) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${pack.name}"?'),
        content: const Text(
          'This will also delete every nest and item inside this pack.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _db.deleteNodeCascade(pack.id);
    if (mounted) Navigator.pop(context);
  }

  /// Used only by the empty-state "Add new item" button, so a
  /// brand-new pack doesn't force you through edit mode just to add
  /// its very first row.
  Future<void> _addFirstChild(ItemNode pack) => _addChild(pack, 0);

  // --- Kebab menu ----------------------------------------------------

  Future<void> _onKebabTap(ItemNode node) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Center(child: Text('Move to')),
              onTap: () => Navigator.pop(context, 'move'),
            ),
            const Divider(height: 1),
            ListTile(
              title: const Center(child: Text('Delete')),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'move') {
      _startMove(node);
    } else if (action == 'delete') {
      await _deleteNode(node);
    }
  }

  // --- Move ------------------------------------------------------------

  void _startMove(ItemNode node) {
    final pack = _pack;
    if (pack == null) return;
    final located = findParentAndIndex(pack, node.id);
    if (located == null) return; // shouldn't happen for a valid tree

    setState(() {
      _moveSession = MoveSession(
        node: node,
        originalParentId: located.parent.id,
        originalIndex: located.index,
        excludedIds: collectSubtreeIds(node),
        nestSpan: nestSpanOf(node),
      );
    });
  }

  void _selectSlot(int parentId, int index) {
    final session = _moveSession;
    if (session == null) return;
    setState(() {
      session.pendingParentId = parentId;
      session.pendingIndex = index;
    });
  }

  void _cancelMove() {
    setState(() => _moveSession = null);
  }

  Future<void> _confirmMove() async {
    final session = _moveSession;
    final pack = _pack;
    if (session == null || pack == null || !session.hasPendingDestination) return;

    final destParentId = session.pendingParentId!;
    final destIndex = session.pendingIndex!;
    final sourceParentId = session.originalParentId;
    final movedNode = session.node;

    final destParent = findNode(pack, destParentId);
    final sourceParent = findNode(pack, sourceParentId);
    if (destParent == null) return;

    // Work out the destination's new child order first (moved node
    // inserted at the chosen position), before writing anything.
    final destSiblings = List<ItemNode>.of(destParent.children)
      ..removeWhere((n) => n.id == movedNode.id);
    final insertAt = destIndex < 0
        ? 0
        : (destIndex > destSiblings.length ? destSiblings.length : destIndex);
    destSiblings.insert(insertAt, movedNode);

    if (destParentId != sourceParentId) {
      await _db.moveNode(movedNode.id, destParentId);
    }
    await _db.saveSiblingOrder(destSiblings);

    if (destParentId != sourceParentId && sourceParent != null) {
      final remaining = List<ItemNode>.of(sourceParent.children)
        ..removeWhere((n) => n.id == movedNode.id);
      await _db.saveSiblingOrder(remaining);
    }

    setState(() => _moveSession = null);
    await _reload();
  }

  // --- UI ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pack = _pack;
    return Scaffold(
      body: SafeArea(
        child: pack == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopBar(context, pack),
                  const Divider(height: 1),
                  Expanded(child: _buildBody(pack)),
                ],
              ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, ItemNode pack) {
    final inMoveMode = _moveSession != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(
        children: [
          BackButton(
            onPressed: inMoveMode
                ? _cancelMove
                : (_isEditing ? _exitEditMode : () => Navigator.pop(context)),
          ),
          Expanded(
            child: Text(
              pack.name,
              style: Theme.of(context).textTheme.titleLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (inMoveMode) ...[
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Move here',
              onPressed: _moveSession!.hasPendingDestination ? _confirmMove : null,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel move',
              onPressed: _cancelMove,
            ),
          ] else if (_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Done',
              onPressed: _exitEditMode,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: _exitEditMode,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: () => setState(() => _isEditing = true),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete pack',
              onPressed: () => _deletePack(pack),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(ItemNode pack) {
    if (pack.children.isEmpty && !_isEditing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Nothing here!', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => _addFirstChild(pack),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              child: const Text('Add new item'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _isEditing
          ? EditableLevel(
              parent: pack,
              depth: 0,
              moveSession: _moveSession,
              onAddChild: _addChild,
              onKebabTap: _onKebabTap,
              onSelectSlot: _selectSlot,
            )
          : PackTreeView(node: pack),
    );
  }
}
