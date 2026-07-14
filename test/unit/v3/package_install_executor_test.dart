import 'package:flutter/services.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater/src/channel/flutter_app_updater_method_channel.dart';
import 'package:flutter_app_updater/src/channel/flutter_app_updater_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InstallPackageExecutor', () {
    test('requires package size and SHA-256 metadata together', () {
      expect(
        () => InstallPackageAction(
          packagePath: '/tmp/app.apk',
          packageSizeBytes: 42,
        ),
        throwsAssertionError,
      );
      expect(
        () => InstallPackageAction(
          packagePath: '/tmp/app.apk',
          sha256: 'a' * 64,
        ),
        throwsAssertionError,
      );
    });

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
            packageSizeBytes: 42,
            sha256: 'a' * 64,
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
        InstallPackageAction(
          packagePath: '/tmp/app.apk',
          packageSizeBytes: 42,
          sha256: 'a' * 64,
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(platform.installedPaths, ['/tmp/app.apk']);
      expect(platform.installs.single.packageSizeBytes, 42);
      expect(platform.installs.single.sha256, 'a' * 64);
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

    test('maps integrity and APK identity failures', () async {
      for (final entry in {
        'PACKAGE_HASH_MISMATCH': UpdateErrorCode.packageHashMismatch,
        'PACKAGE_SIGNATURE_INVALID': UpdateErrorCode.packageSignatureInvalid,
      }.entries) {
        final executor = InstallPackageExecutor(
          platform: _FakeInstallPlatform(
            failure: PlatformException(code: entry.key),
          ),
          targetPlatform: TargetPlatform.android,
        );

        final result = await executor.perform(
          const InstallPackageAction(packagePath: '/tmp/app.apk'),
        );

        expect(result.code, entry.value);
      }
    });

    test('rejects unsupported platforms before calling the channel', () async {
      final platform = _FakeInstallPlatform();
      final result = await InstallPackageExecutor(
        platform: platform,
        targetPlatform: TargetPlatform.iOS,
      ).perform(const InstallPackageAction(packagePath: '/tmp/app.apk'));

      expect(result.code, UpdateErrorCode.platformNotSupported);
      expect(platform.installs, isEmpty);
    });
  });

  group('MethodChannelFlutterAppUpdater.installApp', () {
    const channel = MethodChannel('flutter_app_updater');

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('sends a structured integrity argument map', () async {
      MethodCall? recorded;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        recorded = call;
        return true;
      });

      await MethodChannelFlutterAppUpdater().installApp(
        path: '/tmp/app.apk',
        packageSizeBytes: 42,
        sha256: 'a' * 64,
      );

      expect(recorded?.method, 'installApp');
      expect(recorded?.arguments, {
        'path': '/tmp/app.apk',
        'packageSizeBytes': 42,
        'sha256': 'a' * 64,
      });
    });
  });
}

class _FakeInstallPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements FlutterAppUpdaterPlatform {
  final PlatformException? failure;
  final installedPaths = <String>[];
  final installs = <_InstallRequest>[];

  _FakeInstallPlatform({
    this.failure,
  });

  @override
  Future<void> installApp({
    required String path,
    int? packageSizeBytes,
    String? sha256,
  }) async {
    final failure = this.failure;
    if (failure != null) {
      throw failure;
    }
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
