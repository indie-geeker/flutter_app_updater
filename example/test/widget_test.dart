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
    expect(
      find.byKey(const Key('runtime-architecture-field')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('runtime-channel-field')), findsOneWidget);
    expect(
      find.byKey(const Key('release-architecture-field')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('release-channel-field')), findsOneWidget);
    expect(find.byKey(const Key('delivery-field')), findsOneWidget);
    expect(find.byKey(const Key('fallback-delivery-field')), findsOneWidget);
    expect(find.byKey(const Key('duration-field')), findsOneWidget);
    expect(find.byKey(const Key('outcome-field')), findsOneWidget);
    expect(find.byKey(const Key('retry-succeeds-switch')), findsOneWidget);
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
    expect(find.text('Download APK only'), findsNothing);
    expect(find.text('Install local APK only'), findsNothing);
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

  testWidgets('Android exposes separate download and install flows',
      (tester) async {
    await tester.pumpWidget(const MyApp());

    final deliveryField = find.byKey(const Key('delivery-field'));
    await tester.ensureVisible(deliveryField);
    await tester.pumpAndSettle();
    await tester.tap(deliveryField);
    await tester.pumpAndSettle();

    expect(find.text('Download APK only'), findsOneWidget);
    expect(find.text('Install local APK only'), findsOneWidget);
    expect(find.text('Download and install APK'), findsWidgets);
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
    expect(find.text('Manifest action order'), findsOneWidget);
    expect(
      find.text('1. Download and install package · Recommended'),
      findsOneWidget,
    );
    expect(find.text('2. Open official store'), findsOneWidget);
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

  testWidgets('retry reuses the simulator executor and reaches success',
      (tester) async {
    await _pumpScenario(
      tester,
      DemoScenario.defaults().copyWith(
        outcome: DemoOutcome.downloadFailed,
        succeedOnRetry: true,
        executionDuration: Duration.zero,
      ),
    );
    await _checkForUpdate(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Update now'));
    await tester.pumpAndSettle();

    expect(find.text('PACKAGE_DOWNLOAD_FAILED'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Simulation complete'), findsOneWidget);
  });

  testWidgets('channel and architecture mismatches are visible',
      (tester) async {
    final controller = await _pumpScenario(
      tester,
      DemoScenario.defaults().copyWith(
        runtimeChannel: 'stable',
        releaseChannel: 'beta',
      ),
    );

    await _checkForUpdate(tester);
    expect(find.textContaining('runtime channel stable'), findsOneWidget);

    controller.updateScenario(
      controller.scenario.copyWith(
        releaseChannel: 'stable',
        runtimeArchitecture: 'arm64',
        releaseArchitecture: 'x64',
      ),
    );
    await tester.pump();
    await _checkForUpdate(tester);

    expect(find.text('NO_MATCHING_RELEASE'), findsOneWidget);
    expect(find.textContaining('runtime architecture arm64'), findsOneWidget);
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
