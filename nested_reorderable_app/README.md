# Nested Reorderable App

A Flutter app (Web + Android/iOS) for organizing things into **Packs**, where each Pack can hold **Nests** (containers) and **Items** (leaves). Nests can be nested inside other Nests. Anything can be moved anywhere in the Pack. Data is stored locally in SQLite.

## Features

- Create, update and delete Packs, Nests, and Items
- Nest a Nest inside another Nest (max 4 levels; Items are not limited)
- Move any Nest or Item to any position in the Pack, at any level
  - Tap ⋮ on a row → **Move to** → tap a **Move here** slot → ✓ to confirm, ✕ to cancel
  - Nothing is saved to the database until ✓ is tapped
  - Slots that would break the 4-level limit are not offered
- Deleting a Pack or Nest also deletes everything inside it
- Works on Flutter Web and mobile (SQLite via `sqflite`, with `sqflite_common_ffi_web` on Web)

## Design
You can see pictures of draft design in folder `draft design`.

## Database

Single table, `items_list_table`:

| Column       | Type    | Notes                                              |
|--------------|---------|----------------------------------------------------|
| `id`         | INTEGER | Primary key (autoincrement)                        |
| `name`       | TEXT    |                                                    |
| `type`       | TEXT    | `pack`, `nested`, or `item`                        |
| `id_parent`  | INTEGER | `0` for a Pack; otherwise the parent row's `id`    |
| `sort_order` | INTEGER | Position among siblings (0, 1, 2, ...)             |

## Setup

**Requirements:** [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart 3+ recommended)

```bash
# 1. Install dependencies
flutter pub get

# 2. Web only (one-time): copy the SQLite web files into /web
dart run sqflite_common_ffi_web:setup

# 3. Run
flutter run -d chrome     # Web
flutter run               # Android / iOS (device or emulator connected)
```

**Starting from a fresh Flutter project instead?** Copy this repo's `lib/` folder into your project, then add the dependencies:

```bash
flutter pub add sqflite
flutter pub add sqflite_common_ffi_web
flutter pub add path
dart run sqflite_common_ffi_web:setup
```

## Dart File Structure

```
lib/
├── main.dart
├── models/
│   └── item_node.dart
│   └── format_item.dart
├── database/
│   └── database_helper.dart
├── screens/
│   ├── home_page.dart
│   ├── pack_detail_page.dart
│   └── add_edit_page.dart
└── widgets/
    ├── view_tree.dart
    └── edit_tree.dart
    └── move_feature.dart
    └── app_drawer.dart
```

| File | Description |
|------|-------------|
| `main.dart` | App entry point. Sets up `MaterialApp`/theme and opens `HomePage`. |
| `models/item_node.dart` | Data model. `ItemType` enum (`pack` / `nested` / `item`) and `ItemNode`, one row of `items_list_table` plus its loaded `children`. |
|| `models/format_item.dart` | Collect reusable format such as icons, nest box, item box |
| `database/database_helper.dart` | All SQLite code: opens the database (Web or mobile), creates the table, insert / rename / delete (cascading), loads a whole Pack as a nested tree, saves sibling order, and moves a row to a new parent. |
| `screens/home_page.dart` | First screen. "Add new pack" button and the list of Packs. Tapping a Pack opens its detail page. |
| `screens/pack_detail_page.dart` | Shows one Pack in view mode, edit mode, or move mode. Holds the in-memory Pack tree and the pending move, and is the only screen that writes to the database. |
| `screens/add_edit_page.dart` | Shared "Add new" and "Edit name" form. |
| `widgets/view_tree.dart` | Read-only recursive widget that draws the box-inside-a-box tree. Also reused to show dimmed, non-interactive sections during a move. |
| `widgets/edit_tree.dart` | Edit-mode rendering: kebab-menu rows, "Add new" tiles, and "Move here" slots. |
| `widgets/move_feature.dart` | `MoveSession` (the pending-move state) and tree-walking helpers. |
| `widgets/app_drawer.dart` | Drawer's contents: quick access for add new pack button and go to other pack. |
