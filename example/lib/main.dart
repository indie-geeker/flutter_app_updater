import 'package:flutter/material.dart';

import 'presentation/example_home_page.dart';
import 'production/production_update_configuration.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  final ProductionUpdateConfiguration? productionConfiguration;

  const MyApp({super.key, this.productionConfiguration});

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
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      home: ExampleHomePage(
        productionConfiguration: productionConfiguration ??
            ProductionUpdateConfiguration.fromEnvironment(),
      ),
    );
  }
}
