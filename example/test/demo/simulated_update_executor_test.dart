import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater_example/demo/demo_scenario.dart';
import 'package:flutter_app_updater_example/demo/simulated_update_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DownloadAndInstallPackageAction action;

  setUp(() {
    action = DownloadAndInstallPackageAction(
      packageUrl: Uri.parse('https://download.example.invalid/app.apk'),
      packageType: PackageType.apk,
      packageSizeBytes: 100,
    );
  });

  test('emits start, four progress events, and one successful completion',
      () async {
    const executor = SimulatedUpdateExecutor(
      outcome: DemoOutcome.success,
      duration: Duration.zero,
      totalBytes: 100,
    );

    final events = await executor.performStream(action).toList();

    expect(events.first, isA<UpdateActionStarted>());
    expect(
      events
          .whereType<UpdateActionProgress>()
          .map((event) => event.downloadedBytes),
      [25, 50, 75, 100],
    );
    expect(events.whereType<UpdateActionCompleted>(), hasLength(1));
    expect(events.last, isA<UpdateActionCompleted>());
    expect((events.last as UpdateActionCompleted).result.isSuccess, isTrue);
  });

  test('perform returns the terminal stream result', () async {
    const executor = SimulatedUpdateExecutor(
      outcome: DemoOutcome.hashMismatch,
      duration: Duration.zero,
      totalBytes: 100,
    );

    final result = await executor.perform(action);

    expect(result.isSuccess, isFalse);
    expect(result.code, UpdateErrorCode.packageHashMismatch);
  });

  test('cancellation emits one structured terminal result', () async {
    final token = UpdateActionCancelToken();
    const executor = SimulatedUpdateExecutor(
      outcome: DemoOutcome.success,
      duration: Duration.zero,
      totalBytes: 100,
    );
    final events = <UpdateActionEvent>[];

    await for (final event in executor.performStream(
      action,
      cancelToken: token,
    )) {
      events.add(event);
      if (event is UpdateActionProgress) {
        token.cancel();
      }
    }

    final completions = events.whereType<UpdateActionCompleted>().toList();
    expect(completions, hasLength(1));
    expect(completions.single.result.code, UpdateErrorCode.actionCanceled);
    expect(events.whereType<UpdateActionProgress>(), hasLength(1));
  });

  test('maps configured failures to existing public error codes', () async {
    final cases = <DemoOutcome, UpdateErrorCode>{
      DemoOutcome.downloadFailed: UpdateErrorCode.packageDownloadFailed,
      DemoOutcome.hashMismatch: UpdateErrorCode.packageHashMismatch,
      DemoOutcome.installPermissionRequired:
          UpdateErrorCode.packageInstallPermissionRequired,
      DemoOutcome.platformNotSupported: UpdateErrorCode.platformNotSupported,
      DemoOutcome.actionFailed: UpdateErrorCode.actionFailed,
    };

    for (final MapEntry(key: outcome, value: code) in cases.entries) {
      final executor = SimulatedUpdateExecutor(
        outcome: outcome,
        duration: Duration.zero,
        totalBytes: 100,
      );

      final events = await executor.performStream(action).toList();
      final completion = events.whereType<UpdateActionCompleted>().single;

      expect(completion.result.code, code, reason: outcome.name);
    }
  });

  test('supports every action produced by the demo', () {
    const executor = SimulatedUpdateExecutor(
      outcome: DemoOutcome.success,
      duration: Duration.zero,
      totalBytes: 100,
    );
    final actions = <UpdateAction>[
      OpenStoreAction(
        store: StoreKind.googlePlay,
        storeUrl: Uri.parse('https://store.example.invalid/app'),
      ),
      const OpenAndroidMarketAction(
        market: AndroidMarketKind.xiaomi,
        targetPackageName: 'com.example.app',
      ),
      action,
      OpenInstallerAction(
        installerUrl: Uri.parse('https://download.example.invalid/app.msix'),
        installerType: InstallerType.msix,
      ),
    ];

    expect(actions.every(executor.supports), isTrue);
  });
}
