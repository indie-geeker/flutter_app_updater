import 'dart:convert';

import 'package:flutter_app_updater/src/manifest/manifest_parser.dart';
import 'package:flutter_app_updater/src/models/update_error_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ManifestValidator', () {
    test('rejects unsupported schema versions', () {
      expect(
        () => const ManifestParser().parse({
          'schemaVersion': 2,
          'appId': 'com.example.app',
          'channel': 'stable',
          'releases': [],
        }),
        throwsA(
          isA<ManifestParseException>().having(
            (error) => error.code,
            'code',
            UpdateErrorCode.unsupportedSchemaVersion,
          ),
        ),
      );
    });

    test('rejects malformed release versions', () {
      final manifest = _manifestWithAction({
        'type': 'openStore',
        'store': 'googlePlay',
        'storeUrl': 'https://play.google.com/store/apps/details?id=example',
      });
      final release = (manifest['releases']! as List<Object?>).single
          as Map<String, Object?>;
      release['version'] = '1..0';

      expect(
        () => const ManifestParser().parse(manifest),
        throwsA(
          isA<ManifestParseException>().having(
            (error) => error.code,
            'code',
            UpdateErrorCode.manifestInvalid,
          ),
        ),
      );
    });

    test('rejects malformed minimum supported versions', () {
      final manifest = _manifestWithAction({
        'type': 'openStore',
        'store': 'googlePlay',
        'storeUrl': 'https://play.google.com/store/apps/details?id=example',
      });
      final release = (manifest['releases']! as List<Object?>).single
          as Map<String, Object?>;
      release['policy'] = {'minSupportedVersion': '1.2.3.4'};

      expect(
        () => const ManifestParser().parse(manifest),
        throwsA(
          isA<ManifestParseException>().having(
            (error) => error.code,
            'code',
            UpdateErrorCode.configurationInvalid,
          ),
        ),
      );
    });

    test('rejects legacy downloadUrl fields', () {
      expect(
        () => const ManifestParser().parse(_manifestWithAction({
          'type': 'downloadPackage',
          'downloadUrl': 'https://example.com/app.apk',
          'packageType': 'apk',
          'sha256': 'a' * 64,
        })),
        throwsA(
          isA<ManifestParseException>().having(
            (error) => error.code,
            'code',
            UpdateErrorCode.legacyFieldNotSupported,
          ),
        ),
      );
    });

    test('rejects legacy md5 fields', () {
      expect(
        () => const ManifestParser().parse(_manifestWithAction({
          'type': 'downloadPackage',
          'packageUrl': 'https://example.com/app.apk',
          'packageType': 'apk',
          'sha256': 'a' * 64,
          'md5': 'legacy-md5',
        })),
        throwsA(
          isA<ManifestParseException>().having(
            (error) => error.code,
            'code',
            UpdateErrorCode.legacyFieldNotSupported,
          ),
        ),
      );
    });

    test('rejects generic artifactUri fields', () {
      expect(
        () => const ManifestParser().parse(_manifestWithAction({
          'type': 'downloadPackage',
          'artifactUri': 'https://example.com/app.apk',
          'packageType': 'apk',
          'sha256': 'a' * 64,
        })),
        throwsA(
          isA<ManifestParseException>().having(
            (error) => error.code,
            'code',
            UpdateErrorCode.legacyFieldNotSupported,
          ),
        ),
      );
    });

    test('requires complete package metadata', () {
      expect(
        () => const ManifestParser().parse(_manifestWithAction({
          'type': 'downloadPackage',
          'packageUrl': 'https://example.com/app.apk',
          'packageType': 'apk',
        })),
        throwsA(isA<ManifestParseException>()),
      );
    });

    test('requires complete installer metadata', () {
      expect(
        () => const ManifestParser().parse(_manifestWithAction({
          'type': 'openInstaller',
          'installerUrl': 'https://example.com/app.dmg',
          'installerType': 'dmg',
        })),
        throwsA(isA<ManifestParseException>()),
      );
    });

    test('allows installPackage actions', () {
      expect(
        () => const ManifestParser().parse(_manifestWithAction({
          'type': 'installPackage',
          'packagePath': '/tmp/app.apk',
          'packageType': 'apk',
        })),
        returnsNormally,
      );
    });

    test('requires SHA-256 for downloadAndInstallPackage actions', () {
      expect(
        () => const ManifestParser().parse(_manifestWithAction({
          'type': 'downloadAndInstallPackage',
          'packageUrl': 'https://example.com/app.apk',
          'packageType': 'apk',
          'packageSizeBytes': 25600000,
        })),
        throwsA(isA<ManifestParseException>()),
      );
    });

    test('rejects malformed SHA-256 metadata', () {
      expect(
        () => const ManifestParser().parse(_manifestWithAction({
          'type': 'downloadPackage',
          'packageUrl': 'https://example.com/app.apk',
          'packageType': 'apk',
          'packageSizeBytes': 42,
          'sha256': 'not-a-sha256',
        })),
        throwsA(
          isA<ManifestParseException>().having(
            (error) => error.code,
            'code',
            UpdateErrorCode.manifestInvalid,
          ),
        ),
      );
    });

    test('rejects non-positive declared artifact sizes', () {
      for (final action in [
        {
          'type': 'downloadPackage',
          'packageUrl': 'https://example.com/app.apk',
          'packageType': 'apk',
          'packageSizeBytes': 0,
          'sha256': 'a' * 64,
        },
        {
          'type': 'downloadAndInstallPackage',
          'packageUrl': 'https://example.com/app.apk',
          'packageType': 'apk',
          'packageSizeBytes': -1,
          'sha256': 'a' * 64,
        },
        {
          'type': 'openInstaller',
          'installerUrl': 'https://example.com/app.dmg',
          'installerType': 'dmg',
          'installerSizeBytes': 0,
          'sha256': 'a' * 64,
        },
      ]) {
        expect(
          () => const ManifestParser().parse(_manifestWithAction(action)),
          throwsA(
            isA<ManifestParseException>().having(
              (error) => error.code,
              'code',
              UpdateErrorCode.manifestInvalid,
            ),
          ),
        );
      }
    });

    test('rejects unsupported action types', () {
      expect(
        () => const ManifestParser().parse(_manifestWithAction({
          'type': 'webDelta',
        })),
        throwsA(
          isA<ManifestParseException>().having(
            (error) => error.code,
            'code',
            UpdateErrorCode.unsupportedActionType,
          ),
        ),
      );
    });

    test('rejects unfinished Play in-app update actions', () {
      expect(
        () => const ManifestParser().parse(_manifestWithAction({
          'type': 'playInAppUpdate',
          'mode': 'immediate',
        })),
        throwsA(
          isA<ManifestParseException>().having(
            (error) => error.code,
            'code',
            UpdateErrorCode.unsupportedActionType,
          ),
        ),
      );
    });

    test('rejects relative action URLs', () {
      for (final action in [
        {
          'type': 'openStore',
          'store': 'googlePlay',
          'storeUrl': 'app.apk',
        },
        {
          'type': 'downloadPackage',
          'packageUrl': '/app.apk',
          'packageType': 'apk',
          'sha256': 'a' * 64,
        },
        {
          'type': 'openInstaller',
          'installerUrl': 'app.dmg',
          'installerType': 'dmg',
          'sha256': 'a' * 64,
        },
      ]) {
        expect(
          () => const ManifestParser().parse(_manifestWithAction(action)),
          throwsA(
            isA<ManifestParseException>().having(
              (error) => error.code,
              'code',
              UpdateErrorCode.manifestInvalid,
            ),
          ),
        );
      }
    });

    test('rejects unknown root, release, and policy fields', () {
      const secretValue = 'must-not-appear-in-the-error';
      const encodedKey = 'unexpected"\nroot';

      final rootManifest = _manifestWithAction(_validActions().first)
        ..[encodedKey] = secretValue;
      final releaseManifest = _manifestWithAction(_validActions().first);
      _releaseOf(releaseManifest)['unexpectedRelease'] = secretValue;
      final policyManifest = _manifestWithAction(_validActions().first);
      _releaseOf(policyManifest)['policy'] = {
        'level': 'recommended',
        'unexpectedPolicy': secretValue,
      };

      final cases = [
        (
          manifest: rootManifest,
          key: encodedKey,
          path: r'$',
        ),
        (
          manifest: releaseManifest,
          key: 'unexpectedRelease',
          path: r'$.releases[0]',
        ),
        (
          manifest: policyManifest,
          key: 'unexpectedPolicy',
          path: r'$.releases[0].policy',
        ),
      ];

      for (final testCase in cases) {
        expect(
          () => const ManifestParser().parse(testCase.manifest),
          throwsA(
            isA<ManifestParseException>()
                .having(
                  (error) => error.code,
                  'code',
                  UpdateErrorCode.manifestInvalid,
                )
                .having(
                  (error) => error.message,
                  'message',
                  allOf(
                    contains(jsonEncode(testCase.key)),
                    contains(testCase.path),
                    isNot(contains(secretValue)),
                  ),
                ),
          ),
          reason: 'field ${testCase.key} at ${testCase.path}',
        );
      }
    });

    test('rejects unknown fields for every action type', () {
      for (final validAction in _validActions()) {
        final action = Map<String, Object?>.from(validAction)
          ..['unexpectedAction'] = 'must-not-appear-in-the-error';

        expect(
          () => const ManifestParser().parse(_manifestWithAction(action)),
          throwsA(
            isA<ManifestParseException>()
                .having(
                  (error) => error.code,
                  'code',
                  UpdateErrorCode.manifestInvalid,
                )
                .having(
                  (error) => error.message,
                  'message',
                  allOf(
                    contains(jsonEncode('unexpectedAction')),
                    contains(r'$.releases[0].actions[0]'),
                    isNot(contains('must-not-appear-in-the-error')),
                  ),
                ),
          ),
          reason: 'action type ${validAction['type']}',
        );
      }
    });

    test('action allowlists are not the union of every action field', () {
      expect(
        () => const ManifestParser().parse(_manifestWithAction({
          'type': 'openStore',
          'store': 'googlePlay',
          'storeUrl': 'https://play.google.com/store/apps/details?id=example',
          'packageUrl': 'https://example.com/app.apk',
        })),
        throwsA(
          isA<ManifestParseException>().having(
            (error) => error.code,
            'code',
            UpdateErrorCode.manifestInvalid,
          ),
        ),
      );
    });

    test('rejects extensions objects', () {
      final manifest = _manifestWithAction(_validActions().first)
        ..['extensions'] = {
          'vendor': 'example',
        };

      expect(
        () => const ManifestParser().parse(manifest),
        throwsA(
          isA<ManifestParseException>().having(
            (error) => error.code,
            'code',
            UpdateErrorCode.manifestInvalid,
          ),
        ),
      );
    });

    test('legacy fields take precedence over unknown-field failures', () {
      final action = Map<String, Object?>.from(_validActions().first)
        ..['downloadUrl'] = 'https://example.com/legacy.apk';
      final manifest = _manifestWithAction(action)
        ..['unexpectedRoot'] = 'ignored-until-legacy-scan-completes';

      expect(
        () => const ManifestParser().parse(manifest),
        throwsA(
          isA<ManifestParseException>().having(
            (error) => error.code,
            'code',
            UpdateErrorCode.legacyFieldNotSupported,
          ),
        ),
      );
    });

    test('accepts non-negative decimal-string build numbers', () {
      for (final buildNumber in ['0', '42', '00042']) {
        final manifest = _manifestWithAction(_validActions().first);
        _releaseOf(manifest)['buildNumber'] = buildNumber;

        final parsed = const ManifestParser().parse(manifest);

        expect(parsed.releases.single.buildNumber, buildNumber);
      }
    });

    test('rejects invalid or overflowing build numbers', () {
      final invalidBuildNumbers = <Object?>[
        42,
        '+1',
        '-1',
        ' 1',
        '1 ',
        '1.0',
        'not-a-number',
        '9' * 100,
      ];

      for (final buildNumber in invalidBuildNumbers) {
        final manifest = _manifestWithAction(_validActions().first);
        _releaseOf(manifest)['buildNumber'] = buildNumber;

        expect(
          () => const ManifestParser().parse(manifest),
          throwsA(
            isA<ManifestParseException>().having(
              (error) => error.code,
              'code',
              UpdateErrorCode.manifestInvalid,
            ),
          ),
          reason: 'buildNumber $buildNumber',
        );
      }
    });

    test('accepts minimum-supported versions at or below the release', () {
      final cases = [
        (release: '2.0.0', minimum: '1.9.9'),
        (release: '2.0.0', minimum: '2.0.0'),
        (release: '2.0.0-rc.2', minimum: '2.0.0-beta.1'),
        (release: '2.0.0-rc.2', minimum: '2.0.0-rc.2'),
      ];

      for (final testCase in cases) {
        final manifest = _manifestWithAction(_validActions().first);
        final release = _releaseOf(manifest)
          ..['version'] = testCase.release
          ..['policy'] = {'minSupportedVersion': testCase.minimum};

        expect(
          () => const ManifestParser().parse(manifest),
          returnsNormally,
          reason: '${testCase.minimum} <= ${release['version']}',
        );
      }
    });

    test('rejects minimum-supported versions above the release', () {
      final cases = [
        (release: '2.0.0', minimum: '2.0.1'),
        (release: '2.0.0-rc.2', minimum: '2.0.0'),
      ];

      for (final testCase in cases) {
        final manifest = _manifestWithAction(_validActions().first);
        _releaseOf(manifest)
          ..['version'] = testCase.release
          ..['policy'] = {'minSupportedVersion': testCase.minimum};

        expect(
          () => const ManifestParser().parse(manifest),
          throwsA(
            isA<ManifestParseException>().having(
              (error) => error.code,
              'code',
              UpdateErrorCode.configurationInvalid,
            ),
          ),
          reason: '${testCase.minimum} > ${testCase.release}',
        );
      }
    });
  });
}

Map<String, Object?> _releaseOf(Map<String, Object?> manifest) {
  return (manifest['releases']! as List<Object?>).single
      as Map<String, Object?>;
}

List<Map<String, Object?>> _validActions() {
  return [
    {
      'type': 'openStore',
      'store': 'googlePlay',
      'storeUrl': 'https://play.google.com/store/apps/details?id=example',
    },
    {
      'type': 'openAndroidMarket',
      'market': 'huawei',
      'targetPackageName': 'com.example.app',
      'fallbackUrl': 'https://example.com/app',
    },
    {
      'type': 'downloadPackage',
      'packageUrl': 'https://example.com/app.apk',
      'packageType': 'apk',
      'packageSizeBytes': 42,
      'sha256': 'a' * 64,
    },
    {
      'type': 'installPackage',
      'packagePath': '/tmp/app.apk',
      'packageType': 'apk',
    },
    {
      'type': 'downloadAndInstallPackage',
      'packageUrl': 'https://example.com/app.apk',
      'packageType': 'apk',
      'packageSizeBytes': 42,
      'sha256': 'a' * 64,
    },
    {
      'type': 'openInstaller',
      'installerUrl': 'https://example.com/app.dmg',
      'installerType': 'dmg',
      'installerSizeBytes': 42,
      'sha256': 'a' * 64,
    },
  ];
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
