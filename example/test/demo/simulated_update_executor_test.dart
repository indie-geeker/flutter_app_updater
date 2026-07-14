import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater_example/demo/demo_scenario.dart';
import 'package:flutter_app_updater_example/demo/simulated_update_executor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final download = DownloadPackageAction(
    packageUrl: Uri.parse('https://download.example.invalid/app.apk'),
    packageType: PackageType.apk,
    packageSizeBytes: 100,
    sha256: 'a' * 64,
  );
  const install = InstallPackageAction(
    packagePath: '/simulated/app.apk',
    packageType: PackageType.apk,
  );
  final combined = DownloadAndInstallPackageAction(
    packageUrl: Uri.parse('https://download.example.invalid/app.apk'),
    packageType: PackageType.apk,
    packageSizeBytes: 100,
    sha256: 'a' * 64,
  );
  final installer = OpenInstallerAction(
    installerUrl: Uri.parse('https://download.example.invalid/app.msix'),
    installerType: InstallerType.msix,
    installerSizeBytes: 100,
    sha256: 'a' * 64,
  );
  final store = OpenStoreAction(
    store: StoreKind.googlePlay,
    storeUrl: Uri.parse('https://play.google.com/store/apps/details?id=app'),
  );
  const market = OpenAndroidMarketAction(
    market: AndroidMarketKind.xiaomi,
    targetPackageName: 'com.example.app',
  );

  test('store and market actions emit only started and completed', () async {
    for (final action in [store, market]) {
      final executor = SimulatedUpdateExecutor(
        outcome: DemoOutcome.success,
        duration: Duration.zero,
        totalBytes: 100,
      );

      final events = await executor.performStream(action).toList();

      expect(
          events, [isA<UpdateActionStarted>(), isA<UpdateActionCompleted>()]);
      expect(events.whereType<UpdateActionProgress>(), isEmpty);
    }
  });

  test('only download-related actions emit transfer progress', () async {
    for (final action in [download, combined, installer]) {
      final executor = SimulatedUpdateExecutor(
        outcome: DemoOutcome.success,
        duration: Duration.zero,
        totalBytes: 100,
      );

      final events = await executor.performStream(action).toList();

      expect(
        events
            .whereType<UpdateActionProgress>()
            .map((event) => event.downloadedBytes),
        [25, 50, 75, 100],
        reason: action.runtimeType.toString(),
      );
      expect(events.whereType<UpdateActionCompleted>(), hasLength(1));
    }

    final installEvents = await SimulatedUpdateExecutor(
      outcome: DemoOutcome.success,
      duration: Duration.zero,
      totalBytes: 100,
    ).performStream(install).toList();
    expect(installEvents.whereType<UpdateActionProgress>(), isEmpty);
  });

  test('hash mismatch is available only for download-related actions',
      () async {
    for (final action in [download, combined, installer]) {
      expect(
        SimulatedUpdateExecutor.supportsOutcome(
          action,
          DemoOutcome.hashMismatch,
        ),
        isTrue,
      );
    }
    for (final action in [store, market, install]) {
      expect(
        SimulatedUpdateExecutor.supportsOutcome(
          action,
          DemoOutcome.hashMismatch,
        ),
        isFalse,
      );
    }
  });

  test('install permission is available only for installation actions',
      () async {
    for (final action in [install, combined]) {
      expect(
        SimulatedUpdateExecutor.supportsOutcome(
          action,
          DemoOutcome.installPermissionRequired,
        ),
        isTrue,
      );
    }
    for (final action in [store, market, download, installer]) {
      expect(
        SimulatedUpdateExecutor.supportsOutcome(
          action,
          DemoOutcome.installPermissionRequired,
        ),
        isFalse,
      );
    }
  });

  test('configured first attempt fails and second succeeds on same executor',
      () async {
    final executor = SimulatedUpdateExecutor(
      outcome: DemoOutcome.downloadFailed,
      duration: Duration.zero,
      totalBytes: 100,
      succeedOnRetry: true,
    );

    final first = await executor.perform(download);
    final second = await executor.perform(download);

    expect(first.code, UpdateErrorCode.packageDownloadFailed);
    expect(second.isSuccess, isTrue);
    expect(executor.attemptCount, 2);
  });

  test('cancellation emits one structured terminal result', () async {
    final token = UpdateActionCancelToken();
    final executor = SimulatedUpdateExecutor(
      outcome: DemoOutcome.success,
      duration: Duration.zero,
      totalBytes: 100,
    );
    final events = <UpdateActionEvent>[];

    await for (final event in executor.performStream(
      combined,
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

  test('supports every action produced by the demo', () {
    final executor = SimulatedUpdateExecutor(
      outcome: DemoOutcome.success,
      duration: Duration.zero,
      totalBytes: 100,
    );

    expect(
      [store, market, download, install, combined, installer]
          .every(executor.supports),
      isTrue,
    );
  });
}
