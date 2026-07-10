import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app_updater_example/main.dart';

void main() {
  testWidgets('renders the configurable update simulator', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Update Simulator'), findsWidgets);
    expect(find.text('Installed application'), findsOneWidget);
    expect(find.text('Available release'), findsOneWidget);
    expect(find.text('Simulation behavior'), findsOneWidget);
    expect(find.byKey(const Key('installed-version-field')), findsOneWidget);
    expect(find.byKey(const Key('release-version-field')), findsOneWidget);
    expect(find.byKey(const Key('force-update-switch')), findsOneWidget);
    expect(find.byKey(const Key('platform-field')), findsOneWidget);
    expect(find.byKey(const Key('delivery-field')), findsOneWidget);
    expect(find.byKey(const Key('duration-field')), findsOneWidget);
    expect(find.byKey(const Key('outcome-field')), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reset'), findsOneWidget);
    expect(
        find.widgetWithText(FilledButton, 'Check for update'), findsOneWidget);
  });

  testWidgets('platform selection constrains available delivery methods',
      (tester) async {
    await tester.pumpWidget(const MyApp());

    await tester.tap(find.byKey(const Key('platform-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('iOS').last);
    await tester.pumpAndSettle();

    final deliveryField = find.byKey(const Key('delivery-field'));
    await tester.ensureVisible(deliveryField);
    await tester.pumpAndSettle();
    await tester.tap(deliveryField);
    await tester.pumpAndSettle();
    expect(find.text('Official store'), findsWidgets);
    expect(find.text('Chinese Android market'), findsNothing);
    expect(find.text('Download and install APK'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    final platformField = find.byKey(const Key('platform-field'));
    await tester.ensureVisible(platformField);
    await tester.pumpAndSettle();
    await tester.tap(platformField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Windows').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(deliveryField);
    await tester.pumpAndSettle();
    await tester.tap(deliveryField);
    await tester.pumpAndSettle();
    expect(find.text('Desktop installer'), findsWidgets);
  });
}
