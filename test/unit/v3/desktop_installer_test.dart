import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/src/actions/update_action.dart';
import 'package:flutter_app_updater/src/channel/flutter_app_updater_platform_interface.dart';
import 'package:flutter_app_updater/src/download/package_downloader.dart';
import 'package:flutter_app_updater/src/models/update_error_code.dart';
import 'package:flutter_app_updater/src/platform/desktop_installer_executor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

void main() {
  late Directory tempDir;
  late _FakeInstallerPlatform platform;
  late _FakePackageDownloadClient client;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('desktop_installer_test_');
    platform = _FakeInstallerPlatform();
    client = _FakePackageDownloadClient();
  });

  tearDown(() async {
    final escapedFile = File('${tempDir.parent.path}/evil.dmg');
    if (await escapedFile.exists()) {
      await escapedFile.delete();
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('DesktopInstallerExecutor', () {
    test('accepts Windows installer types and opens verified installer',
        () async {
      final bytes = utf8.encode('windows-installer');
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {},
          bytes: Stream.value(bytes),
        ),
      );
      final action = _installer(
        installerUrl: Uri.parse('https://example.com/app.msi'),
        installerType: InstallerType.msi,
        sha256: _sha256(bytes),
      );

      final result = await DesktopInstallerExecutor(
        platform: TargetPlatform.windows,
        platformChannel: platform,
        client: client,
        downloadDirectory: tempDir,
      ).perform(action);

      expect(result.isSuccess, isTrue);
      expect(platform.openedInstallers.single, endsWith('.msi'));
    });

    test('accepts macOS installer types and opens verified installer',
        () async {
      final bytes = utf8.encode('mac-installer');
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {},
          bytes: Stream.value(bytes),
        ),
      );
      final action = _installer(
        installerUrl: Uri.parse('https://example.com/app.dmg'),
        installerType: InstallerType.dmg,
        sha256: _sha256(bytes),
      );

      final result = await DesktopInstallerExecutor(
        platform: TargetPlatform.macOS,
        platformChannel: platform,
        client: client,
        downloadDirectory: tempDir,
      ).perform(action);

      expect(result.isSuccess, isTrue);
      expect(platform.openedInstallers.single, endsWith('.dmg'));
    });

    test('rejects unsupported installer types for the platform', () async {
      final result = await DesktopInstallerExecutor(
        platform: TargetPlatform.windows,
        platformChannel: platform,
        client: client,
        downloadDirectory: tempDir,
      ).perform(_installer(installerType: InstallerType.dmg));

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.platformNotSupported);
      expect(client.requests, isEmpty);
      expect(platform.openedInstallers, isEmpty);
    });

    test('opens installers without SHA-256', () async {
      final bytes = utf8.encode('windows-installer');
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {},
          bytes: Stream.value(bytes),
        ),
      );

      final result = await DesktopInstallerExecutor(
        platform: TargetPlatform.windows,
        platformChannel: platform,
        client: client,
        downloadDirectory: tempDir,
      ).perform(_installer(sha256: ''));

      expect(result.isSuccess, isTrue);
      expect(client.requests.single, Uri.parse('https://example.com/app.msi'));
      expect(platform.openedInstallers.single, endsWith('.msi'));
    });

    test('returns structured failure for unsupported platform', () async {
      final result = await DesktopInstallerExecutor(
        platform: TargetPlatform.android,
        platformChannel: platform,
        client: client,
        downloadDirectory: tempDir,
      ).perform(_installer(installerType: InstallerType.exe));

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.platformNotSupported);
    });

    test('sanitizes unsafe decoded installer URL file names', () async {
      final bytes = utf8.encode('mac-installer');
      final sha256 = _sha256(bytes);
      final cases = [
        Uri.parse('https://example.com/..%2Fevil.dmg'),
        Uri.parse('https://example.com/%2Ftmp%2Fevil.dmg'),
        Uri.parse('https://example.com/a%2Fb.dmg'),
      ];

      for (final installerUrl in cases) {
        client.enqueue(
          PackageDownloadResponse(
            statusCode: 200,
            headers: const {},
            bytes: Stream.value(bytes),
          ),
        );

        final result = await DesktopInstallerExecutor(
          platform: TargetPlatform.macOS,
          platformChannel: platform,
          client: client,
          downloadDirectory: tempDir,
        ).perform(
          _installer(
            installerUrl: installerUrl,
            installerType: InstallerType.dmg,
            sha256: sha256,
          ),
        );

        final openedInstaller = platform.openedInstallers.removeLast();

        expect(result.isSuccess, isTrue);
        expect(
          openedInstaller,
          '${tempDir.path}${Platform.pathSeparator}'
          'installer-${sha256.substring(0, 12)}.dmg',
        );
        expect(
          File(openedInstaller).absolute.path,
          startsWith('${tempDir.absolute.path}${Platform.pathSeparator}'),
        );
      }
    });
  });
}

OpenInstallerAction _installer({
  Uri? installerUrl,
  InstallerType installerType = InstallerType.msi,
  String? sha256,
}) {
  return OpenInstallerAction(
    installerUrl: installerUrl ?? Uri.parse('https://example.com/app.msi'),
    installerType: installerType,
    installerSizeBytes: 1024,
    sha256: sha256 ?? _sha256(utf8.encode('windows-installer')),
  );
}

String _sha256(List<int> bytes) => crypto.sha256.convert(bytes).toString();

class _FakePackageDownloadClient implements PackageDownloadClient {
  final requests = <Uri>[];
  final _responses = <PackageDownloadResponse>[];

  void enqueue(PackageDownloadResponse response) {
    _responses.add(response);
  }

  @override
  Future<PackageDownloadResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    requests.add(url);
    if (_responses.isEmpty) {
      throw StateError('No response queued.');
    }
    return _responses.removeAt(0);
  }
}

class _FakeInstallerPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements FlutterAppUpdaterPlatform {
  final openedInstallers = <String>[];

  @override
  Future<void> openInstaller({required String installerPath}) async {
    openedInstallers.add(installerPath);
  }
}
