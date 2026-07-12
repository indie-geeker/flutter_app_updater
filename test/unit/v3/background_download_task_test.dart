import 'package:flutter_app_updater/src/background/background_download_task.dart';
import 'package:flutter_app_updater/src/models/update_error_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackgroundDownloadStatus', () {
    test('defines every durable native status', () {
      expect(
        BackgroundDownloadStatus.values,
        [
          BackgroundDownloadStatus.queued,
          BackgroundDownloadStatus.running,
          BackgroundDownloadStatus.waitingForNetwork,
          BackgroundDownloadStatus.waitingForStorage,
          BackgroundDownloadStatus.pausedBySystem,
          BackgroundDownloadStatus.verifying,
          BackgroundDownloadStatus.completed,
          BackgroundDownloadStatus.failed,
          BackgroundDownloadStatus.canceled,
        ],
      );
    });
  });

  group('BackgroundDownloadTask', () {
    test('only completed, failed, and canceled tasks are terminal', () {
      for (final status in BackgroundDownloadStatus.values) {
        final task = _task(status: status);

        expect(
          task.isTerminal,
          {
            BackgroundDownloadStatus.completed,
            BackgroundDownloadStatus.failed,
            BackgroundDownloadStatus.canceled,
          }.contains(status),
          reason: status.name,
        );
      }
    });

    test('retains monotonic revision and StandardMessageCodec-sized integers',
        () {
      final task = BackgroundDownloadTask(
        id: 'task-large',
        revision: 4294967301,
        status: BackgroundDownloadStatus.running,
        downloadedBytes: 5368709120,
        totalBytes: 6442450944,
        createdAt: DateTime.fromMillisecondsSinceEpoch(4294967301000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(4294967302000),
      );

      expect(task.revision, 4294967301);
      expect(task.downloadedBytes, 5368709120);
      expect(task.totalBytes, 6442450944);
      expect(task.createdAt.millisecondsSinceEpoch, 4294967301000);
      expect(task.updatedAt.millisecondsSinceEpoch, 4294967302000);
    });

    test('failure and exception retain structured native details', () {
      const failure = BackgroundDownloadFailure(
        code: UpdateErrorCode.backgroundStorageUnavailable,
        message: 'Disk is full.',
        nativeCode: 'ENOSPC',
      );
      const exception = BackgroundDownloadException(
        code: UpdateErrorCode.backgroundStorageUnavailable,
        message: 'Disk is full.',
        nativeCode: 'ENOSPC',
      );

      expect(failure.code, UpdateErrorCode.backgroundStorageUnavailable);
      expect(failure.message, 'Disk is full.');
      expect(failure.nativeCode, 'ENOSPC');
      expect(exception.toString(), contains('BACKGROUND_STORAGE_UNAVAILABLE'));
      expect(exception.toString(), contains('ENOSPC'));
      expect(exception.toString(), contains('Disk is full.'));
    });
  });
}

BackgroundDownloadTask _task({required BackgroundDownloadStatus status}) {
  return BackgroundDownloadTask(
    id: 'task-${status.name}',
    revision: 1,
    status: status,
    downloadedBytes: 0,
    filePath:
        status == BackgroundDownloadStatus.completed ? '/tmp/update.apk' : null,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
  );
}
