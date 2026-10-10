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
// NOTE ON THE TABLE SCHEMA
// -------------------------
// You asked for exactly these 4 columns:
//   id INTEGER PRIMARY KEY, name TEXT, type TEXT, id_parent INTEGER
//
// I added ONE extra column: `sort_order INTEGER`.
// Reason: a row's position among its siblings has to be saved
// *somewhere*, and the `id` column can't be reused for that (ids are
// assigned by SQLite and changing them would mean re-writing every
// child's id_parent too, which is fragile). `sort_order` just remembers
// "this row is the Nth child of its parent". If you don't want this
// extra column, you can remove it, but then re-ordering (including
// "Move to") will only last until the app is closed.
// -----------------------------------------------------------------------

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import '../models/item_node.dart';

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

  /// The id used to mean "no parent" - matches your example data
  /// (Pack 1 / Pack 2 both have id_parent = 0).
  static const rootId = 0;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    if (kIsWeb) {
      // On Flutter Web there is no filesystem, so sqflite alone can't
      // work. sqflite_common_ffi_web stores the data in the browser
      // (IndexedDB) instead.
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

  /// Changes [id]'s parent - used by the "Move to" picker when a node
  /// is being moved to a different container. (If it's only being
  /// repositioned among its current siblings, you don't need this -
  /// just call saveSiblingOrder.)
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

  /// Deletes [id] AND every descendant of it (a Pack full of Nests and
  /// Items, or just one Item - works for any type).
  Future<void> deleteNodeCascade(int id) async {
    final children = await getChildren(id);
    for (final child in children) {
      await deleteNodeCascade(child.id);
    }
    final db = await database;
    await db.delete(table, where: '$colId = ?', whereArgs: [id]);
  }
}
