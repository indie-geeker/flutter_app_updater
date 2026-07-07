import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdater.performStream', () {
    test('falls back to started and completed events for normal executors',
        () async {
      final action = OpenStoreAction(
        store: StoreKind.googlePlay,
        storeUrl: Uri.parse(
          'https://play.google.com/store/apps/details?id=com.example.app',
        ),
      );
      final executor = _RecordingExecutor(
        supportsAction: (candidate) => candidate is OpenStoreAction,
      );
      final updater = _updater(executors: [executor]);

      final events = await updater.performStream(action).toList();

      expect(events, hasLength(2));
      expect(events[0], isA<UpdateActionStarted>());
      expect(events[1], isA<UpdateActionCompleted>());
      expect((events[1] as UpdateActionCompleted).result.isSuccess, isTrue);
      expect(executor.performedActions, [same(action)]);
    });

    test('delegates to streaming executors when available', () async {
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
      );
      final executor = _StreamingRecordingExecutor();
      final updater = _updater(executors: [executor]);

      final events = await updater.performStream(action).toList();

      expect(events.whereType<UpdateActionProgress>(), hasLength(1));
      expect(events.last, isA<UpdateActionCompleted>());
      expect(executor.streamedActions, [same(action)]);
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

class _RecordingExecutor implements UpdateActionExecutor {
  final bool Function(UpdateAction action) supportsAction;
  final performedActions = <UpdateAction>[];

  _RecordingExecutor({
    required this.supportsAction,
  });

  @override
  bool supports(UpdateAction action) => supportsAction(action);

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    performedActions.add(action);
    return const UpdateActionResult.success();
  }
}

class _StreamingRecordingExecutor implements StreamingUpdateActionExecutor {
  final streamedActions = <UpdateAction>[];

  @override
  bool supports(UpdateAction action) => action is DownloadPackageAction;

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    streamedActions.add(action);
    return const UpdateActionResult.success();
  }

  @override
  Stream<UpdateActionEvent> performStream(
    UpdateAction action, {
    UpdateActionCancelToken? cancelToken,
  }) async* {
    streamedActions.add(action);
    yield UpdateActionStarted(action);
    yield UpdateActionProgress(
      action: action,
      downloadedBytes: 5,
      totalBytes: 10,
    );
    yield const UpdateActionCompleted(UpdateActionResult.success());
  }
}
