import 'package:flutter/material.dart';

import 'presentation/update_simulator_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF182028);
    const accent = Color(0xFFC84E2F);
    const canvas = Color(0xFFF2F0EA);
    final colors = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      surface: const Color(0xFFFCFBF7),
    );

    return MaterialApp(
      title: 'Update Simulator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colors,
        scaffoldBackgroundColor: canvas,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: colors.surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFD7D2C7)),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      home: const UpdateSimulatorPage(),
    );
  }
}
