import 'package:flutter/services.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater/src/channel/flutter_app_updater_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  group('InstallPackageExecutor', () {
    test('supports only package install actions', () {
      final executor = InstallPackageExecutor(platform: _FakeInstallPlatform());

      expect(
        executor.supports(
          const InstallPackageAction(packagePath: '/tmp/app.apk'),
        ),
        isTrue,
      );
      expect(
        executor.supports(
          DownloadPackageAction(
            packageUrl: Uri.parse('https://example.com/app.apk'),
            packageType: PackageType.apk,
          ),
        ),
        isFalse,
      );
    });

    test('installs an existing package through the platform channel', () async {
      final platform = _FakeInstallPlatform();
      final executor = InstallPackageExecutor(platform: platform);

      final result = await executor.perform(
        const InstallPackageAction(packagePath: '/tmp/app.apk'),
      );

      expect(result.isSuccess, isTrue);
      expect(platform.installedPaths, ['/tmp/app.apk']);
    });

    test('rejects blank package paths before calling platform', () async {
      final platform = _FakeInstallPlatform();
      final executor = InstallPackageExecutor(platform: platform);

      final result = await executor.perform(
        const InstallPackageAction(packagePath: ' '),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.missingRequiredField);
      expect(platform.installedPaths, isEmpty);
    });

    test('rejects non-APK package types before calling platform', () async {
      final platform = _FakeInstallPlatform();
      final executor = InstallPackageExecutor(platform: platform);

      final result = await executor.perform(
        const InstallPackageAction(
          packagePath: '/tmp/app.aab',
          packageType: PackageType.aab,
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.manifestInvalid);
      expect(platform.installedPaths, isEmpty);
    });

    test('maps install permission failures', () async {
      final executor = InstallPackageExecutor(
        platform: _FakeInstallPlatform(
          failure: PlatformException(
            code: 'INSTALL_PERMISSION_REQUIRED',
            message: 'Permission required.',
          ),
        ),
      );

      final result = await executor.perform(
        const InstallPackageAction(packagePath: '/tmp/app.apk'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.packageInstallPermissionRequired);
    });

    test('maps missing package files', () async {
      final executor = InstallPackageExecutor(
        platform: _FakeInstallPlatform(
          failure: PlatformException(
            code: 'FILE_NOT_FOUND',
            message: 'Missing file.',
          ),
        ),
      );

      final result = await executor.perform(
        const InstallPackageAction(packagePath: '/tmp/app.apk'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.packageFileNotFound);
    });

    test('opens install permission settings through public AppUpdater API',
        () async {
      final originalPlatform = FlutterAppUpdaterPlatform.instance;
      final platform = _FakeInstallPlatform();
      FlutterAppUpdaterPlatform.instance = platform;
      addTearDown(() {
        FlutterAppUpdaterPlatform.instance = originalPlatform;
      });

      final result = await _updater().openInstallPermissionSettings();

      expect(result.isSuccess, isTrue);
      expect(platform.openedInstallPermissionSettings, 1);
    });

    test('maps unsupported install permission settings', () async {
      final originalPlatform = FlutterAppUpdaterPlatform.instance;
      FlutterAppUpdaterPlatform.instance = _FakeInstallPlatform(
        settingsFailure: PlatformException(
          code: 'PLATFORM_NOT_SUPPORTED',
          message: 'Settings not available.',
        ),
      );
      addTearDown(() {
        FlutterAppUpdaterPlatform.instance = originalPlatform;
      });

      final result = await _updater().openInstallPermissionSettings();

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.platformNotSupported);
    });
  });
}

AppUpdater _updater() {
  return AppUpdater(
    source: UpdateSource.manifest(
      manifestUrl: Uri.parse('https://example.com/update.json'),
    ),
  );
}

class _FakeInstallPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements FlutterAppUpdaterPlatform {
  final PlatformException? failure;
  final PlatformException? settingsFailure;
  final installedPaths = <String>[];
  var openedInstallPermissionSettings = 0;

  _FakeInstallPlatform({
    this.failure,
    this.settingsFailure,
  });

  @override
  Future<void> installApp({required String path}) async {
    final failure = this.failure;
    if (failure != null) {
      throw failure;
    }
    installedPaths.add(path);
  }

  @override
  Future<void> openInstallPermissionSettings() async {
    final failure = settingsFailure;
    if (failure != null) {
      throw failure;
    }
    openedInstallPermissionSettings++;
  }
}
