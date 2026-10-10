// -----------------------------------------------------------------------
// add_edit_page.dart
//
// One shared form screen used in two places:
//   1. Home page "Add new pack"        -> allowedTypes: [ItemType.pack]
//   2. Inside a Pack, "Add new"        -> allowedTypes: [ItemType.nested,
//                                          ItemType.item] (or just
//                                          [ItemType.item] once the 4-nest
//                                          limit has been reached)
//
// When allowedTypes has only one entry, the Type dropdown is hidden
// entirely (that's the "Add new pack" wireframe, which only asks for a
// name). When it has more than one entry, a dropdown is shown so the
// user can choose "Nest" or "Item".
// -----------------------------------------------------------------------

import 'package:flutter/material.dart';

import '../models/item_node.dart';

/// What this page hands back to whoever pushed it, via Navigator.pop.
class AddNodeResult {
  final String name;
  final ItemType type;

  AddNodeResult({required this.name, required this.type});
}

class AddEditPage extends StatefulWidget {
  final String title;
  final List<ItemType> allowedTypes;

  const AddEditPage({
    super.key,
    required this.title,
    required this.allowedTypes,
  });

  @override
  State<AddEditPage> createState() => _AddEditPageState();
}

class _AddEditPageState extends State<AddEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  late ItemType _selectedType;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.allowedTypes.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.pop(
      context,
      AddNodeResult(name: _nameController.text.trim(), type: _selectedType),
    );
  }

  void _cancel() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    final showTypePicker = widget.allowedTypes.length > 1;
    final radius = BorderRadius.circular(28);

    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: _cancel)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 32),
                const Text('Name', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: '${_selectedType.label} name',
                    border: OutlineInputBorder(borderRadius: radius),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Please enter a name'
                      : null,
                ),
                if (showTypePicker) ...[
                  const SizedBox(height: 24),
                  const Text('Type', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ItemType>(
                    value: _selectedType,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: radius),
                    ),
                    items: [
                      for (final type in widget.allowedTypes)
                        DropdownMenuItem(value: type, child: Text(type.label)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _selectedType = value);
                    },
                  ),
                ],
                const SizedBox(height: 40),
                Center(
                  child: SizedBox(
                    width: 220,
                    child: OutlinedButton(
                      onPressed: _save,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: radius),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: SizedBox(
                    width: 220,
                    child: OutlinedButton(
                      onPressed: _cancel,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: radius),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
