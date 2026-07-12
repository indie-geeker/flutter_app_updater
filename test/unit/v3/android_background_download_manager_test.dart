import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app_updater/src/actions/update_action.dart';
import 'package:flutter_app_updater/src/background/android_background_download_manager.dart';
import 'package:flutter_app_updater/src/background/background_download_task.dart';
import 'package:flutter_app_updater/src/channel/flutter_app_updater_platform_interface.dart';
import 'package:flutter_app_updater/src/download/package_downloader.dart';
import 'package:flutter_app_updater/src/models/update_error_code.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeBackgroundPlatform platform;
  late AndroidBackgroundDownloadManager manager;
  late FlutterAppUpdaterPlatform previousPlatform;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    previousPlatform = FlutterAppUpdaterPlatform.instance;
    platform = _FakeBackgroundPlatform();
    FlutterAppUpdaterPlatform.instance = platform;
    manager = AndroidBackgroundDownloadManager();
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    FlutterAppUpdaterPlatform.instance = previousPlatform;
    await platform.dispose();
  });

  group('start', () {
    test('normalizes a valid APK action before the platform call', () async {
      platform.startResult = _task(id: 'task-start', revision: 1);
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/update.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: 1024,
        sha256: 'ABCDEF0123456789' * 4,
      );

      final task = await manager.start(action);

      expect(task.id, 'task-start');
      expect(platform.startCalls.single, (
        packageUrl: Uri.parse('https://example.com/update.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: 1024,
        sha256: ('ABCDEF0123456789' * 4).toLowerCase(),
      ));
    });

    test('allows HTTP only for loopback hosts', () async {
      platform.startResult = _task(id: 'loopback', revision: 1);

      await manager.start(_action(url: 'http://127.0.0.1:8080/update.apk'));
      await manager.start(_action(url: 'http://[::1]:8080/update.apk'));
      await manager.start(_action(url: 'http://localhost:8080/update.apk'));

      expect(platform.startCalls, hasLength(3));
    });

    test('rejects invalid actions without calling the platform', () async {
      final invalidActions = <DownloadPackageAction>[
        DownloadPackageAction(
          packageUrl: Uri.parse('https://example.com/update.aab'),
          packageType: PackageType.aab,
          packageSizeBytes: 1,
          sha256: 'a' * 64,
        ),
        DownloadPackageAction(
          packageUrl: Uri.parse('https://example.com/update.apk'),
          packageType: PackageType.apk,
          sha256: 'a' * 64,
        ),
        _action(size: 0),
        _action(size: PackageDownloader.defaultMaxDownloadBytes + 1),
        _action(sha256: 'not-a-sha'),
        _action(url: 'http://example.com/update.apk'),
        _action(url: 'ftp://localhost/update.apk'),
      ];

      for (final action in invalidActions) {
        await expectLater(manager.start(action), throwsArgumentError);
      }

      expect(platform.startCalls, isEmpty);
    });
  });

  test('validates safe task IDs before every platform operation', () async {
    for (final taskId in ['', ' ', '../task', 'task/child', 'task\nnext']) {
      await expectLater(manager.get(taskId), throwsArgumentError);
      await expectLater(manager.resume(taskId), throwsArgumentError);
      await expectLater(manager.cancel(taskId), throwsArgumentError);
      await expectLater(manager.remove(taskId), throwsArgumentError);
      await expectLater(
          manager.createInstallAction(taskId), throwsArgumentError);
      expect(() => manager.watch(taskId), throwsArgumentError);
    }

    expect(platform.taskOperationCalls, isEmpty);
  });

  test(
      'delegates snapshots, filtering, cancellation, removal, and install prep',
      () async {
    final active = _task(id: 'active', revision: 1);
    final completed = _task(
      id: 'completed',
      revision: 2,
      status: BackgroundDownloadStatus.completed,
      filePath: '/downloads/completed.apk',
    );
    final failed = _task(
      id: 'failed',
      revision: 2,
      status: BackgroundDownloadStatus.failed,
    );
    final canceled = _task(
      id: 'canceled',
      revision: 2,
      status: BackgroundDownloadStatus.canceled,
    );
    platform.tasks['active'] = active;
    platform.resumeResult = _task(id: 'active', revision: 2);
    platform.cancelResult = canceled;
    platform.listResult = [active, completed, failed, canceled];
    platform.installPath = '/downloads/completed.apk';

    expect(await manager.get('active'), same(active));
    expect((await manager.listUnfinished()).map((task) => task.id), ['active']);
    expect((await manager.resume('active')).revision, 2);
    expect((await manager.cancel('active')).status,
        BackgroundDownloadStatus.canceled);
    await manager.remove('completed');
    final installAction = await manager.createInstallAction('completed');

    expect(installAction.packagePath, '/downloads/completed.apk');
    expect(installAction.packageType, PackageType.apk);
    expect(platform.removedTaskIds, ['completed']);
  });

  test('maps missing plugin and typed platform errors with raw details',
      () async {
    platform.getFailure = MissingPluginException('Background API missing.');

    await expectLater(
      manager.get('task-1'),
      throwsA(
        isA<BackgroundDownloadException>()
            .having((error) => error.code, 'code',
                UpdateErrorCode.backgroundDownloadUnavailable)
            .having((error) => error.message, 'message',
                contains('Background API missing')),
      ),
    );

    platform.getFailure = PlatformException(
      code: 'BACKGROUND_DOWNLOAD_NOT_FOUND',
      message: 'No such durable task.',
    );
    await expectLater(
      manager.get('task-1'),
      throwsA(
        isA<BackgroundDownloadException>()
            .having((error) => error.code, 'code',
                UpdateErrorCode.backgroundDownloadNotFound)
            .having((error) => error.nativeCode, 'nativeCode',
                'BACKGROUND_DOWNLOAD_NOT_FOUND')
            .having(
                (error) => error.message, 'message', 'No such durable task.'),
      ),
    );
  });

  test('rejects all operations on non-Android platforms without platform calls',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await expectLater(
      manager.start(_action()),
      throwsA(
        isA<BackgroundDownloadException>().having(
          (error) => error.code,
          'code',
          UpdateErrorCode.backgroundDownloadUnavailable,
        ),
      ),
    );
    await expectLater(
        manager.list(), throwsA(isA<BackgroundDownloadException>()));
    expect(
      () => manager.watch('task-1'),
      throwsA(isA<BackgroundDownloadException>()),
    );
    expect(platform.startCalls, isEmpty);
    expect(platform.watchBackgroundDownloadsCalls, 0);
  });

  group('watch', () {
    test('terminal snapshot emits once and closes', () async {
      platform.tasks['done'] = _task(
        id: 'done',
        revision: 4,
        status: BackgroundDownloadStatus.completed,
        filePath: '/downloads/done.apk',
      );

      final events = await manager.watch('done').toList();

      expect(events, hasLength(1));
      expect(events.single.revision, 4);
    });

    test('subscribes before get and preserves an event arriving in the race',
        () async {
      platform.getCompleters['race'] = Completer<BackgroundDownloadTask>();
      final eventsFuture = manager.watch('race').take(2).toList();
      await pumpEventQueue();

      expect(platform.watchBackgroundDownloadsCalls, 1);
      expect(platform.getTaskIds, ['race']);
      platform.events.add(_task(id: 'race', revision: 2));
      platform.getCompleters['race']!.complete(_task(id: 'race', revision: 1));

      final events = await eventsFuture;
      expect(events.map((task) => task.revision), [1, 2]);
    });

    test('reconciles a buffered newer terminal before closing', () async {
      platform.getCompleters['terminal-race'] =
          Completer<BackgroundDownloadTask>();
      final eventsFuture = manager.watch('terminal-race').toList();
      await pumpEventQueue();

      platform.events.add(_task(
        id: 'terminal-race',
        revision: 4,
        status: BackgroundDownloadStatus.completed,
        filePath: '/downloads/revision-4.apk',
      ));
      platform.getCompleters['terminal-race']!.complete(_task(
        id: 'terminal-race',
        revision: 3,
        status: BackgroundDownloadStatus.completed,
        filePath: '/downloads/revision-3.apk',
      ));

      final events = await eventsFuture;
      expect(events.map((task) => task.revision), [4]);
      expect(events.single.filePath, '/downloads/revision-4.apk');
      expect(platform.eventListenerCancelCount, 1);
    });

    test('drops buffered revisions older than the returned snapshot', () async {
      platform.getCompleters['stale-race'] =
          Completer<BackgroundDownloadTask>();
      final eventsFuture = manager.watch('stale-race').toList();
      await pumpEventQueue();

      platform.events.add(_task(id: 'stale-race', revision: 2));
      platform.events.add(_task(
        id: 'stale-race',
        revision: 4,
        status: BackgroundDownloadStatus.completed,
        filePath: '/downloads/revision-4.apk',
      ));
      platform.getCompleters['stale-race']!
          .complete(_task(id: 'stale-race', revision: 3));

      final events = await eventsFuture;
      expect(events.map((task) => task.revision), [3, 4]);
    });

    test('drops stale and duplicate revisions and closes after terminal',
        () async {
      platform.tasks['ordered'] = _task(id: 'ordered', revision: 3);
      final eventsFuture = manager.watch('ordered').toList();
      await pumpEventQueue();

      platform.events.add(_task(id: 'ordered', revision: 2));
      platform.events.add(_task(id: 'ordered', revision: 3));
      platform.events.add(_task(id: 'ordered', revision: 4));
      platform.events.add(_task(
        id: 'ordered',
        revision: 5,
        status: BackgroundDownloadStatus.completed,
        filePath: '/downloads/ordered.apk',
      ));
      platform.events.add(_task(id: 'ordered', revision: 6));

      final events = await eventsFuture;
      expect(events.map((task) => task.revision), [3, 4, 5]);
    });

    test('two task watchers share one global platform stream', () async {
      platform.tasks['one'] = _task(id: 'one', revision: 1);
      platform.tasks['two'] = _task(id: 'two', revision: 1);

      final oneFuture = manager.watch('one').take(2).toList();
      final twoFuture = manager.watch('two').take(2).toList();
      await pumpEventQueue();
      platform.events.add(_task(id: 'one', revision: 2));
      platform.events.add(_task(id: 'two', revision: 2));

      expect((await oneFuture).map((task) => task.id), ['one', 'one']);
      expect((await twoFuture).map((task) => task.id), ['two', 'two']);
      expect(platform.watchBackgroundDownloadsCalls, 1);
    });

    test('terminal watcher closes without making global stream unusable',
        () async {
      platform.tasks['first'] = _task(id: 'first', revision: 1);
      final firstFuture = manager.watch('first').toList();
      await pumpEventQueue();
      platform.events.add(_task(
        id: 'first',
        revision: 2,
        status: BackgroundDownloadStatus.completed,
        filePath: '/downloads/first.apk',
      ));
      expect((await firstFuture).map((task) => task.revision), [1, 2]);

      platform.tasks['second'] = _task(id: 'second', revision: 1);
      final secondFuture = manager.watch('second').take(2).toList();
      await pumpEventQueue();
      platform.events.add(_task(id: 'second', revision: 2));

      expect((await secondFuture).map((task) => task.revision), [1, 2]);
      expect(platform.watchBackgroundDownloadsCalls, 1);
    });

    test('canceling a Dart subscription never cancels the native task',
        () async {
      platform.tasks['active'] = _task(id: 'active', revision: 1);
      final subscription = manager.watch('active').listen((_) {});
      await pumpEventQueue();

      await subscription.cancel();

      expect(platform.canceledTaskIds, isEmpty);
    });

    test('get failure maps error, closes, and cancels event subscription',
        () async {
      platform.getFailure = PlatformException(
        code: 'BACKGROUND_DOWNLOAD_NOT_FOUND',
        message: 'Missing task.',
      );
      final errors = <Object>[];
      final done = Completer<void>();

      manager.watch('missing').listen(
            (_) {},
            onError: errors.add,
            onDone: done.complete,
          );
      await done.future;

      expect(
        errors.single,
        isA<BackgroundDownloadException>()
            .having((error) => error.code, 'code',
                UpdateErrorCode.backgroundDownloadNotFound)
            .having((error) => error.nativeCode, 'nativeCode',
                'BACKGROUND_DOWNLOAD_NOT_FOUND'),
      );
      expect(platform.activeEventListeners, 0);
      expect(platform.eventListenerCancelCount, 1);
    });

    test('event error maps, closes, and cancels event subscription', () async {
      platform.tasks['event-error'] = _task(id: 'event-error', revision: 1);
      final errors = <Object>[];
      final done = Completer<void>();
      manager.watch('event-error').listen(
            (_) {},
            onError: errors.add,
            onDone: done.complete,
          );
      await pumpEventQueue();

      platform.events.addError(PlatformException(
        code: 'BACKGROUND_STORAGE_UNAVAILABLE',
        message: 'Storage detached.',
      ));
      await done.future;

      expect(
        errors.single,
        isA<BackgroundDownloadException>()
            .having((error) => error.code, 'code',
                UpdateErrorCode.backgroundStorageUnavailable)
            .having((error) => error.nativeCode, 'nativeCode',
                'BACKGROUND_STORAGE_UNAVAILABLE'),
      );
      expect(platform.activeEventListeners, 0);
      expect(platform.eventListenerCancelCount, 1);
    });

    test('global event completion errors and closes an active watcher',
        () async {
      platform.tasks['event-done'] = _task(id: 'event-done', revision: 1);
      final received = <BackgroundDownloadTask>[];
      final errors = <Object>[];
      final done = Completer<void>();
      manager.watch('event-done').listen(
            received.add,
            onError: errors.add,
            onDone: done.complete,
          );
      await pumpEventQueue();
      expect(received.map((task) => task.revision), [1]);

      await platform.events.close();
      await done.future.timeout(const Duration(milliseconds: 200));

      expect(
        errors.single,
        isA<BackgroundDownloadException>().having(
          (error) => error.code,
          'code',
          UpdateErrorCode.backgroundDownloadUnavailable,
        ),
      );
      expect(platform.activeEventListeners, 0);
      expect(platform.eventListenerCancelCount, 1);
    });

    test('cancel while get is pending cleans up and ignores late snapshot',
        () async {
      platform.getCompleters['pending'] = Completer<BackgroundDownloadTask>();
      final received = <BackgroundDownloadTask>[];
      final subscription = manager.watch('pending').listen(received.add);
      await pumpEventQueue();
      expect(platform.activeEventListeners, 1);

      await subscription.cancel();
      platform.getCompleters['pending']!
          .complete(_task(id: 'pending', revision: 1));
      await pumpEventQueue();

      expect(received, isEmpty);
      expect(platform.activeEventListeners, 0);
      expect(platform.eventListenerCancelCount, 1);
      expect(platform.canceledTaskIds, isEmpty);
    });
  });
}

DownloadPackageAction _action({
  String url = 'https://example.com/update.apk',
  int size = 1024,
  String? sha256,
}) {
  return DownloadPackageAction(
    packageUrl: Uri.parse(url),
    packageType: PackageType.apk,
    packageSizeBytes: size,
    sha256: sha256 ?? 'a' * 64,
  );
}

BackgroundDownloadTask _task({
  required String id,
  required int revision,
  BackgroundDownloadStatus status = BackgroundDownloadStatus.running,
  String? filePath,
}) {
  return BackgroundDownloadTask(
    id: id,
    revision: revision,
    status: status,
    downloadedBytes: revision * 100,
    totalBytes: 1000,
    filePath: filePath,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1000 + revision),
  );
}

class _FakeBackgroundPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements FlutterAppUpdaterPlatform {
  late final StreamController<BackgroundDownloadTask> events;
  final tasks = <String, BackgroundDownloadTask>{};
  final getCompleters = <String, Completer<BackgroundDownloadTask>>{};
  final startCalls = <({
    Uri packageUrl,
    PackageType packageType,
    int packageSizeBytes,
    String sha256,
  })>[];
  final getTaskIds = <String>[];
  final resumedTaskIds = <String>[];
  final canceledTaskIds = <String>[];
  final removedTaskIds = <String>[];
  final preparedTaskIds = <String>[];
  int watchBackgroundDownloadsCalls = 0;
  int activeEventListeners = 0;
  int eventListenerCancelCount = 0;
  Object? getFailure;
  BackgroundDownloadTask? startResult;
  BackgroundDownloadTask? resumeResult;
  BackgroundDownloadTask? cancelResult;
  List<BackgroundDownloadTask> listResult = const [];
  String installPath = '/downloads/update.apk';

  _FakeBackgroundPlatform() {
    events = StreamController<BackgroundDownloadTask>.broadcast(
      sync: true,
      onListen: () => activeEventListeners += 1,
      onCancel: () {
        activeEventListeners -= 1;
        eventListenerCancelCount += 1;
      },
    );
  }

  Iterable<String> get taskOperationCalls => [
        ...getTaskIds,
        ...resumedTaskIds,
        ...canceledTaskIds,
        ...removedTaskIds,
        ...preparedTaskIds,
      ];

  @override
  Future<BackgroundDownloadTask> startBackgroundDownload({
    required Uri packageUrl,
    required PackageType packageType,
    required int packageSizeBytes,
    required String sha256,
  }) async {
    startCalls.add((
      packageUrl: packageUrl,
      packageType: packageType,
      packageSizeBytes: packageSizeBytes,
      sha256: sha256,
    ));
    return startResult ?? _task(id: 'started', revision: 1);
  }

  @override
  Future<BackgroundDownloadTask> getBackgroundDownload(String taskId) async {
    getTaskIds.add(taskId);
    final failure = getFailure;
    if (failure != null) {
      throw failure;
    }
    final completer = getCompleters[taskId];
    if (completer != null) {
      return completer.future;
    }
    return tasks[taskId] ?? _task(id: taskId, revision: 1);
  }

  @override
  Future<List<BackgroundDownloadTask>> listBackgroundDownloads() async =>
      listResult;

  @override
  Future<BackgroundDownloadTask> resumeBackgroundDownload(String taskId) async {
    resumedTaskIds.add(taskId);
    return resumeResult ?? _task(id: taskId, revision: 2);
  }

  @override
  Future<BackgroundDownloadTask> cancelBackgroundDownload(String taskId) async {
    canceledTaskIds.add(taskId);
    return cancelResult ??
        _task(
          id: taskId,
          revision: 2,
          status: BackgroundDownloadStatus.canceled,
        );
  }

  @override
  Future<void> removeBackgroundDownload(String taskId) async {
    removedTaskIds.add(taskId);
  }

  @override
  Future<String> prepareBackgroundDownloadInstall(String taskId) async {
    preparedTaskIds.add(taskId);
    return installPath;
  }

  @override
  Stream<BackgroundDownloadTask> watchBackgroundDownloads() {
    watchBackgroundDownloadsCalls += 1;
    return events.stream;
  }

  Future<void> dispose() => events.close();
}
