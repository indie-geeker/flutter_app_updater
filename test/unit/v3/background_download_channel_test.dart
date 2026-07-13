import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_app_updater/src/actions/update_action.dart';
import 'package:flutter_app_updater/src/background/background_download_task.dart';
import 'package:flutter_app_updater/src/channel/flutter_app_updater_method_channel.dart';
import 'package:flutter_app_updater/src/models/update_error_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('flutter_app_updater');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  test('uses exact method and event channel names', () {
    final platform = MethodChannelFlutterAppUpdater();

    expect(platform.methodChannel.name, 'flutter_app_updater');
    expect(
      platform.backgroundDownloadEventChannel.name,
      'flutter_app_updater/background_downloads',
    );
  });

  test('uses exact methods and payloads for every background operation',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'listBackgroundDownloads' => [_nativeTask(id: 'listed')],
        'prepareBackgroundDownloadInstall' => '/downloads/update.apk',
        'removeBackgroundDownload' => null,
        _ => _nativeTask(id: 'task-1'),
      };
    });
    final platform = MethodChannelFlutterAppUpdater();

    await platform.startBackgroundDownload(
      packageUrl: Uri.parse('https://example.com/update.apk'),
      packageType: PackageType.apk,
      packageSizeBytes: 2048,
      sha256: 'a' * 64,
    );
    await platform.getBackgroundDownload('task-1');
    await platform.listBackgroundDownloads();
    await platform.resumeBackgroundDownload('task-1');
    await platform.cancelBackgroundDownload('task-1');
    await platform.removeBackgroundDownload('task-1');
    expect(
      await platform.prepareBackgroundDownloadInstall('task-1'),
      '/downloads/update.apk',
    );

    expect(calls.map((call) => call.method), [
      'startBackgroundDownload',
      'getBackgroundDownload',
      'listBackgroundDownloads',
      'resumeBackgroundDownload',
      'cancelBackgroundDownload',
      'removeBackgroundDownload',
      'prepareBackgroundDownloadInstall',
    ]);
    expect(calls[0].arguments, {
      'packageUrl': 'https://example.com/update.apk',
      'packageType': 'apk',
      'packageSizeBytes': 2048,
      'sha256': 'a' * 64,
    });
    expect(calls[1].arguments, {'taskId': 'task-1'});
    expect(calls[2].arguments, isNull);
    for (final index in [3, 4, 5, 6]) {
      expect(calls[index].arguments, {'taskId': 'task-1'});
    }
  });

  test('install preparation only requests a verified path from native',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      return '/internal/flutter_app_updater/background/task-1/artifact.apk';
    });

    final path = await MethodChannelFlutterAppUpdater()
        .prepareBackgroundDownloadInstall('task-1');

    expect(
      path,
      '/internal/flutter_app_updater/background/task-1/artifact.apk',
    );
    expect(calls, hasLength(1));
    expect(calls.single.method, 'prepareBackgroundDownloadInstall');
    expect(calls.single.arguments, {'taskId': 'task-1'});
    expect(calls.where((call) => call.method == 'installApp'), isEmpty);
  });

  test('strict decoder accepts large num values from StandardMessageCodec',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (_) async {
      return _nativeTask(
        id: 'large',
        revision: 4294967301.0,
        downloadedBytes: 5368709120.0,
        totalBytes: 6442450944.0,
        createdAtEpochMs: 4294967301000.0,
        updatedAtEpochMs: 4294967302000.0,
      );
    });

    final task =
        await MethodChannelFlutterAppUpdater().getBackgroundDownload('large');

    expect(task.revision, 4294967301);
    expect(task.downloadedBytes, 5368709120);
    expect(task.totalBytes, 6442450944);
    expect(task.createdAt.millisecondsSinceEpoch, 4294967301000);
    expect(task.updatedAt.millisecondsSinceEpoch, 4294967302000);
  });

  test('unknown status becomes a safe failed task without throwing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (_) async {
      return _nativeTask(id: 'unknown-status', status: 'teleported');
    });

    final task = await MethodChannelFlutterAppUpdater()
        .getBackgroundDownload('unknown-status');

    expect(task.status, BackgroundDownloadStatus.failed);
    expect(task.failure?.code, UpdateErrorCode.actionFailed);
    expect(task.failure?.nativeCode, 'teleported');
  });

  test('unknown failure code preserves raw native code and message', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (_) async {
      return _nativeTask(
        id: 'unknown-error',
        status: 'failed',
        errorCode: 'OEM_DOWNLOAD_BROKEN',
        errorMessage: 'OEM service stopped.',
      );
    });

    final task = await MethodChannelFlutterAppUpdater()
        .getBackgroundDownload('unknown-error');

    expect(task.status, BackgroundDownloadStatus.failed);
    expect(task.failure?.code, UpdateErrorCode.actionFailed);
    expect(task.failure?.nativeCode, 'OEM_DOWNLOAD_BROKEN');
    expect(task.failure?.message, 'OEM service stopped.');
  });

  test('completed task without a nonblank path becomes a safe failed task',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (_) async {
      return _nativeTask(
          id: 'invalid-complete', status: 'completed', filePath: ' ');
    });

    final task = await MethodChannelFlutterAppUpdater()
        .getBackgroundDownload('invalid-complete');

    expect(task.status, BackgroundDownloadStatus.failed);
    expect(task.failure?.code, UpdateErrorCode.actionFailed);
    expect(task.filePath, isNull);
  });

  test('out-of-range epoch data becomes a safe failed task', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (_) async {
      return _nativeTask(
        id: 'invalid-date',
        createdAtEpochMs: 9223372036854775807,
      );
    });

    final task = await MethodChannelFlutterAppUpdater()
        .getBackgroundDownload('invalid-date');

    expect(task.status, BackgroundDownloadStatus.failed);
    expect(task.failure?.code, UpdateErrorCode.actionFailed);
  });

  test('method and event results use the same strict decoder', () async {
    final controller = StreamController<dynamic>.broadcast(sync: true);
    final eventChannel = _CountingEventChannel(controller.stream);
    final platform = MethodChannelFlutterAppUpdater(
      backgroundDownloadEventChannel: eventChannel,
    );
    final first = platform.watchBackgroundDownloads();
    final second = platform.watchBackgroundDownloads();

    final firstEvent = first.first;
    final secondEvent = second.first;
    controller.add(_nativeTask(id: 'event-task', status: 'mystery'));

    expect((await firstEvent).status, BackgroundDownloadStatus.failed);
    expect((await secondEvent).failure?.nativeCode, 'mystery');
    expect(eventChannel.receiveCalls, 1);
    await controller.close();
  });
}

Map<String, Object?> _nativeTask({
  required String id,
  Object revision = 1,
  String status = 'running',
  Object downloadedBytes = 256,
  Object? totalBytes = 1024,
  String? filePath,
  String? errorCode,
  String? errorMessage,
  String? nativeErrorCode,
  Object createdAtEpochMs = 1700000000000,
  Object updatedAtEpochMs = 1700000001000,
}) {
  return {
    'id': id,
    'revision': revision,
    'status': status,
    'downloadedBytes': downloadedBytes,
    'totalBytes': totalBytes,
    'filePath': filePath,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
    'nativeErrorCode': nativeErrorCode,
    'createdAtEpochMs': createdAtEpochMs,
    'updatedAtEpochMs': updatedAtEpochMs,
  };
}

class _CountingEventChannel extends EventChannel {
  final Stream<dynamic> stream;
  int receiveCalls = 0;

  _CountingEventChannel(this.stream) : super('test/background_downloads');

  @override
  Stream<dynamic> receiveBroadcastStream([dynamic arguments]) {
    receiveCalls += 1;
    return stream;
  }
}
