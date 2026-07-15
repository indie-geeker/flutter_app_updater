import 'package:flutter/material.dart';

/// Card styling shared by the example without relying on version-specific
/// [ThemeData.cardTheme] types.
final class AppCard extends StatelessWidget {
  final Color? color;
  final Widget child;

  const AppCard({super.key, this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color ?? Theme.of(context).colorScheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFD7D2C7)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
