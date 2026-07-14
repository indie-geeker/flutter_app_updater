import 'package:flutter/material.dart';

import '../production/production_update_configuration.dart';
import 'production_integration_page.dart';
import 'update_simulator_page.dart';

/// Keeps the safe simulator first while exposing an explicit production tab.
final class ExampleHomePage extends StatefulWidget {
  final ProductionUpdateConfiguration productionConfiguration;

  const ExampleHomePage({
    super.key,
    required this.productionConfiguration,
  });

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

final class _ExampleHomePageState extends State<ExampleHomePage> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          const UpdateSimulatorPage(),
          ProductionIntegrationPage(
            configuration: widget.productionConfiguration,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: 'Simulator',
          ),
          NavigationDestination(
            icon: Icon(Icons.security_outlined),
            selectedIcon: Icon(Icons.security),
            label: 'Production',
          ),
        ],
      ),
    );
  }
}
