// -----------------------------------------------------------------------
// app_drawer.dart
//
// The slide-out menu (hamburger icon) shared by HomePage and
// PackDetailPage.
//
// The pack that is currently open is highlighted in gray.
//
// Flutter only builds a Drawer's contents while it is open, so
// initState below runs every time the drawer is opened - that is what
// keeps the pack list fresh without any extra reload code.
// -----------------------------------------------------------------------

import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/item_node.dart';
import '../screens/add_edit_page.dart';
import '../screens/pack_detail_page.dart';


class AppDrawer extends StatefulWidget {
  final int? selectedPackId;
  final VoidCallback? onPackAdded; // Called after add a new pack from the drawer, so the page underneath (Home) can refresh its own list.

  const AppDrawer({super.key, this.selectedPackId, this.onPackAdded});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _db = DatabaseHelper.instance;
  late final Future<List<ItemNode>> _packsFuture;

  @override
  void initState() {
    super.initState();
    _packsFuture = _db.getPacks();
  }

  // Closes the drawer, then opens pack
  void _openPack(ItemNode pack) {
    final navigator = Navigator.of(context);
    navigator.pop(); // closes the drawer
    if (pack.id == widget.selectedPackId) return; // already showing it

    final route = MaterialPageRoute<void>(
      builder: (_) => PackDetailPage(packId: pack.id),
    );

    if (widget.selectedPackId == null) {
      navigator.push(route);
    } else {
      navigator.pushReplacement(route);
    }
  }

  /// Closes the drawer, add a new pack. The user stays on the page they were on.
  Future<void> _addNewPack() async {
    final navigator = Navigator.of(context);
    navigator.pop(); // closes the drawer

    final result = await navigator.push<AddNodeResult>(
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
    widget.onPackAdded?.call();  
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Drawer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // header
          DrawerHeader(
            margin: EdgeInsets.zero,
            decoration: BoxDecoration(color: colors.primary),
            child: Center(
              child: Text(
                'Nested reorderable app',
                style: TextStyle(
                  color: colors.onPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // add new pack button
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _addNewPack,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                ),
                child: const Text('Add new pack'),
              ),
            ),
          ),

          // pack
          Expanded(
            child: FutureBuilder<List<ItemNode>>(
              future: _packsFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final packs = snapshot.data!;
                if (packs.isEmpty) {
                  return Center(
                    child: Text(
                      'No packs yet',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  );
                }
                return ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final pack in packs)
                      ListTile(
                        tileColor: pack.id == widget.selectedPackId
                            ? Colors.grey.shade300
                            : null,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 32),
                        title: Text(
                          pack.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onTap: () => _openPack(pack),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
