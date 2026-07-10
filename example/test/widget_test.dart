import 'package:flutter/material.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater_example/demo/demo_scenario.dart';
import 'package:flutter_app_updater_example/demo/update_demo_controller.dart';
import 'package:flutter_app_updater_example/presentation/update_simulator_page.dart';
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

  testWidgets('shows an in-page result when no update is available',
      (tester) async {
    await _pumpScenario(
      tester,
      DemoScenario.defaults().copyWith(updateAvailable: false),
    );

    await _checkForUpdate(tester);

    expect(find.text('No update available'), findsOneWidget);
    expect(find.textContaining('up to date'), findsOneWidget);
  });

  testWidgets('recommended update can be deferred', (tester) async {
    final controller = await _pumpScenario(
      tester,
      DemoScenario.defaults().copyWith(executionDuration: Duration.zero),
    );

    await _checkForUpdate(tester);

    expect(find.text('Update 2.0.0 available'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Later'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update now'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Later'));
    await tester.pumpAndSettle();

    expect(find.text('Update 2.0.0 available'), findsNothing);
    expect(controller.phase, DemoPhase.idle);
  });

  testWidgets('required update resists dismissal but exposes simulator reset',
      (tester) async {
    final controller = await _pumpScenario(
      tester,
      DemoScenario.defaults().copyWith(
        policyLevel: UpdatePolicyLevel.required,
        executionDuration: Duration.zero,
      ),
    );

    await _checkForUpdate(tester);

    expect(find.text('Required update'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Later'), findsNothing);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('Required update'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Required update'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Reset simulation'));
    await tester.pumpAndSettle();
    expect(find.text('Required update'), findsNothing);
    expect(controller.phase, DemoPhase.idle);
  });

  testWidgets('simulated transfer reports progress and can be canceled',
      (tester) async {
    await _pumpScenario(
      tester,
      DemoScenario.defaults().copyWith(
        executionDuration: const Duration(milliseconds: 500),
      ),
    );
    await _checkForUpdate(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Update now'));
    await tester.pump(const Duration(milliseconds: 130));

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('25%'), findsWidgets);
    expect(
        find.widgetWithText(OutlinedButton, 'Cancel update'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel update'));
    await tester.pumpAndSettle();

    expect(find.text('ACTION_CANCELED'), findsOneWidget);
  });

  testWidgets('download failure exposes its code and retry action',
      (tester) async {
    await _pumpScenario(
      tester,
      DemoScenario.defaults().copyWith(
        outcome: DemoOutcome.downloadFailed,
        executionDuration: Duration.zero,
      ),
    );
    await _checkForUpdate(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Update now'));
    await tester.pumpAndSettle();

    expect(find.text('PACKAGE_DOWNLOAD_FAILED'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets('install permission failure offers simulated recovery',
      (tester) async {
    await _pumpScenario(
      tester,
      DemoScenario.defaults().copyWith(
        outcome: DemoOutcome.installPermissionRequired,
        executionDuration: Duration.zero,
      ),
    );
    await _checkForUpdate(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Update now'));
    await tester.pumpAndSettle();

    expect(find.text('PACKAGE_INSTALL_PERMISSION_REQUIRED'), findsOneWidget);
    final settings = find.widgetWithText(
      OutlinedButton,
      'Open settings (simulated)',
    );
    expect(settings, findsOneWidget);
    await tester.tap(settings);
    await tester.pump();
    expect(find.textContaining('no system setting changed'), findsOneWidget);
  });

  testWidgets('successful action clearly reports simulated completion',
      (tester) async {
    await _pumpScenario(
      tester,
      DemoScenario.defaults().copyWith(executionDuration: Duration.zero),
    );
    await _checkForUpdate(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Update now'));
    await tester.pumpAndSettle();

    expect(find.text('Simulation complete'), findsOneWidget);
    expect(find.textContaining('No external action was performed'),
        findsOneWidget);
  });
}

Future<UpdateDemoController> _pumpScenario(
  WidgetTester tester,
  DemoScenario scenario,
) async {
  final controller = UpdateDemoController(scenario: scenario);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(home: UpdateSimulatorPage(controller: controller)),
  );
  return controller;
}

Future<void> _checkForUpdate(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Check for update');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}
