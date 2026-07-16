import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater_example/presentation/production_integration_page.dart';
import 'package:flutter_app_updater_example/production/production_app_metadata.dart';
import 'package:flutter_app_updater_example/production/production_update_configuration.dart';
import 'package:flutter_app_updater_example/production/production_update_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_finders.dart';

void main() {
  testWidgets('disabled page does not load runtime boundaries', (tester) async {
    final loader = _RuntimeLoader(_metadata());
    final factory = _StaticUpdaterFactory();
    final controller = ProductionUpdateController(
      configuration: ProductionUpdateConfiguration.parse(),
      runtimeLoader: loader,
      updaterFactory: factory,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ProductionIntegrationPage(controller: controller)),
    );

    expect(find.text('Production integration disabled'), findsOneWidget);
    expect(find.text('ENABLE_PRODUCTION_UPDATE_EXAMPLE'), findsOneWidget);
    expect(loader.calls, 0);
    expect(factory.calls, 0);
  });

  testWidgets('confirmation cancel executes nothing and confirm executes once',
      (tester) async {
    final executor = _RecordingExecutor();
    final controller = ProductionUpdateController(
      configuration: _configuration(),
      runtimeLoader: _RuntimeLoader(_metadata()),
      updaterFactory: _StaticUpdaterFactory(executor: executor),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ProductionIntegrationPage(controller: controller)),
    );

    await tester.tap(
      widgetSubtypeWithText<FilledButton>('Check production update'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Update 2.0.0 available'), findsOneWidget);
    expect(executor.calls, 0);

    await tester.tap(
      widgetSubtypeWithText<FilledButton>('Review recommended action'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Confirm update action'), findsOneWidget);
    expect(find.text('Action type'), findsOneWidget);
    expect(find.text('Open official store'), findsOneWidget);
    expect(find.text('Destination host'), findsOneWidget);
    expect(find.text('play.google.com'), findsOneWidget);
    expect(find.text('Package / installer type'), findsOneWidget);
    expect(find.text('Exact size'), findsOneWidget);
    expect(find.text('SHA-256'), findsOneWidget);
    expect(find.text('Distribution policy'), findsOneWidget);
    expect(find.text('any'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(executor.calls, 0);

    await tester.tap(
      widgetSubtypeWithText<FilledButton>('Review recommended action'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      widgetSubtypeWithText<FilledButton>('Confirm and execute'),
    );
    await tester.pumpAndSettle();

    expect(executor.calls, 1);
    expect(find.text('Update action completed'), findsOneWidget);
  });

  testWidgets('structured runtime failures render without escaping widget tree',
      (tester) async {
    final controller = ProductionUpdateController(
      configuration: _configuration(),
      runtimeLoader: _ThrowingRuntimeLoader(),
      updaterFactory: _StaticUpdaterFactory(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ProductionIntegrationPage(controller: controller)),
    );

    await tester.tap(
      widgetSubtypeWithText<FilledButton>('Check production update'),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('CONFIGURATION_INVALID'), findsOneWidget);
    expect(find.textContaining('metadata unavailable'), findsOneWidget);
  });
}

ProductionUpdateConfiguration _configuration() {
  return ProductionUpdateConfiguration.parse(
    enabled: true,
    manifestUrl: 'https://updates.example.com/manifest.json',
    expectedAppId: 'com.example.app',
    publicKeysJson: jsonEncode({
      'release-1': base64.encode(List<int>.filled(32, 1)),
    }),
  );
}

ProductionAppMetadata _metadata() {
  return const ProductionAppMetadata(
    version: '1.0.0',
    buildNumber: '10',
    appId: 'com.example.app',
    downloadDirectory: '/simulated/application-support/updates',
  );
}

final class _RuntimeLoader implements ProductionRuntimeLoader {
  final ProductionAppMetadata metadata;
  int calls = 0;

  _RuntimeLoader(this.metadata);

  @override
  Future<ProductionAppMetadata> load() async {
    calls++;
    return metadata;
  }
}

final class _ThrowingRuntimeLoader implements ProductionRuntimeLoader {
  @override
  Future<ProductionAppMetadata> load() {
    throw StateError('metadata unavailable');
  }
}

final class _StaticUpdaterFactory implements ProductionUpdaterFactory {
  final _RecordingExecutor? executor;
  int calls = 0;

  _StaticUpdaterFactory({this.executor});

  @override
  AppUpdater create({
    required ProductionUpdateConfiguration configuration,
    required ProductionAppMetadata metadata,
  }) {
    calls++;
    final action = OpenStoreAction(
      store: StoreKind.googlePlay,
      storeUrl: Uri.parse(
        'https://play.google.com/store/apps/details?id=com.example.app',
      ),
    );
    return AppUpdater(
      source: UpdateSource.staticManifest(
        manifest: UpdateManifest(
          schemaVersion: 3,
          appId: 'com.example.app',
          channel: 'stable',
          releases: [
            UpdateCandidate(
              version: '2.0.0',
              buildNumber: '20',
              channel: 'stable',
              platform: TargetPlatform.android,
              architecture: 'arm64',
              releaseNotes: 'Production page fixture.',
              policy: const UpdatePolicy(),
              actions: [action],
            ),
          ],
        ),
      ),
      selector: const UpdateSelector(
        installedVersion: '1.0.0',
        installedBuildNumber: '10',
        platform: TargetPlatform.android,
        architecture: 'arm64',
        channel: 'stable',
      ),
      executors: [if (executor case final value?) value],
      distributionPolicy: configuration.distributionPolicy,
    );
  }
}

final class _RecordingExecutor implements UpdateActionExecutor {
  int calls = 0;

  @override
  bool supports(UpdateAction action) => action is OpenStoreAction;

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    calls++;
    return const UpdateActionResult.success();
  }
}
