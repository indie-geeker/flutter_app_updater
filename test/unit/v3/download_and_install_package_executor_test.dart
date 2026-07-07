import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater/src/channel/flutter_app_updater_platform_interface.dart';
import 'package:flutter_app_updater/src/download/package_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  group('DownloadAndInstallPackageExecutor', () {
    late Directory tempDir;
    late _FakePackageClient client;
    late _FakeInstallPlatform platform;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'download_and_install_package_executor_test_',
      );
      client = _FakePackageClient();
      platform = _FakeInstallPlatform();
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('downloads and installs package actions', () async {
      final bytes = utf8.encode('package bytes');
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {},
          bytes: Stream.value(bytes),
        ),
      );
      final executor = DownloadAndInstallPackageExecutor(
        downloadDirectory: tempDir.path,
        downloader: PackageDownloader(client: client),
        installExecutor: InstallPackageExecutor(platform: platform),
      );

      final result = await executor.perform(
        DownloadAndInstallPackageAction(
          packageUrl: Uri.parse('https://example.com/app.apk'),
          packageType: PackageType.apk,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(platform.installedPaths.single,
          endsWith('${Platform.pathSeparator}app.apk'));
      expect(await File(platform.installedPaths.single).readAsBytes(), bytes);
    });

    test('does not install when download fails', () async {
      client.enqueue(
        const PackageDownloadResponse(
          statusCode: 500,
          headers: {},
          bytes: Stream<List<int>>.empty(),
        ),
      );
      final executor = DownloadAndInstallPackageExecutor(
        downloadDirectory: tempDir.path,
        downloader: PackageDownloader(client: client),
        installExecutor: InstallPackageExecutor(platform: platform),
      );

      final result = await executor.perform(
        DownloadAndInstallPackageAction(
          packageUrl: Uri.parse('https://example.com/app.apk'),
          packageType: PackageType.apk,
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(platform.installedPaths, isEmpty);
    });

    test('performStream emits download progress and install events', () async {
      final firstChunk = utf8.encode('package ');
      final secondChunk = utf8.encode('bytes');
      final bytes = [...firstChunk, ...secondChunk];
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: {'content-length': '${bytes.length}'},
          bytes: Stream.fromIterable([firstChunk, secondChunk]),
        ),
      );
      final action = DownloadAndInstallPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
      );
      final executor = DownloadAndInstallPackageExecutor(
        downloadDirectory: tempDir.path,
        downloader: PackageDownloader(client: client),
        installExecutor: InstallPackageExecutor(platform: platform),
      );

      final events = await executor.performStream(action).toList();

      expect(events, hasLength(6));
      expect(events[0], isA<UpdateActionStarted>());
      expect(
        events[1],
        isA<UpdateDownloadProgress>().having(
          (event) => event.receivedBytes,
          'receivedBytes',
          firstChunk.length,
        ),
      );
      expect(
        events[2],
        isA<UpdateDownloadProgress>().having(
          (event) => event.receivedBytes,
          'receivedBytes',
          bytes.length,
        ),
      );
      expect(events[3], isA<UpdateDownloadCompleted>());
      expect(
        events[4],
        isA<UpdateInstallStarted>().having(
          (event) => event.packagePath,
          'packagePath',
          endsWith('${Platform.pathSeparator}app.apk'),
        ),
      );
      expect(
        events[5],
        isA<UpdateActionCompleted>().having(
          (event) => event.result.downloadedBytes,
          'downloadedBytes',
          bytes.length,
        ),
      );
      expect(platform.installedPaths.single,
          endsWith('${Platform.pathSeparator}app.apk'));
    });

    test(
        'performStream emits permission required when install permission is missing',
        () async {
      final bytes = utf8.encode('package bytes');
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: {'content-length': '${bytes.length}'},
          bytes: Stream.value(bytes),
        ),
      );
      platform.failure = PlatformException(
        code: 'INSTALL_PERMISSION_REQUIRED',
        message: 'Permission required.',
      );
      final executor = DownloadAndInstallPackageExecutor(
        downloadDirectory: tempDir.path,
        downloader: PackageDownloader(client: client),
        installExecutor: InstallPackageExecutor(platform: platform),
      );

      final events = await executor
          .performStream(
            DownloadAndInstallPackageAction(
              packageUrl: Uri.parse('https://example.com/app.apk'),
              packageType: PackageType.apk,
            ),
          )
          .toList();

      expect(events.whereType<UpdateInstallPermissionRequired>(), hasLength(1));
      expect(
        events.last,
        isA<UpdateActionFailed>().having(
          (event) => event.result.code,
          'code',
          UpdateErrorCode.packageInstallPermissionRequired,
        ),
      );
    });
  });
}

class _FakePackageClient implements PackageDownloadClient {
  final _responses = <PackageDownloadResponse>[];

  void enqueue(PackageDownloadResponse response) {
    _responses.add(response);
  }

  @override
  Future<PackageDownloadResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    if (_responses.isEmpty) {
      throw StateError('No response queued.');
    }
    return _responses.removeAt(0);
  }
}

class _FakeInstallPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements FlutterAppUpdaterPlatform {
  final installedPaths = <String>[];
  PlatformException? failure;

  @override
  Future<void> installApp({required String path}) async {
    final failure = this.failure;
    if (failure != null) {
      throw failure;
    }
    installedPaths.add(path);
  }
}
