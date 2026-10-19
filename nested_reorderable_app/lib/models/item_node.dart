// -----------------------------------------------------------------------
// item_node.dart
//
// The data model for a single row of `items_list_table`.
//
// -----------------------------------------------------------------------

/// Item types
///   - none   -> for show none selected in input list
///   - pack   -> a top-level container (id_parent = 0)
///   - nested -> a "Nest" that can contain more nests or items
///   - item   -> a leaf row, cannot contain children
enum ItemType {
  none,
  pack,
  nested,
  item;

  // for database
  String get dbValue {
    switch (this) {
      case ItemType.none:
        return 'Please select type';
      case ItemType.pack:
        return 'pack';
      case ItemType.nested:
        return 'nested';
      case ItemType.item:
        return 'item';
    }
  }

  // for the user in menus / dropdowns.
  String get label {
    switch (this) {
      case ItemType.none:
        return 'Please select type';
      case ItemType.pack:
        return 'Pack';
      case ItemType.nested:
        return 'Nest';
      case ItemType.item:
        return 'Item';
    }
  }

  // Parses the string coming back from SQLite into an [ItemType].
  static ItemType fromDbValue(String value) {
    switch (value) {
      case 'pack':
        return ItemType.pack;
      case 'nested':
        return ItemType.nested;
      case 'item':
        return ItemType.item;
      default:
        throw ArgumentError('Unknown item type "$value" from database');
    }
  }
}

/// One row of `items_list_table`.
///
/// [children] is empty by default. It only gets filled in after you call
/// `DatabaseHelper.loadPackTree(...)`, which walks the table and builds
/// the nested structure you see in the wireframes. Reading a single row
/// on its own will never populate [children] automatically.
class ItemNode {
  final int id;
  String name;
  final ItemType type;
  final int idParent;
  int sortOrder;
  final List<ItemNode> children;

  ItemNode({
    required this.id,
    required this.name,
    required this.type,
    required this.idParent,
    this.sortOrder = 0,
    List<ItemNode>? children,
  }) : children = children ?? [];

  /// Builds an [ItemNode] from a raw SQLite row (a `Map`).
  factory ItemNode.fromMap(Map<String, Object?> map) {
    return ItemNode(
      id: map['id'] as int,
      name: map['name'] as String,
      type: ItemType.fromDbValue(map['type'] as String),
      idParent: map['id_parent'] as int,
      sortOrder: (map['sort_order'] as int?) ?? 0,
    );
  }

  /// Converts this node back into a `Map` ready for `db.insert` / `db.update`.
  /// Note: `id` is intentionally left out - SQLite assigns it for you on
  /// insert, and you should never need to overwrite it on update.
  Map<String, Object?> toMap() {
    return {
      'name': name,
      'type': type.dbValue,
      'id_parent': idParent,
      'sort_order': sortOrder,
    };
  }

  /// A leaf item can never have children - convenience getter used a lot
  /// in the UI code to decide whether to draw a nested container or a
  /// simple box.
  bool get isLeaf => type == ItemType.item;

  /// A full, independent copy of this node and everything under it.
  /// Used to remember what a Pack looked like before editing started.
  ItemNode clone() {
    return ItemNode(
      id: id,
      name: name,
      type: type,
      idParent: idParent,
      sortOrder: sortOrder,
      children: [for (final child in children) child.clone()],
    );
  }

  @override
  String toString() =>
      'ItemNode(id: $id, name: $name, type: ${type.dbValue}, '
      'idParent: $idParent, sortOrder: $sortOrder, '
      'children: ${children.length})';
}