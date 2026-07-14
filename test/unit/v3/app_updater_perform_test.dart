import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater/src/channel/flutter_app_updater_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  group('AppUpdater.perform', () {
    late Directory tempDir;
    late HttpServer server;
    late _FakeCommercialPlatform platform;
    late FlutterAppUpdaterPlatform previousPlatform;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'app_updater_perform_test_',
      );
      server = await _PackageServer.start();
      previousPlatform = FlutterAppUpdaterPlatform.instance;
      platform = _FakeCommercialPlatform();
      FlutterAppUpdaterPlatform.instance = platform;
    });

    tearDown(() async {
      FlutterAppUpdaterPlatform.instance = previousPlatform;
      await server.close(force: true);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('delegates OpenStoreAction to a supporting executor', () async {
      final executor = _RecordingExecutor(
        supportsAction: (action) => action is OpenStoreAction,
      );
      final action = OpenStoreAction(
        store: StoreKind.googlePlay,
        storeUrl: Uri.parse(
          'https://play.google.com/store/apps/details?id=com.example.app',
        ),
      );
      final updater = _updater(executors: [executor]);

      final result = await updater.perform(action);

      expect(result.isSuccess, isTrue);
      expect(executor.performedActions, [same(action)]);
    });

    test('delegates DownloadPackageAction to a supporting executor', () async {
      final executor = _RecordingExecutor(
        supportsAction: (action) => action is DownloadPackageAction,
      );
      final action = DownloadPackageAction(
        packageUrl: Uri.parse('https://example.com/app.apk'),
        packageType: PackageType.apk,
        packageSizeBytes: 42,
        sha256: 'a' * 64,
      );
      final updater = _updater(executors: [executor]);

      final result = await updater.perform(action);

      expect(result.isSuccess, isTrue);
      expect(executor.performedActions, [same(action)]);
    });

    test('returns structured failure for unsupported actions', () async {
      const action = OpenAndroidMarketAction(
        market: AndroidMarketKind.huawei,
        targetPackageName: 'com.example.app',
      );
      final updater = _updater(executors: const []);

      final result = await updater.perform(action);

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.noSupportedAction);
    });

    test('public barrel exports executor API', () async {
      final executor = _RecordingExecutor(
        supportsAction: (action) => action is OpenStoreAction,
      );

      expect(executor, isA<UpdateActionExecutor>());
      expect(const UpdateActionResult.success().isSuccess, isTrue);
    });

    test('default executors perform stable commercial actions', () async {
      final androidUpdater = AppUpdater(
        source: UpdateSource.manifest(
          manifestUrl: Uri.parse('https://example.com/update.json'),
          expectedAppId: 'com.example.app',
        ),
        selector: const UpdateSelector(
          installedVersion: '1.0.0',
          platform: TargetPlatform.android,
          channel: 'stable',
        ),
        downloadDirectory: tempDir.path,
        platform: TargetPlatform.android,
      );
      final windowsUpdater = AppUpdater(
        source: UpdateSource.manifest(
          manifestUrl: Uri.parse('https://example.com/update.json'),
          expectedAppId: 'com.example.app',
        ),
        selector: const UpdateSelector(
          installedVersion: '1.0.0',
          platform: TargetPlatform.windows,
          channel: 'stable',
        ),
        downloadDirectory: tempDir.path,
        platform: TargetPlatform.windows,
      );

      final downloadResult = await androidUpdater.perform(
        DownloadPackageAction(
          packageUrl: _serverUri(server, '/app.apk'),
          packageType: PackageType.apk,
          packageSizeBytes: _packageBytes('/app.apk').length,
          sha256: sha256.convert(_packageBytes('/app.apk')).toString(),
        ),
      );
      final installResult = await androidUpdater.perform(
        const InstallPackageAction(packagePath: '/tmp/app.apk'),
      );
      final downloadAndInstallResult = await androidUpdater.perform(
        DownloadAndInstallPackageAction(
          packageUrl: _serverUri(server, '/combined.apk'),
          packageType: PackageType.apk,
          packageSizeBytes: _packageBytes('/combined.apk').length,
          sha256: sha256.convert(_packageBytes('/combined.apk')).toString(),
        ),
      );
      final installerResult = await windowsUpdater.perform(
        OpenInstallerAction(
          installerUrl: _serverUri(server, '/app.msi'),
          installerType: InstallerType.msi,
          installerSizeBytes: _packageBytes('/app.msi').length,
          sha256: sha256.convert(_packageBytes('/app.msi')).toString(),
        ),
      );

      expect(downloadResult.isSuccess, isTrue);
      expect(downloadResult.file?.path, startsWith(tempDir.path));
      expect(installResult.isSuccess, isTrue);
      expect(downloadAndInstallResult.isSuccess, isTrue);
      expect(installerResult.isSuccess, isTrue);
      expect(platform.installedPaths, hasLength(2));
      expect(platform.openedInstallers.single, startsWith(tempDir.path));
    });
  });
}

AppUpdater _updater({
  required List<UpdateActionExecutor> executors,
}) {
  return AppUpdater(
    source: UpdateSource.manifest(
      manifestUrl: Uri.parse('https://example.com/update.json'),
      expectedAppId: 'com.example.app',
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

class _FakeCommercialPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements FlutterAppUpdaterPlatform {
  final installedPaths = <String>[];
  final openedInstallers = <String>[];

  @override
  Future<void> installApp({required String path}) async {
    installedPaths.add(path);
  }

  @override
  Future<void> openInstaller({required String installerPath}) async {
    openedInstallers.add(installerPath);
  }
}

class _PackageServer {
  static Future<HttpServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.statusCode = HttpStatus.ok;
      request.response.add(_packageBytes(request.uri.path));
      request.response.close();
    });
    return server;
  }
}

List<int> _packageBytes(String path) => utf8.encode('package:$path');

Uri _serverUri(HttpServer server, String path) {
  return Uri.parse('http://127.0.0.1:${server.port}$path');
}
