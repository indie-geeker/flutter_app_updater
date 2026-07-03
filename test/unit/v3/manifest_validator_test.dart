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

    test('allows package actions without sha256', () {
      expect(
        () => const ManifestParser().parse(_manifestWithAction({
          'type': 'downloadPackage',
          'packageUrl': 'https://example.com/app.apk',
          'packageType': 'apk',
        })),
        returnsNormally,
      );
    });

    test('allows installer actions without sha256', () {
      expect(
        () => const ManifestParser().parse(_manifestWithAction({
          'type': 'openInstaller',
          'installerUrl': 'https://example.com/app.dmg',
          'installerType': 'dmg',
        })),
        returnsNormally,
      );
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
  });
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
