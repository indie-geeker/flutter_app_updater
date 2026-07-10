import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater_example/demo/demo_scenario.dart';
import 'package:flutter_app_updater_example/demo/update_demo_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('checks a configured scenario and exposes an available update',
      () async {
    final controller = UpdateDemoController(
      scenario: DemoScenario.defaults().copyWith(
        executionDuration: Duration.zero,
      ),
    );
    addTearDown(controller.dispose);

    await controller.checkForUpdate();

    expect(controller.phase, DemoPhase.updateAvailable);
    expect(controller.preparedUpdate?.candidate.version, '2.0.0');
    expect(controller.preparedUpdate?.isRequired, isFalse);
  });

  test('reports up to date through the real selector path', () async {
    final controller = UpdateDemoController(
      scenario: DemoScenario.defaults().copyWith(updateAvailable: false),
    );
    addTearDown(controller.dispose);

    await controller.checkForUpdate();

    expect(controller.phase, DemoPhase.upToDate);
    expect(controller.preparedUpdate, isNull);
  });

  test('uses the prepared result as the source of required policy', () async {
    final controller = UpdateDemoController(
      scenario: DemoScenario.defaults().copyWith(
        policyLevel: UpdatePolicyLevel.recommended,
        minSupportedVersion: '1.5.0',
      ),
    );
    addTearDown(controller.dispose);

    await controller.checkForUpdate();

    expect(controller.preparedUpdate?.isRequired, isTrue);
  });

  test('executes a prepared update to success with progress', () async {
    final controller = UpdateDemoController(
      scenario: DemoScenario.defaults().copyWith(
        executionDuration: Duration.zero,
      ),
    );
    addTearDown(controller.dispose);
    await controller.checkForUpdate();

    await controller.performRecommended();

    expect(controller.phase, DemoPhase.succeeded);
    expect(controller.progress, 1);
    expect(controller.downloadedBytes, controller.totalBytes);
  });

  test('exposes the configured structured execution failure', () async {
    final controller = UpdateDemoController(
      scenario: DemoScenario.defaults().copyWith(
        outcome: DemoOutcome.hashMismatch,
        executionDuration: Duration.zero,
      ),
    );
    addTearDown(controller.dispose);
    await controller.checkForUpdate();

    await controller.performRecommended();

    expect(controller.phase, DemoPhase.failed);
    expect(controller.errorCode, UpdateErrorCode.packageHashMismatch);
  });

  test('cancels an active simulated update', () async {
    final controller = UpdateDemoController(
      scenario: DemoScenario.defaults().copyWith(
        executionDuration: const Duration(milliseconds: 80),
      ),
    );
    addTearDown(controller.dispose);
    await controller.checkForUpdate();

    final execution = controller.performRecommended();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    controller.cancel();
    await execution;

    expect(controller.phase, DemoPhase.canceled);
    expect(controller.errorCode, UpdateErrorCode.actionCanceled);
  });

  test('reset prevents stale execution events from changing idle state',
      () async {
    final controller = UpdateDemoController(
      scenario: DemoScenario.defaults().copyWith(
        executionDuration: const Duration(milliseconds: 80),
      ),
    );
    addTearDown(controller.dispose);
    await controller.checkForUpdate();

    final execution = controller.performRecommended();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    controller.reset();
    await execution;

    expect(controller.phase, DemoPhase.idle);
    expect(controller.scenario.installedVersion, '1.0.0');
    expect(controller.preparedUpdate, isNull);
    expect(controller.errorCode, isNull);
  });

  test('deferring an optional update returns to an editable idle state',
      () async {
    final controller = UpdateDemoController(
      scenario: DemoScenario.defaults(),
    );
    addTearDown(controller.dispose);
    await controller.checkForUpdate();

    controller.deferUpdate();

    expect(controller.phase, DemoPhase.idle);
    expect(controller.preparedUpdate, isNull);
    expect(controller.isBusy, isFalse);
  });
}
