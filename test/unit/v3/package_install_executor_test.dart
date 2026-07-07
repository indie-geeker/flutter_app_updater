import 'package:flutter/services.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater/src/channel/flutter_app_updater_method_channel.dart';
import 'package:flutter_app_updater/src/channel/flutter_app_updater_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    test('rejects AAB package installs before calling platform', () async {
      final platform = _FakeInstallPlatform();
      final executor = InstallPackageExecutor(platform: platform);

      final result = await executor.perform(
        const InstallPackageAction(
          packagePath: '/tmp/app.aab',
          packageType: PackageType.aab,
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.packageTypeNotInstallable);
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

    test(
        'performStream emits permission required for missing install permission',
        () async {
      final executor = InstallPackageExecutor(
        platform: _FakeInstallPlatform(
          failure: PlatformException(
            code: 'INSTALL_PERMISSION_REQUIRED',
            message: 'Permission required.',
          ),
        ),
      );

      final events = await executor
          .performStream(
            const InstallPackageAction(packagePath: '/tmp/app.apk'),
          )
          .toList();

      expect(events, hasLength(4));
      expect(events[0], isA<UpdateActionStarted>());
      expect(
        events[1],
        isA<UpdateInstallStarted>().having(
          (event) => event.packagePath,
          'packagePath',
          '/tmp/app.apk',
        ),
      );
      expect(
        events[2],
        isA<UpdateInstallPermissionRequired>().having(
          (event) => event.packagePath,
          'packagePath',
          '/tmp/app.apk',
        ),
      );
      expect(
        events[3],
        isA<UpdateActionFailed>().having(
          (event) => event.result.code,
          'code',
          UpdateErrorCode.packageInstallPermissionRequired,
        ),
      );
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
  });

  group('MethodChannelFlutterAppUpdater install permission helpers', () {
    const channel = MethodChannel('flutter_app_updater');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('invokes canRequestPackageInstalls', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });

      final result =
          await MethodChannelFlutterAppUpdater().canRequestPackageInstalls();

      expect(result, isTrue);
      expect(calls.single.method, 'canRequestPackageInstalls');
    });

    test('invokes openInstallPermissionSettings', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });

      await MethodChannelFlutterAppUpdater().openInstallPermissionSettings();

      expect(calls.single.method, 'openInstallPermissionSettings');
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
