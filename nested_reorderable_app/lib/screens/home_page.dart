// -----------------------------------------------------------------------
// home_page.dart
//
// The very first screen: "Add new pack" button + a list of existing
// packs. Tapping a pack opens PackDetailPage.
// -----------------------------------------------------------------------

import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/item_node.dart';
import '../widgets/app_drawer.dart';
import 'add_edit_page.dart';
import 'pack_detail_page.dart';

/// Lets HomePage find out when it becomes visible again (see didPopNext
/// below). Registered in main.dart under navigatorObservers.
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RouteAware {
  final _db = DatabaseHelper.instance;
  late Future<List<ItemNode>> _packsFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  /// Called when a page opened on top of Home (a pack, possibly reached
  /// through the drawer) is closed and Home is visible again. Packs may
  /// have been deleted or added meanwhile, so reload the list.
  @override
  void didPopNext() => _reload();

  void _reload() {
    setState(() {
      _packsFuture = _db.getPacks();
    });
  }

  Future<void> _addNewPack() async {
    final result = await Navigator.push<AddNodeResult>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddEditPage(
          title: 'Add new pack',
          allowedTypes: [ItemType.pack],
          warningMsg: null,
        ),
      ),
    );
    if (result == null) return;
    await _db.insertPack(result.name);
    _reload();
  }

  Future<void> _openPack(ItemNode pack) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PackDetailPage(packId: pack.id)),
    );
    _reload(); // pack may have been renamed/deleted while it was open
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nested reorderable app')),
      drawer: AppDrawer(onPackAdded: _reload),
      body: FutureBuilder<List<ItemNode>>(
        future: _packsFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final packs = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Add new pack button
              Center(
                child: OutlinedButton(
                  onPressed: _addNewPack,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                  ),
                  child: const Text('Add new pack'),
                ),
              ),
              const SizedBox(height: 24),
              
              // pack list
              if (packs.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      'No packs yet - add one above!',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                ),
              for (final pack in packs)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(
                      pack.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openPack(pack),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
