// -----------------------------------------------------------------------
// database_helper.dart
//
// Everything related to SQLite lives in this one file:
//   - opening the database (works on Web AND Android/iOS/desktop)
//   - creating the `items_list_table` table
//   - insert / rename / delete
//   - loading a whole Pack as a nested tree of ItemNode
//   - saving a new sibling order (after a reorder or a "Move to")
//
// -----------------------------------------------------------------------

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import '../models/item_node.dart';

/// How many levels of "nest in nest" are allowed
final int kMaxNestDepth = 4;

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const _dbName = 'nested_reorderable_app.db';
  static const _dbVersion = 1;

  static const table = 'items_list_table';
  static const colId = 'id';
  static const colName = 'name';
  static const colType = 'type';
  static const colIdParent = 'id_parent';
  static const colSortOrder = 'sort_order';

  static const rootId = 0;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    if (kIsWeb) {
      // sqflite_common_ffi_web stores the data in the browser (IndexedDB) instead.
      final factory = databaseFactoryFfiWeb;
      return factory.openDatabase(
        _dbName,
        options: OpenDatabaseOptions(
          version: _dbVersion,
          onCreate: (db, version) => _onCreate(db),
        ),
      );
    }

    // Android / iOS / desktop: normal sqflite on-disk database.
    final dbDir = await getDatabasesPath();
    final path = join(dbDir, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) => _onCreate(db),
    );
  }

  Future<void> _onCreate(Database db) async {
    await db.execute('''
      CREATE TABLE $table (
        $colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colName TEXT NOT NULL,
        $colType TEXT NOT NULL,
        $colIdParent INTEGER NOT NULL DEFAULT 0,
        $colSortOrder INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  // ---------------------------------------------------------------------
  // CREATE
  // ---------------------------------------------------------------------

  /// Inserts a new row and puts it at the end of its siblings.
  /// Returns the new row's id.
  Future<int> insertNode({
    required String name,
    required ItemType type,
    required int idParent,
  }) async {
    final db = await database;
    final siblings = await getChildren(idParent);
    final newRow = {
      colName: name,
      colType: type.dbValue,
      colIdParent: idParent,
      colSortOrder: siblings.length, // put it last
    };
    return db.insert(table, newRow);
  }

  /// Convenience for the Home page's "Add new pack" button.
  Future<int> insertPack(String name) {
    return insertNode(name: name, type: ItemType.pack, idParent: rootId);
  }

  // ---------------------------------------------------------------------
  // READ
  // ---------------------------------------------------------------------

  /// All top-level packs, in display order.
  Future<List<ItemNode>> getPacks() => getChildren(rootId);

  /// The direct children of [idParent] (one level only), in display order.
  Future<List<ItemNode>> getChildren(int idParent) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: '$colIdParent = ?',
      whereArgs: [idParent],
      orderBy: '$colSortOrder ASC, $colId ASC',
    );
    return rows.map(ItemNode.fromMap).toList();
  }

  Future<ItemNode?> getNodeById(int id) async {
    final db = await database;
    final rows = await db.query(table, where: '$colId = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ItemNode.fromMap(rows.first);
  }

  /// Loads a full Pack (or any node) together with every descendant,
  /// already nested inside `.children`. This is what the Pack detail
  /// page uses to draw the whole box-in-a-box tree in one go.
  Future<ItemNode> loadPackTree(int packId) async {
    final root = await getNodeById(packId);
    if (root == null) {
      throw StateError('No row with id $packId in $table');
    }
    await _fillChildrenRecursively(root);
    return root;
  }

  Future<void> _fillChildrenRecursively(ItemNode node) async {
    if (node.isLeaf) return; // items never have children
    final children = await getChildren(node.id);
    node.children
      ..clear()
      ..addAll(children);
    for (final child in node.children) {
      await _fillChildrenRecursively(child);
    }
  }

  // ---------------------------------------------------------------------
  // UPDATE
  // ---------------------------------------------------------------------

  Future<void> renameNode(int id, String newName) async {
    final db = await database;
    await db.update(
      table,
      {colName: newName},
      where: '$colId = ?',
      whereArgs: [id],
    );
  }

  /// use when action move impact with siblings
  /// Persists a new order for one level of siblings (used after a
  /// "Move to" is confirmed). Pass the children list in its NEW order;
  /// this writes 0, 1, 2, ... into `sort_order` for each one.
  Future<void> saveSiblingOrder(List<ItemNode> siblingsInNewOrder) async {
    final db = await database;
    final batch = db.batch();
    for (var i = 0; i < siblingsInNewOrder.length; i++) {
      batch.update(
        table,
        {colSortOrder: i},
        where: '$colId = ?',
        whereArgs: [siblingsInNewOrder[i].id],
      );
    }
    await batch.commit(noResult: true);
  }

  /// use when node move to new parent
  Future<void> moveNode(int id, int newIdParent) async {
    final db = await database;
    await db.update(
      table,
      {colIdParent: newIdParent},
      where: '$colId = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------
  // DELETE
  // ---------------------------------------------------------------------

  /// Deletes [id] AND every descendant of it
  Future<void> deleteNodeCascade(int id) async {
    final children = await getChildren(id);
    for (final child in children) {
      await deleteNodeCascade(child.id);
    }
    final db = await database;
    await db.delete(table, where: '$colId = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------
  // RESTORE (used by the edit-mode "X" button)
  // ---------------------------------------------------------------------

  /// Puts everything under [snapshot] (a Pack, as loaded by loadPackTree
  /// before editing started) back exactly as it was: same ids, names,
  /// parents and order. Anything added during editing is removed,
  /// anything deleted is brought back, and moves / renames are undone.
  ///
  /// Runs as ONE transaction, so if something fails the database is left
  /// as it was instead of half-restored. The Pack's own row is not
  /// touched - only what is inside it.
  Future<void> restoreSubtree(ItemNode snapshot) async {
    final db = await database;
    await db.transaction((txn) async {
      await _deleteDescendants(txn, snapshot.id);
      await _insertDescendants(txn, snapshot);
    });
  }

  Future<void> _deleteDescendants(DatabaseExecutor txn, int parentId) async {
    final rows = await txn.query(
      table,
      columns: [colId],
      where: '$colIdParent = ?',
      whereArgs: [parentId],
    );
    for (final row in rows) {
      final childId = row[colId] as int;
      await _deleteDescendants(txn, childId);
      await txn.delete(table, where: '$colId = ?', whereArgs: [childId]);
    }
  }

  Future<void> _insertDescendants(DatabaseExecutor txn, ItemNode parent) async {
    for (var i = 0; i < parent.children.length; i++) {
      final child = parent.children[i];
      await txn.insert(table, {
        colId: child.id, // same id as before, so nothing is renumbered
        colName: child.name,
        colType: child.type.dbValue,
        colIdParent: parent.id,
        colSortOrder: i,
      });
      await _insertDescendants(txn, child);
    }
  }
}