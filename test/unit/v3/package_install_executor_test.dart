import 'package:flutter/services.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater/src/channel/flutter_app_updater_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  group('InstallPackageExecutor', () {
    test('supports only Android APK installation', () {
      const apk = InstallPackageAction(packagePath: '/tmp/app.apk');
      const aab = InstallPackageAction(
        packagePath: '/tmp/app.aab',
        packageType: PackageType.aab,
      );

      expect(
        InstallPackageExecutor(targetPlatform: TargetPlatform.android)
            .supports(apk),
        isTrue,
      );
      expect(
        InstallPackageExecutor(targetPlatform: TargetPlatform.iOS)
            .supports(apk),
        isFalse,
      );
      expect(
        InstallPackageExecutor(targetPlatform: TargetPlatform.android)
            .supports(aab),
        isFalse,
      );
    });

    test('supports only package install actions', () {
      final executor = InstallPackageExecutor(
        platform: _FakeInstallPlatform(),
        targetPlatform: TargetPlatform.android,
      );

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
      final executor = InstallPackageExecutor(
        platform: platform,
        targetPlatform: TargetPlatform.android,
      );

      final result = await executor.perform(
        const InstallPackageAction(packagePath: '/tmp/app.apk'),
      );

      expect(result.isSuccess, isTrue);
      expect(platform.installedPaths, ['/tmp/app.apk']);
    });

    test('rejects blank package paths before calling platform', () async {
      final platform = _FakeInstallPlatform();
      final executor = InstallPackageExecutor(
        platform: platform,
        targetPlatform: TargetPlatform.android,
      );

      final result = await executor.perform(
        const InstallPackageAction(packagePath: ' '),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.missingRequiredField);
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
        targetPlatform: TargetPlatform.android,
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
        targetPlatform: TargetPlatform.android,
      );

      final result = await executor.perform(
        const InstallPackageAction(packagePath: '/tmp/app.apk'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.packageFileNotFound);
    });
  });
}

class _FakeInstallPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements FlutterAppUpdaterPlatform {
  final PlatformException? failure;
  final installedPaths = <String>[];

  _FakeInstallPlatform({
    this.failure,
  });

  @override
  Future<void> installApp({required String path}) async {
    final failure = this.failure;
    if (failure != null) {
      throw failure;
    }
    installedPaths.add(path);
  }
}
