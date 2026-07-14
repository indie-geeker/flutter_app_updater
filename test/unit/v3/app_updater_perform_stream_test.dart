import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppUpdater.performStream', () {
    test('wraps a regular executor with one start and one completion',
        () async {
      final action = OpenStoreAction(
        store: StoreKind.googlePlay,
        storeUrl: Uri.parse('https://example.com/store'),
      );
      final updater = _updater([_RegularExecutor()]);

      final events = await updater.performStream(action).toList();

      expect(events.whereType<UpdateActionStarted>(), hasLength(1));
      expect(events.whereType<UpdateActionCompleted>(), hasLength(1));
      expect(events.last, isA<UpdateActionCompleted>());
    });

    test('delegates progress and cancellation to a streaming executor',
        () async {
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
      );
      final token = UpdateActionCancelToken();
      final executor = _StreamingExecutor();
      final updater = _updater([executor]);

      final events =
          await updater.performStream(action, cancelToken: token).toList();

      expect(events.whereType<UpdateActionProgress>(), hasLength(1));
      expect(events.whereType<UpdateActionCompleted>(), hasLength(1));
      expect(executor.receivedToken, same(token));
      expect(token.isCanceled, isFalse);
    });

    test('performRecommendedStream uses the recommended action', () async {
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
      );
      final updater = _updater([_StreamingExecutor()]);
      final prepared = PreparedUpdateAvailable(
        candidate: UpdateCandidate(
          version: '2.0.0',
          channel: 'stable',
          platform: TargetPlatform.android,
          releaseNotes: 'Fixes',
          policy: const UpdatePolicy(),
          actions: [action],
        ),
        recommendedAction: action,
        actions: [action],
        isRequired: false,
      );

      final events = await updater.performRecommendedStream(prepared).toList();

      expect((events.first as UpdateActionStarted).action, same(action));
      expect(events.last, isA<UpdateActionCompleted>());
    });

    test('adds a terminal failure when a streaming executor omits it',
        () async {
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
      );
      final events = await _updater([_NoTerminalExecutor()])
          .performStream(action)
          .toList();

      expect(events.whereType<UpdateActionStarted>(), hasLength(1));
      expect(events.whereType<UpdateActionCompleted>(), hasLength(1));
      expect(
        (events.last as UpdateActionCompleted).result.code,
        UpdateErrorCode.actionFailed,
      );
    });

    test('suppresses duplicate starts and terminal events', () async {
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
      );
      final events = await _updater([_DuplicateTerminalExecutor()])
          .performStream(action)
          .toList();

      expect(events.whereType<UpdateActionStarted>(), hasLength(1));
      expect(events.whereType<UpdateActionCompleted>(), hasLength(1));
    });

    test('maps thrown executor failures to one terminal event', () async {
      final action = OpenStoreAction(
        store: StoreKind.googlePlay,
        storeUrl: Uri.parse('https://example.com/store'),
      );
      final events =
          await _updater([_ThrowingExecutor()]).performStream(action).toList();

      expect(events.whereType<UpdateActionCompleted>(), hasLength(1));
      expect(
        (events.last as UpdateActionCompleted).result.code,
        UpdateErrorCode.actionFailed,
      );
    });
  });
}

AppUpdater _updater(List<UpdateActionExecutor> executors) {
  return AppUpdater(
    source: UpdateSource.manifest(
      manifestUrl: Uri.parse('https://example.com/manifest.json'),
      expectedAppId: 'com.example.app',
    ),
    executors: executors,
  );
}

class _RegularExecutor implements UpdateActionExecutor {
  @override
  bool supports(UpdateAction action) => action is OpenStoreAction;

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    return const UpdateActionResult.success();
  }
}

class _StreamingExecutor implements StreamingUpdateActionExecutor {
  UpdateActionCancelToken? receivedToken;

  @override
  bool supports(UpdateAction action) => action is DownloadPackageAction;

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    return const UpdateActionResult.success();
  }

  @override
  Stream<UpdateActionEvent> performStream(
    UpdateAction action, {
    UpdateActionCancelToken? cancelToken,
  }) async* {
    receivedToken = cancelToken;
    yield UpdateActionStarted(action);
    yield UpdateActionProgress(
      action: action,
      downloadedBytes: 1,
      totalBytes: 2,
    );
    yield const UpdateActionCompleted(UpdateActionResult.success());
  }
}

class _NoTerminalExecutor extends _StreamingExecutor {
  @override
  Stream<UpdateActionEvent> performStream(
    UpdateAction action, {
    UpdateActionCancelToken? cancelToken,
  }) async* {
    yield UpdateActionStarted(action);
    yield UpdateActionProgress(
      action: action,
      downloadedBytes: 1,
      totalBytes: 2,
    );
  }
}

class _DuplicateTerminalExecutor extends _StreamingExecutor {
  @override
  Stream<UpdateActionEvent> performStream(
    UpdateAction action, {
    UpdateActionCancelToken? cancelToken,
  }) async* {
    yield UpdateActionStarted(action);
    yield const UpdateActionCompleted(UpdateActionResult.success());
    yield const UpdateActionCompleted(UpdateActionResult.success());
  }
}

class _ThrowingExecutor implements UpdateActionExecutor {
  @override
  bool supports(UpdateAction action) => true;

  @override
  Future<UpdateActionResult> perform(UpdateAction action) {
    throw StateError('executor failed');
  }
}
