// -----------------------------------------------------------------------
// main.dart
//
// App entry point. Nothing feature-specific lives here on purpose -
// it just sets up the MaterialApp theme and points "home" at HomePage.
// -----------------------------------------------------------------------

import 'package:flutter/material.dart';

import 'screens/home_page.dart';

void main() {
  runApp(const NestedReorderableApp());
}

class NestedReorderableApp extends StatelessWidget {
  const NestedReorderableApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nested reorderable app',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF102A54)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
