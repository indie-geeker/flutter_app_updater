import 'dart:convert';
import 'dart:io';

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

  @override
  Future<void> installApp({required String path}) async {
    installedPaths.add(path);
  }
}
