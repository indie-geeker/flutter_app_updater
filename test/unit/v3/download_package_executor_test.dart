import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater/src/download/package_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DownloadPackageExecutor', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'download_package_executor_test_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('downloads package actions and returns file metadata', () async {
      final bytes = utf8.encode('package bytes');
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: bytes.length,
        sha256: crypto.sha256.convert(bytes).toString(),
      );
      final executor = DownloadPackageExecutor(
        downloadDirectory: tempDir.path,
        downloader: PackageDownloader(
          client: _FakePackageClient(
            PackageDownloadResponse(
              statusCode: 200,
              headers: const {},
              bytes: Stream.value(bytes),
            ),
          ),
        ),
      );

      final result = await executor.perform(action);

      expect(result.isSuccess, isTrue);
      expect(result.file, isNotNull);
      expect(result.file!.path, endsWith('${Platform.pathSeparator}app.apk'));
      expect(await result.file!.readAsBytes(), bytes);
      expect(result.downloadedBytes, bytes.length);
      expect(result.sha256, action.sha256);
    });

    test('maps package download failures to action failures', () async {
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: 42,
        sha256: 'a' * 64,
      );
      final executor = DownloadPackageExecutor(
        downloadDirectory: tempDir.path,
        downloader: PackageDownloader(
          client: _FakePackageClient(
            PackageDownloadResponse(
              statusCode: 500,
              headers: {},
              bytes: const Stream<List<int>>.empty(),
            ),
          ),
          retryStrategy: RetryStrategy.disabled,
        ),
      );

      final result = await executor.perform(action);

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.packageDownloadFailed);
    });

    test('downloads package actions with required integrity metadata',
        () async {
      final bytes = utf8.encode('package bytes');
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: bytes.length,
        sha256: crypto.sha256.convert(bytes).toString(),
      );
      final executor = DownloadPackageExecutor(
        downloadDirectory: tempDir.path,
        downloader: PackageDownloader(
          client: _FakePackageClient(
            PackageDownloadResponse(
              statusCode: 200,
              headers: const {},
              bytes: Stream.value(bytes),
            ),
          ),
        ),
      );

      final result = await executor.perform(action);

      expect(result.isSuccess, isTrue);
      expect(result.file, isNotNull);
      expect(result.file!.path, endsWith('${Platform.pathSeparator}app.apk'));
      expect(await result.file!.readAsBytes(), bytes);
      expect(result.downloadedBytes, bytes.length);
      expect(result.sha256, action.sha256);
    });

    test('replaces reserved or mismatched artifact file names', () async {
      final bytes = utf8.encode('package bytes');
      final urls = [
        Uri.parse('https://example.com/CON.apk'),
        Uri.parse('https://example.com/setup.exe'),
        Uri.parse('https://example.com/bad%3Aname.apk'),
      ];

      for (final url in urls) {
        final action = DownloadPackageAction(
          packageUrl: url,
          packageType: PackageType.apk,
          packageSizeBytes: bytes.length,
          sha256: crypto.sha256.convert(bytes).toString(),
        );
        final executor = DownloadPackageExecutor(
          downloadDirectory: tempDir.path,
          downloader: PackageDownloader(
            client: _FakePackageClient(
              PackageDownloadResponse(
                statusCode: 200,
                headers: const {},
                bytes: Stream.value(bytes),
              ),
            ),
          ),
        );

        final result = await executor.perform(action);

        expect(result.isSuccess, isTrue);
        expect(
          result.file!.path,
          endsWith(
            '${Platform.pathSeparator}package-'
            '${crypto.sha256.convert(bytes).toString().substring(0, 12)}.apk',
          ),
        );
      }
    });

    test('streams start, progress, and exactly one completion', () async {
      final bytes = utf8.encode('package bytes');
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: bytes.length,
        sha256: crypto.sha256.convert(bytes).toString(),
      );
      final executor = DownloadPackageExecutor(
        downloadDirectory: tempDir.path,
        downloader: PackageDownloader(
          client: _FakePackageClient(
            PackageDownloadResponse(
              statusCode: 200,
              headers: {'content-length': '${bytes.length}'},
              bytes: Stream<List<int>>.fromIterable([
                bytes.sublist(0, 4),
                bytes.sublist(4),
              ]),
            ),
          ),
        ),
      );

      final events = await executor.performStream(action).toList();

      expect(events.whereType<UpdateActionStarted>(), hasLength(1));
      expect(events.whereType<UpdateActionProgress>(), hasLength(2));
      expect(events.whereType<UpdateActionCompleted>(), hasLength(1));
      expect(
        (events.last as UpdateActionCompleted).result.isSuccess,
        isTrue,
      );
    });

    test('canceling the stream subscription cancels the active download',
        () async {
      final bodyStarted = Completer<void>();
      final responseClosed = Completer<void>();
      final body = StreamController<List<int>>(
        onListen: bodyStarted.complete,
      );
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: 42,
        sha256: 'a' * 64,
      );
      final executor = DownloadPackageExecutor(
        downloadDirectory: tempDir.path,
        downloader: PackageDownloader(
          client: _FakePackageClient(
            PackageDownloadResponse(
              statusCode: 200,
              headers: const {},
              bytes: body.stream,
              onClose: responseClosed.complete,
            ),
          ),
        ),
      );

      final subscription = executor.performStream(action).listen((_) {});
      await bodyStarted.future;
      await subscription.cancel();

      await responseClosed.future.timeout(const Duration(seconds: 1));
      await body.close();
    });
  });
}

class _FakePackageClient implements PackageDownloadClient {
  final PackageDownloadResponse response;

  _FakePackageClient(this.response);

  @override
  Future<PackageDownloadResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
    UpdateActionCancelToken? cancelToken,
  }) async {
    return response;
  }
}
