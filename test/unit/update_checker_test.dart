import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app_updater/src/utils/update_checker.dart';
import 'package:flutter_app_updater/src/models/update_error.dart';

void main() {
  group('UpdateChecker', () {
    group('constructor validation', () {
      test('should require either updateUrl or onCheckUpdate', () {
        expect(
          () => UpdateChecker(currentVersion: '1.0.0'),
          throwsA(isA<AssertionError>()),
        );
      });

      test('should accept updateUrl', () {
        expect(
          () => UpdateChecker(
            currentVersion: '1.0.0',
            updateUrl: 'https://api.example.com/update',
          ),
          returnsNormally,
        );
      });

      test('should accept onCheckUpdate callback', () {
        expect(
          () => UpdateChecker(
            currentVersion: '1.0.0',
            onCheckUpdate: () async => {'version': '2.0.0', 'downloadUrl': 'https://example.com/app.apk'},
          ),
          returnsNormally,
        );
      });
    });

    group('checkForUpdate with onCheckUpdate callback', () {
      test('should detect newer version', () async {
        final checker = UpdateChecker(
          currentVersion: '1.0.0',
          onCheckUpdate: () async => {
            'version': '2.0.0',
            'downloadUrl': 'https://example.com/app.apk',
            'changelog': 'New features',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
        expect(updateInfo!.newVersion, equals('2.0.0'));
        expect(updateInfo.downloadUrl, equals('https://example.com/app.apk'));
        expect(updateInfo.changelog, equals('New features'));
      });

      test('should return null for same version', () async {
        final checker = UpdateChecker(
          currentVersion: '2.0.0',
          onCheckUpdate: () async => {
            'version': '2.0.0',
            'downloadUrl': 'https://example.com/app.apk',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNull);
      });

      test('should return null for older version', () async {
        final checker = UpdateChecker(
          currentVersion: '3.0.0',
          onCheckUpdate: () async => {
            'version': '2.0.0',
            'downloadUrl': 'https://example.com/app.apk',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNull);
      });

      test('should handle force update flag', () async {
        final checker = UpdateChecker(
          currentVersion: '1.0.0',
          onCheckUpdate: () async => {
            'version': '2.0.0',
            'downloadUrl': 'https://example.com/app.apk',
            'isForceUpdate': true,
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
        expect(updateInfo!.isForceUpdate, isTrue);
      });

      test('should parse all update info fields', () async {
        final checker = UpdateChecker(
          currentVersion: '1.0.0',
          onCheckUpdate: () async => {
            'version': '2.0.0',
            'downloadUrl': 'https://example.com/app.apk',
            'changelog': 'Bug fixes',
            'isForceUpdate': false,
            'fileSize': 1024000,
            'md5': 'abc123',
            'publishDate': '2025-11-17T10:30:00.000Z',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
        expect(updateInfo!.fileSize, equals(1024000));
        expect(updateInfo.md5, equals('abc123'));
        expect(updateInfo.publishDate, isNotNull);
      });

      test('should preserve extra fields', () async {
        final checker = UpdateChecker(
          currentVersion: '1.0.0',
          onCheckUpdate: () async => {
            'version': '2.0.0',
            'downloadUrl': 'https://example.com/app.apk',
            'customField': 'custom value',
            'anotherField': 123,
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
        expect(updateInfo!.extraInfo, isNotNull);
        expect(updateInfo.extraInfo!['customField'], equals('custom value'));
        expect(updateInfo.extraInfo!['anotherField'], equals(123));
      });

      test('should handle version with v prefix', () async {
        final checker = UpdateChecker(
          currentVersion: 'v1.0.0',
          onCheckUpdate: () async => {
            'version': 'v2.0.0',
            'downloadUrl': 'https://example.com/app.apk',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
        expect(updateInfo!.newVersion, equals('v2.0.0'));
      });

      test('should handle numeric version comparison', () async {
        final checker = UpdateChecker(
          currentVersion: '1.9.0',
          onCheckUpdate: () async => {
            'version': '1.10.0',
            'downloadUrl': 'https://example.com/app.apk',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
      });

      test('should handle pre-release versions', () async {
        final checker = UpdateChecker(
          currentVersion: '1.0.0-beta',
          onCheckUpdate: () async => {
            'version': '1.0.0',
            'downloadUrl': 'https://example.com/app.apk',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
      });

      test('should throw UpdateError when callback throws', () async {
        final checker = UpdateChecker(
          currentVersion: '1.0.0',
          onCheckUpdate: () async => throw Exception('Network error'),
        );

        expect(
          () => checker.checkForUpdate(),
          throwsA(isA<UpdateError>()),
        );
      });
    });

    group('custom field mapping', () {
      test('should use custom version key', () async {
        final checker = UpdateChecker(
          currentVersion: '1.0.0',
          versionKey: 'newVersionCode',
          downloadUrlKey: 'apkUrl',
          onCheckUpdate: () async => {
            'newVersionCode': '2.0.0',
            'apkUrl': 'https://example.com/app.apk',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
        expect(updateInfo!.newVersion, equals('2.0.0'));
        expect(updateInfo.downloadUrl, equals('https://example.com/app.apk'));
      });

      test('should use custom changelog key', () async {
        final checker = UpdateChecker(
          currentVersion: '1.0.0',
          changelogKey: 'updateMessage',
          onCheckUpdate: () async => {
            'version': '2.0.0',
            'downloadUrl': 'https://example.com/app.apk',
            'updateMessage': 'Custom changelog',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
        expect(updateInfo!.changelog, equals('Custom changelog'));
      });

      test('should use custom force update key', () async {
        final checker = UpdateChecker(
          currentVersion: '1.0.0',
          isForceUpdateKey: 'forceUpdate',
          onCheckUpdate: () async => {
            'version': '2.0.0',
            'downloadUrl': 'https://example.com/app.apk',
            'forceUpdate': true,
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
        expect(updateInfo!.isForceUpdate, isTrue);
      });

      test('should use all custom keys', () async {
        final checker = UpdateChecker(
          currentVersion: '1.0.0',
          versionKey: 'ver',
          downloadUrlKey: 'url',
          changelogKey: 'notes',
          isForceUpdateKey: 'force',
          publishDateKey: 'date',
          fileSizeKey: 'size',
          md5Key: 'hash',
          onCheckUpdate: () async => {
            'ver': '2.0.0',
            'url': 'https://example.com/app.apk',
            'notes': 'Notes',
            'force': true,
            'date': '2025-11-17T10:30:00.000Z',
            'size': 1024000,
            'hash': 'abc123',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
        expect(updateInfo!.newVersion, equals('2.0.0'));
        expect(updateInfo.downloadUrl, equals('https://example.com/app.apk'));
        expect(updateInfo.changelog, equals('Notes'));
        expect(updateInfo.isForceUpdate, isTrue);
        expect(updateInfo.fileSize, equals(1024000));
        expect(updateInfo.md5, equals('abc123'));
      });
    });

    group('version comparison edge cases', () {
      test('should handle version padding (1.0 vs 1.0.0)', () async {
        final checker = UpdateChecker(
          currentVersion: '1.0',
          onCheckUpdate: () async => {
            'version': '1.0.0',
            'downloadUrl': 'https://example.com/app.apk',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNull);
      });

      test('should handle build numbers', () async {
        final checker = UpdateChecker(
          currentVersion: '1.0.0+1',
          onCheckUpdate: () async => {
            'version': '1.0.0+2',
            'downloadUrl': 'https://example.com/app.apk',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        // Build numbers are ignored, versions are considered the same
        expect(updateInfo, isNull);
      });

      test('should handle very long version numbers', () async {
        final checker = UpdateChecker(
          currentVersion: '1.2.3.4.5',
          onCheckUpdate: () async => {
            'version': '1.2.3.4.6',
            'downloadUrl': 'https://example.com/app.apk',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
      });

      test('should handle major version difference', () async {
        final checker = UpdateChecker(
          currentVersion: '1.999.999',
          onCheckUpdate: () async => {
            'version': '2.0.0',
            'downloadUrl': 'https://example.com/app.apk',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
      });

      test('should handle minor version difference', () async {
        final checker = UpdateChecker(
          currentVersion: '1.99.0',
          onCheckUpdate: () async => {
            'version': '1.100.0',
            'downloadUrl': 'https://example.com/app.apk',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
      });
    });

    group('error handling', () {
      test('should wrap exceptions in UpdateError', () async {
        final checker = UpdateChecker(
          currentVersion: '1.0.0',
          onCheckUpdate: () async => throw Exception('Test error'),
        );

        expect(
          () => checker.checkForUpdate(),
          throwsA(
            predicate((e) =>
                e is UpdateError &&
                e.code == 'PARSE_ERROR'),
          ),
        );
      });

      test('should preserve UpdateError from callback', () async {
        const originalError = UpdateError(
          code: 'CUSTOM_ERROR',
          message: 'Custom error message',
        );

        final checker = UpdateChecker(
          currentVersion: '1.0.0',
          onCheckUpdate: () async => throw originalError,
        );

        expect(
          () => checker.checkForUpdate(),
          throwsA(
            predicate((e) =>
                e is UpdateError &&
                e.code == 'PARSE_ERROR'),
          ),
        );
      });

      test('should handle missing required fields', () async {
        final checker = UpdateChecker(
          currentVersion: '1.0.0',
          onCheckUpdate: () async => {
            // Missing downloadUrl
            'version': '2.0.0',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        // Should still work, just with empty downloadUrl
        expect(updateInfo, isNotNull);
        expect(updateInfo!.downloadUrl, isEmpty);
      });

      test('should handle invalid version format', () async {
        final checker = UpdateChecker(
          currentVersion: '1.0.0',
          onCheckUpdate: () async => {
            'version': null,
            'downloadUrl': 'https://example.com/app.apk',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        // Should handle null version gracefully
        expect(updateInfo, isNotNull);
      });
    });

    group('real-world scenarios', () {
      test('should handle typical update check flow', () async {
        final checker = UpdateChecker(
          currentVersion: '1.5.3',
          onCheckUpdate: () async => {
            'version': '1.6.0',
            'downloadUrl': 'https://cdn.example.com/app-1.6.0.apk',
            'changelog': '- Bug fixes\n- Performance improvements\n- New features',
            'isForceUpdate': false,
            'fileSize': 25600000, // 25.6 MB
            'md5': 'a1b2c3d4e5f6',
            'publishDate': '2025-11-17T10:00:00.000Z',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
        expect(updateInfo!.newVersion, equals('1.6.0'));
        expect(updateInfo.isForceUpdate, isFalse);
        expect(updateInfo.fileSize, equals(25600000));
      });

      test('should handle force update scenario', () async {
        final checker = UpdateChecker(
          currentVersion: '1.0.0',
          onCheckUpdate: () async => {
            'version': '2.0.0',
            'downloadUrl': 'https://cdn.example.com/app-2.0.0.apk',
            'changelog': 'Critical security update - please update immediately',
            'isForceUpdate': true,
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
        expect(updateInfo!.isForceUpdate, isTrue);
      });

      test('should handle already up-to-date scenario', () async {
        final checker = UpdateChecker(
          currentVersion: '2.5.0',
          onCheckUpdate: () async => {
            'version': '2.5.0',
            'downloadUrl': 'https://cdn.example.com/app-2.5.0.apk',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNull);
      });

      test('should handle beta to stable upgrade', () async {
        final checker = UpdateChecker(
          currentVersion: '2.0.0-beta.5',
          onCheckUpdate: () async => {
            'version': '2.0.0',
            'downloadUrl': 'https://cdn.example.com/app-2.0.0.apk',
            'changelog': 'Stable release',
          },
        );

        final updateInfo = await checker.checkForUpdate();

        expect(updateInfo, isNotNull);
      });
    });
  });
}
