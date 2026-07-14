import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
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

    test('supports only Android APK download and installation', () {
      final apk = DownloadAndInstallPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: 42,
        sha256: 'a' * 64,
      );
      final aab = DownloadAndInstallPackageAction(
        packageUrl: Uri.parse('https://example.com/app.aab'),
        packageType: PackageType.aab,
        packageSizeBytes: 42,
        sha256: 'a' * 64,
      );

      expect(
        DownloadAndInstallPackageExecutor(
          downloadDirectory: tempDir.path,
          targetPlatform: TargetPlatform.android,
        ).supports(apk),
        isTrue,
      );
      expect(
        DownloadAndInstallPackageExecutor(
          downloadDirectory: tempDir.path,
          targetPlatform: TargetPlatform.iOS,
        ).supports(apk),
        isFalse,
      );
      expect(
        DownloadAndInstallPackageExecutor(
          downloadDirectory: tempDir.path,
          targetPlatform: TargetPlatform.android,
        ).supports(aab),
        isFalse,
      );
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
        targetPlatform: TargetPlatform.android,
        downloader: PackageDownloader(
          client: client,
          retryStrategy: RetryStrategy.disabled,
        ),
        installExecutor: InstallPackageExecutor(
          platform: platform,
          targetPlatform: TargetPlatform.android,
        ),
      );

      final result = await executor.perform(
        DownloadAndInstallPackageAction(
          packageUrl: Uri.parse('https://example.com/app.apk'),
          packageType: PackageType.apk,
          packageSizeBytes: bytes.length,
          sha256: crypto.sha256.convert(bytes).toString(),
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(platform.installedPaths.single,
          endsWith('${Platform.pathSeparator}app.apk'));
      expect(platform.installs.single.packageSizeBytes, bytes.length);
      expect(
        platform.installs.single.sha256,
        crypto.sha256.convert(bytes).toString(),
      );
      expect(await File(platform.installedPaths.single).readAsBytes(), bytes);
    });

    test('does not install when download fails', () async {
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 500,
          headers: {},
          bytes: const Stream<List<int>>.empty(),
        ),
      );
      final executor = DownloadAndInstallPackageExecutor(
        downloadDirectory: tempDir.path,
        targetPlatform: TargetPlatform.android,
        downloader: PackageDownloader(
          client: client,
          retryStrategy: RetryStrategy.disabled,
        ),
        installExecutor: InstallPackageExecutor(
          platform: platform,
          targetPlatform: TargetPlatform.android,
        ),
      );

      final result = await executor.perform(
        DownloadAndInstallPackageAction(
          packageUrl: Uri.parse('https://example.com/app.apk'),
          packageType: PackageType.apk,
          packageSizeBytes: 42,
          sha256: 'a' * 64,
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(platform.installedPaths, isEmpty);
    });

    test('streams download progress before installing', () async {
      final bytes = utf8.encode('package bytes');
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: {'content-length': '${bytes.length}'},
          bytes: Stream<List<int>>.fromIterable([
            bytes.sublist(0, 4),
            bytes.sublist(4),
          ]),
        ),
      );
      final action = DownloadAndInstallPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: bytes.length,
        sha256: crypto.sha256.convert(bytes).toString(),
      );
      final executor = DownloadAndInstallPackageExecutor(
        downloadDirectory: tempDir.path,
        targetPlatform: TargetPlatform.android,
        downloader: PackageDownloader(client: client),
        installExecutor: InstallPackageExecutor(
          platform: platform,
          targetPlatform: TargetPlatform.android,
        ),
      );

      final events = await executor.performStream(action).toList();

      expect(events.whereType<UpdateActionStarted>(), hasLength(1));
      expect(events.whereType<UpdateActionProgress>(), hasLength(2));
      expect(events.whereType<UpdateActionCompleted>(), hasLength(1));
      expect(platform.installedPaths, hasLength(1));
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
    UpdateActionCancelToken? cancelToken,
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
  final installs = <_InstallRequest>[];

  @override
  Future<void> installApp({
    required String path,
    int? packageSizeBytes,
    String? sha256,
  }) async {
    installedPaths.add(path);
    installs.add(_InstallRequest(path, packageSizeBytes, sha256));
  }
}

class _InstallRequest {
  final String path;
  final int? packageSizeBytes;
  final String? sha256;

  const _InstallRequest(this.path, this.packageSizeBytes, this.sha256);
}
