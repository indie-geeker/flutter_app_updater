import 'dart:convert';
import 'dart:io';

import 'package:flutter_app_updater/src/cli/hash_command.dart';
import 'package:flutter_app_updater/src/cli/manifest_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('updater_cli_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ManifestCommand', () {
    test('generates manifest skeleton', () {
      final output = const ManifestCommand().generate();
      final data = jsonDecode(output) as Map<String, Object?>;

      expect(data['schemaVersion'], 3);
      expect(data['appId'], 'com.example.app');
      expect(data['channel'], 'stable');
      expect(data['releases'], isA<List>());
      expect(output, contains('packageUrl'));
      expect(output, contains('downloadAndInstallPackage'));
    });

    test('verifies manifest schema', () async {
      final manifestFile = File('${tempDir.path}/manifest.json');
      await manifestFile.writeAsString(const ManifestCommand().generate());

      final result = await const ManifestCommand().verify(manifestFile.path);

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Manifest valid'));
    });

    test('rejects legacy fields', () async {
      final manifestFile = File('${tempDir.path}/legacy.json');
      await manifestFile.writeAsString(jsonEncode({
        'schemaVersion': 3,
        'appId': 'com.example.app',
        'channel': 'stable',
        'releases': [
          {
            'version': '2.0.0',
            'platform': 'android',
            'releaseNotes': 'Bug fixes',
            'actions': [
              {
                'type': 'downloadPackage',
                'packageType': 'apk',
                'packageUrl': 'https://example.com/app.apk',
                'sha256': 'a' * 64,
                'downloadUrl': 'https://example.com/app.apk',
              },
            ],
          },
        ],
      }));

      final result = await const ManifestCommand().verify(manifestFile.path);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('LEGACY_FIELD_NOT_SUPPORTED'));
    });

    test('rejects openStore actions without store', () async {
      final manifestFile = await _writeManifest(
        tempDir,
        _manifestWithAction({
          'type': 'openStore',
          'storeUrl':
              'https://play.google.com/store/apps/details?id=com.example.app',
        }),
      );

      final result = await const ManifestCommand().verify(manifestFile.path);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('MISSING_REQUIRED_FIELD'));
      expect(result.stderr, contains('store'));
    });

    test('rejects openAndroidMarket actions without market', () async {
      final manifestFile = await _writeManifest(
        tempDir,
        _manifestWithAction({
          'type': 'openAndroidMarket',
          'targetPackageName': 'com.example.app',
        }),
      );

      final result = await const ManifestCommand().verify(manifestFile.path);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('MISSING_REQUIRED_FIELD'));
      expect(result.stderr, contains('market'));
    });

    test('rejects downloadPackage actions without packageType', () async {
      final manifestFile = await _writeManifest(
        tempDir,
        _manifestWithAction({
          'type': 'downloadPackage',
          'packageUrl': 'https://example.com/app.apk',
          'sha256': 'a' * 64,
        }),
      );

      final result = await const ManifestCommand().verify(manifestFile.path);

      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('MISSING_REQUIRED_FIELD'));
      expect(result.stderr, contains('packageType'));
    });

    test('verifies downloadAndInstallPackage actions without sha256', () async {
      final manifestFile = await _writeManifest(
        tempDir,
        _manifestWithAction({
          'type': 'downloadAndInstallPackage',
          'packageUrl': 'https://example.com/app.apk',
          'packageType': 'apk',
        }),
      );

      final result = await const ManifestCommand().verify(manifestFile.path);

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Manifest valid'));
    });

    test('rejects relative action URLs', () async {
      final cases = [
        _manifestWithAction({
          'type': 'openStore',
          'store': 'googlePlay',
          'storeUrl': 'app.apk',
        }),
        _manifestWithAction({
          'type': 'downloadPackage',
          'packageUrl': '/app.apk',
          'packageType': 'apk',
          'sha256': 'a' * 64,
        }),
        _manifestWithAction({
          'type': 'openInstaller',
          'installerUrl': 'app.dmg',
          'installerType': 'dmg',
          'sha256': 'a' * 64,
        }),
      ];

      for (var index = 0; index < cases.length; index += 1) {
        final manifestFile = await _writeManifest(
          tempDir,
          cases[index],
          name: 'relative-url-$index.json',
        );

        final result = await const ManifestCommand().verify(manifestFile.path);

        expect(result.exitCode, isNot(0));
        expect(result.stderr, contains('MANIFEST_INVALID'));
      }
    });
  });

  group('HashCommand', () {
    test('computes SHA-256', () async {
      final file = File('${tempDir.path}/package.apk');
      await file.writeAsString('package-bytes');

      final hash = await const HashCommand().compute(file.path);

      expect(
        hash,
        '9d7ec3059a3be4a437e8028d9a498f2fd4adfa7183af52ecc712704ee1dc8260',
      );
    });
  });
}

Future<File> _writeManifest(
  Directory tempDir,
  Map<String, Object?> manifest, {
  String name = 'manifest.json',
}) async {
  final file = File('${tempDir.path}/$name');
  await file.writeAsString(jsonEncode(manifest));
  return file;
}

Map<String, Object?> _manifestWithAction(Map<String, Object?> action) {
  return {
    'schemaVersion': 3,
    'appId': 'com.example.app',
    'channel': 'stable',
    'releases': [
      {
        'version': '2.0.0',
        'platform': 'android',
        'releaseNotes': 'Bug fixes',
        'actions': [action],
      },
    ],
  };
}
