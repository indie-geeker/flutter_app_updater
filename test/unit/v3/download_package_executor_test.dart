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
        sha256: 'a' * 64,
      );
      final executor = DownloadPackageExecutor(
        downloadDirectory: tempDir.path,
        downloader: PackageDownloader(
          client: _FakePackageClient(
            const PackageDownloadResponse(
              statusCode: 500,
              headers: {},
              bytes: Stream<List<int>>.empty(),
            ),
          ),
        ),
      );

      final result = await executor.perform(action);

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.packageDownloadFailed);
    });

    test('rejects insecure production package URLs before downloading',
        () async {
      final executor = DownloadPackageExecutor(
        downloadDirectory: tempDir.path,
        downloader: PackageDownloader(
          client: _FakePackageClient(
            const PackageDownloadResponse(
              statusCode: 200,
              headers: {},
              bytes: Stream<List<int>>.empty(),
            ),
          ),
        ),
      );

      final result = await executor.perform(
        DownloadPackageAction(
          packageUrl: Uri.parse('http://example.com/app.apk'),
          packageType: PackageType.apk,
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.manifestInvalid);
    });

    test('downloads package actions without SHA-256', () async {
      final bytes = utf8.encode('package bytes');
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
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
      expect(result.sha256, isNull);
    });

    test('performStream emits progress and completion', () async {
      final chunks = [
        utf8.encode('package '),
        utf8.encode('bytes'),
      ];
      final bytes = chunks.expand((chunk) => chunk).toList();
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: bytes.length,
      );
      final executor = DownloadPackageExecutor(
        downloadDirectory: tempDir.path,
        downloader: PackageDownloader(
          client: _FakePackageClient(
            PackageDownloadResponse(
              statusCode: 200,
              headers: {'content-length': '${bytes.length}'},
              bytes: Stream<List<int>>.fromIterable(chunks),
            ),
          ),
        ),
      );

      final events = await executor.performStream(action).toList();

      expect(events.first, isA<UpdateActionStarted>());
      expect(events.whereType<UpdateActionProgress>(), hasLength(2));
      expect(events.last, isA<UpdateActionCompleted>());
      expect((events.last as UpdateActionCompleted).result.isSuccess, isTrue);
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
  }) async {
    return response;
  }
}
