// -----------------------------------------------------------------------
// pack_detail_page.dart
//
// Shows one Pack. Three states:
//   - view mode  (default): read-only nested boxes, via PackTreeView
//   - edit mode  (pencil icon): each row has a kebab menu (Edit / Move to /
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
import '../widgets/app_drawer.dart';
import '../widgets/edit_tree.dart';
import '../widgets/view_tree.dart';
import '../widgets/move_feature.dart';
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
  ItemNode? _editSnapshot; // Copy of the pack when edit mode started. Use when cancel edit.

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

  // Starts edit mode + snapshot data
  void _enterEditMode() {
    final pack = _pack;
    if (pack == null) return;
    setState(() {
      _editSnapshot = pack.clone();
      _isEditing = true;
    });
  }

  // close edit mode
  void _exitEditMode() {
    setState(() {
      _isEditing = false;
      _moveSession = null;
      _editSnapshot = null;
    });
  }

  // go back to how the pack was before edit mode started (rewrites the database from the snapshot)
  Future<void> _cancelEdit() async {
    final snapshot = _editSnapshot;
    final pack = _pack;
    if (snapshot == null || pack == null || _sameTree(snapshot, pack)) {
      _exitEditMode(); // nothing to undo
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'Everything you changed since you started editing will be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _db.restoreSubtree(snapshot);
    await _reload();
    if (!mounted) return;
    _exitEditMode();
  }

  // ture if a nd b have all same node in pack
  bool _sameTree(ItemNode a, ItemNode b) {
    if (a.id != b.id || a.name != b.name || a.type != b.type) return false;
    if (a.children.length != b.children.length) return false;
    for (var i = 0; i < a.children.length; i++) {
      if (!_sameTree(a.children[i], b.children[i])) return false;
    }
    return true;
  }

  // --- Add / delete ------------------------------------------------------

  Future<void> _addChild(ItemNode parent, int depth) async {
    final canAddNest = depth < kMaxNestDepth;
    final allowedTypes = canAddNest
        ? const [ItemType.none, ItemType.nested, ItemType.item]
        : const [ItemType.none, ItemType.item];
    final warningMaxNest = canAddNest
        ? null
        : 'Can not add nest, You reach maximum nest in nest limit';

    final result = await Navigator.push<AddNodeResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditPage(title: 'Add new', allowedTypes: allowedTypes, warningMsg: warningMaxNest),
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

  // when click "Add new item" button in empty pack
  Future<void> _addFirstChild(ItemNode pack) async {
    _enterEditMode();
    await _addChild(pack, 0);
  }

  // --- Edit (rename) -------------------------------------------------

  /// Changes a Nest's or Item's name. The type can't be changed.
  Future<void> _editNode(ItemNode node) async {
    final result = await Navigator.push<AddNodeResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditPage(
          title: 'Edit name',
          allowedTypes: [node.type],
          warningMsg: null,
          initialName: node.name,
        ),
      ),
    );
    if (result == null || result.name == node.name) return; // cancelled / unchanged

    await _db.renameNode(node.id, result.name);
    await _reload();
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

    // moved node inserted at the chosen position before writing anything.
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

    // reorder sort number of sibling after move
    if (destParentId != sourceParentId && sourceParent != null) {
      final remaining = List<ItemNode>.of(sourceParent.children)
        ..removeWhere((n) => n.id == movedNode.id);
      await _db.saveSiblingOrder(remaining);
    }

    setState(() => _moveSession = null);
    await _reload();
  }

  // --- Kebab menu ----------------------------------------------------

  Future<void> _onKebabTap(ItemNode node) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Center(child: Text('Edit')),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            const Divider(height: 1),
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
    if (action == 'edit') {
      await _editNode(node);
    } else if (action == 'move') {
      _startMove(node);
    } else if (action == 'delete') {
      await _deleteNode(node);
    }
  }

  // --- UI ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pack = _pack;
    // While editing, the phone's back gesture / button (and the browser's
    // back button) must not leave the page. canPop: false hands the press
    // to onPopInvokedWithResult below, which treats it like the X button.
    return PopScope(
      canPop: !_isEditing,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return; // not editing: the page was closed normally
        if (_moveSession != null) {
          _cancelMove(); // same as X button while picking a move destination
        } else {
          _cancelEdit(); // same as X button in edit mode (asks first if changed)
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nested reorderable app'),
          // View mode: the drawer's hamburger icon shows automatically.
          // Edit / move mode: no drawer and no back arrow
          automaticallyImplyLeading: !_isEditing,
        ),
        // The drawer is only available outside edit mode.
        drawer: _isEditing ? null : AppDrawer(selectedPackId: widget.packId),
        body: SafeArea(
          child: pack == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(height: 1),
                    _buildTopBar(context, pack),
                    Expanded(child: _buildBody(pack)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, ItemNode pack) {
    final inMoveMode = _moveSession != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      child: Row(
        children: [
          // pack name
          Expanded(
            child: Text(
              pack.name,
              style: Theme.of(context).textTheme.titleLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // move mode
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
          
          // edit mode
          ] else if (_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Done',
              onPressed: _exitEditMode,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel changes',
              onPressed: _cancelEdit,
            ),
          
          // view mode
          ] else ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
              onPressed: _enterEditMode,
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