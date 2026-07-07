import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdater.performStream', () {
    test('delegates to streaming executors when supported', () async {
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
      );
      final executor = _StreamingExecutor(action);
      final updater = _updater(executors: [executor]);

      final events = await updater.performStream(action).toList();

      expect(events, [
        isA<UpdateActionStarted>()
            .having((event) => event.action, 'action', same(action)),
        isA<UpdateDownloadProgress>()
            .having((event) => event.receivedBytes, 'receivedBytes', 5)
            .having((event) => event.totalBytes, 'totalBytes', 10),
        isA<UpdateActionCompleted>().having(
          (event) => event.result.downloadedBytes,
          'downloadedBytes',
          10,
        ),
      ]);
      expect(executor.performedActions, isEmpty);
    });

    test('falls back to perform for non-streaming executors', () async {
      final action = OpenStoreAction(
        store: StoreKind.googlePlay,
        storeUrl: Uri.parse(
          'https://play.google.com/store/apps/details?id=com.example.app',
        ),
      );
      final executor = _FutureExecutor(action);
      final updater = _updater(executors: [executor]);

      final events = await updater.performStream(action).toList();

      expect(events, [
        isA<UpdateActionStarted>()
            .having((event) => event.action, 'action', same(action)),
        isA<UpdateActionCompleted>(),
      ]);
      expect(executor.performedActions, [same(action)]);
    });

    test('emits a structured failure when no executor supports the action',
        () async {
      const action = OpenAndroidMarketAction(
        market: AndroidMarketKind.huawei,
        targetPackageName: 'com.example.app',
      );
      final updater = _updater(executors: const []);

      final events = await updater.performStream(action).toList();

      expect(events, [
        isA<UpdateActionFailed>().having(
          (event) => event.result.code,
          'code',
          UpdateErrorCode.noSupportedAction,
        ),
      ]);
    });
  });
}

AppUpdater _updater({
  required List<UpdateActionExecutor> executors,
}) {
  return AppUpdater(
    source: UpdateSource.manifest(
      manifestUrl: Uri.parse('https://example.com/update.json'),
    ),
    executors: executors,
  );
}

class _FutureExecutor implements UpdateActionExecutor {
  final UpdateAction action;
  final performedActions = <UpdateAction>[];

  _FutureExecutor(this.action);

  @override
  bool supports(UpdateAction action) => identical(action, this.action);

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    performedActions.add(action);
    return const UpdateActionResult.success();
  }
}

class _StreamingExecutor implements StreamingUpdateActionExecutor {
  final UpdateAction action;
  final performedActions = <UpdateAction>[];

  _StreamingExecutor(this.action);

  @override
  bool supports(UpdateAction action) => identical(action, this.action);

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    performedActions.add(action);
    return const UpdateActionResult.success();
  }

  @override
  Stream<UpdateActionEvent> performStream(UpdateAction action) async* {
    yield UpdateActionStarted(action);
    yield const UpdateDownloadProgress(receivedBytes: 5, totalBytes: 10);
    yield const UpdateActionCompleted(
      UpdateActionResult.success(downloadedBytes: 10),
    );
  }
}
