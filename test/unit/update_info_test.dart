import 'package:test/test.dart';
import 'package:flutter_app_updater/src/models/update_info.dart';

void main() {
  group('UpdateInfo', () {
    group('constructor', () {
      test('should create instance with required fields', () {
        final updateInfo = UpdateInfo(
          newVersion: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
          changelog: 'Bug fixes',
        );

        expect(updateInfo.newVersion, equals('2.0.0'));
        expect(updateInfo.downloadUrl, equals('https://example.com/app.apk'));
        expect(updateInfo.changelog, equals('Bug fixes'));
        expect(updateInfo.isForceUpdate, isFalse);
        expect(updateInfo.publishDate, isNull);
        expect(updateInfo.fileSize, isNull);
        expect(updateInfo.md5, isNull);
        expect(updateInfo.extraInfo, isNull);
      });

      test('should create instance with all fields', () {
        final publishDate = DateTime(2025, 11, 17);
        final extraInfo = {'customField': 'value'};

        final updateInfo = UpdateInfo(
          newVersion: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
          changelog: 'Bug fixes',
          isForceUpdate: true,
          publishDate: publishDate,
          fileSize: 1024000,
          md5: 'abc123',
          extraInfo: extraInfo,
        );

        expect(updateInfo.isForceUpdate, isTrue);
        expect(updateInfo.publishDate, equals(publishDate));
        expect(updateInfo.fileSize, equals(1024000));
        expect(updateInfo.md5, equals('abc123'));
        expect(updateInfo.extraInfo, equals(extraInfo));
      });
    });

    group('fromMap', () {
      test('should parse map with default keys', () {
        final data = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
          'changelog': 'Bug fixes and improvements',
          'isForceUpdate': true,
        };

        final updateInfo = UpdateInfo.fromMap(data);

        expect(updateInfo.newVersion, equals('2.0.0'));
        expect(updateInfo.downloadUrl, equals('https://example.com/app.apk'));
        expect(updateInfo.changelog, equals('Bug fixes and improvements'));
        expect(updateInfo.isForceUpdate, isTrue);
      });

      test('should parse map with custom keys', () {
        final data = {
          'newVersionCode': '2.0.0',
          'apkUrl': 'https://example.com/app.apk',
          'updateMessage': 'New features',
          'forceUpdate': false,
        };

        final updateInfo = UpdateInfo.fromMap(
          data,
          versionKey: 'newVersionCode',
          downloadUrlKey: 'apkUrl',
          changelogKey: 'updateMessage',
          isForceUpdateKey: 'forceUpdate',
        );

        expect(updateInfo.newVersion, equals('2.0.0'));
        expect(updateInfo.downloadUrl, equals('https://example.com/app.apk'));
        expect(updateInfo.changelog, equals('New features'));
        expect(updateInfo.isForceUpdate, isFalse);
      });

      test('should convert numeric version to string', () {
        final data1 = {
          'version': 2,
          'downloadUrl': 'https://example.com/app.apk',
        };
        final updateInfo1 = UpdateInfo.fromMap(data1);
        expect(updateInfo1.newVersion, equals('2'));

        final data2 = {
          'version': 2.5,
          'downloadUrl': 'https://example.com/app.apk',
        };
        final updateInfo2 = UpdateInfo.fromMap(data2);
        expect(updateInfo2.newVersion, equals('2.5'));
      });

      test('should handle boolean forceUpdate', () {
        final data1 = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
          'isForceUpdate': true,
        };
        final updateInfo1 = UpdateInfo.fromMap(data1);
        expect(updateInfo1.isForceUpdate, isTrue);

        final data2 = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
          'isForceUpdate': false,
        };
        final updateInfo2 = UpdateInfo.fromMap(data2);
        expect(updateInfo2.isForceUpdate, isFalse);
      });

      test('should handle string forceUpdate', () {
        final data1 = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
          'isForceUpdate': 'true',
        };
        final updateInfo1 = UpdateInfo.fromMap(data1);
        expect(updateInfo1.isForceUpdate, isTrue);

        final data2 = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
          'isForceUpdate': 'false',
        };
        final updateInfo2 = UpdateInfo.fromMap(data2);
        expect(updateInfo2.isForceUpdate, isFalse);

        final data3 = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
          'isForceUpdate': 'TRUE',
        };
        final updateInfo3 = UpdateInfo.fromMap(data3);
        expect(updateInfo3.isForceUpdate, isTrue);
      });

      test('should parse ISO8601 date string', () {
        final data = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
          'publishDate': '2025-11-17T10:30:00.000Z',
        };

        final updateInfo = UpdateInfo.fromMap(data);
        expect(updateInfo.publishDate, isNotNull);
        expect(updateInfo.publishDate!.year, equals(2025));
        expect(updateInfo.publishDate!.month, equals(11));
        expect(updateInfo.publishDate!.day, equals(17));
      });

      test('should parse timestamp date', () {
        final timestamp = DateTime(2025, 11, 17).millisecondsSinceEpoch;
        final data = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
          'publishDate': timestamp,
        };

        final updateInfo = UpdateInfo.fromMap(data);
        expect(updateInfo.publishDate, isNotNull);
        expect(updateInfo.publishDate!.year, equals(2025));
        expect(updateInfo.publishDate!.month, equals(11));
        expect(updateInfo.publishDate!.day, equals(17));
      });

      test('should ignore invalid date format', () {
        final data = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
          'publishDate': 'invalid-date',
        };

        final updateInfo = UpdateInfo.fromMap(data);
        expect(updateInfo.publishDate, isNull);
      });

      test('should parse integer fileSize', () {
        final data = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
          'fileSize': 1024000,
        };

        final updateInfo = UpdateInfo.fromMap(data);
        expect(updateInfo.fileSize, equals(1024000));
      });

      test('should parse string fileSize', () {
        final data = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
          'fileSize': '2048000',
        };

        final updateInfo = UpdateInfo.fromMap(data);
        expect(updateInfo.fileSize, equals(2048000));
      });

      test('should ignore invalid fileSize', () {
        final data = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
          'fileSize': 'invalid',
        };

        final updateInfo = UpdateInfo.fromMap(data);
        expect(updateInfo.fileSize, isNull);
      });

      test('should parse MD5', () {
        final data = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
          'md5': 'abc123def456',
        };

        final updateInfo = UpdateInfo.fromMap(data);
        expect(updateInfo.md5, equals('abc123def456'));
      });

      test('should preserve extra fields', () {
        final data = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
          'customField1': 'value1',
          'customField2': 123,
          'customField3': true,
        };

        final updateInfo = UpdateInfo.fromMap(data);
        expect(updateInfo.extraInfo, isNotNull);
        expect(updateInfo.extraInfo!['customField1'], equals('value1'));
        expect(updateInfo.extraInfo!['customField2'], equals(123));
        expect(updateInfo.extraInfo!['customField3'], isTrue);
      });

      test('should not include standard fields in extraInfo', () {
        final data = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
          'changelog': 'Updates',
          'isForceUpdate': true,
          'customField': 'custom',
        };

        final updateInfo = UpdateInfo.fromMap(data);
        expect(updateInfo.extraInfo, isNotNull);
        expect(updateInfo.extraInfo!.containsKey('version'), isFalse);
        expect(updateInfo.extraInfo!.containsKey('downloadUrl'), isFalse);
        expect(updateInfo.extraInfo!.containsKey('changelog'), isFalse);
        expect(updateInfo.extraInfo!.containsKey('isForceUpdate'), isFalse);
        expect(updateInfo.extraInfo!['customField'], equals('custom'));
      });

      test('should return null extraInfo when no extra fields', () {
        final data = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
        };

        final updateInfo = UpdateInfo.fromMap(data);
        expect(updateInfo.extraInfo, isNull);
      });

      test('should handle missing optional fields', () {
        final data = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
        };

        final updateInfo = UpdateInfo.fromMap(data);
        expect(updateInfo.newVersion, equals('2.0.0'));
        expect(updateInfo.downloadUrl, equals('https://example.com/app.apk'));
        expect(updateInfo.changelog, isEmpty);
        expect(updateInfo.isForceUpdate, isFalse);
        expect(updateInfo.publishDate, isNull);
        expect(updateInfo.fileSize, isNull);
        expect(updateInfo.md5, isNull);
      });
    });

    group('fromJson', () {
      test('should parse JSON string with default keys', () {
        const jsonString = '''
          {
            "version": "2.0.0",
            "downloadUrl": "https://example.com/app.apk",
            "changelog": "Bug fixes",
            "isForceUpdate": true
          }
        ''';

        final updateInfo = UpdateInfo.fromJson(jsonString);
        expect(updateInfo.newVersion, equals('2.0.0'));
        expect(updateInfo.downloadUrl, equals('https://example.com/app.apk'));
        expect(updateInfo.changelog, equals('Bug fixes'));
        expect(updateInfo.isForceUpdate, isTrue);
      });

      test('should parse JSON string with custom keys', () {
        const jsonString = '''
          {
            "newVersionCode": "3.0.0",
            "apkUrl": "https://example.com/v3.apk",
            "updateMessage": "New features",
            "forceUpdate": false
          }
        ''';

        final updateInfo = UpdateInfo.fromJson(
          jsonString,
          versionKey: 'newVersionCode',
          downloadUrlKey: 'apkUrl',
          changelogKey: 'updateMessage',
          isForceUpdateKey: 'forceUpdate',
        );

        expect(updateInfo.newVersion, equals('3.0.0'));
        expect(updateInfo.downloadUrl, equals('https://example.com/v3.apk'));
        expect(updateInfo.changelog, equals('New features'));
        expect(updateInfo.isForceUpdate, isFalse);
      });

      test('should parse JSON with all fields', () {
        const jsonString = '''
          {
            "version": "2.0.0",
            "downloadUrl": "https://example.com/app.apk",
            "changelog": "Updates",
            "isForceUpdate": true,
            "publishDate": "2025-11-17T10:30:00.000Z",
            "fileSize": 1024000,
            "md5": "abc123",
            "customField": "custom value"
          }
        ''';

        final updateInfo = UpdateInfo.fromJson(jsonString);
        expect(updateInfo.newVersion, equals('2.0.0'));
        expect(updateInfo.publishDate, isNotNull);
        expect(updateInfo.fileSize, equals(1024000));
        expect(updateInfo.md5, equals('abc123'));
        expect(updateInfo.extraInfo!['customField'], equals('custom value'));
      });
    });

    group('toMap', () {
      test('should convert to map with default keys', () {
        final updateInfo = UpdateInfo(
          newVersion: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
          changelog: 'Bug fixes',
          isForceUpdate: true,
        );

        final map = updateInfo.toMap();
        expect(map['version'], equals('2.0.0'));
        expect(map['downloadUrl'], equals('https://example.com/app.apk'));
        expect(map['changelog'], equals('Bug fixes'));
        expect(map['isForceUpdate'], isTrue);
      });

      test('should convert to map with custom keys', () {
        final updateInfo = UpdateInfo(
          newVersion: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
          changelog: 'Updates',
          isForceUpdate: false,
        );

        final map = updateInfo.toMap(
          versionKey: 'newVersionCode',
          downloadUrlKey: 'apkUrl',
          changelogKey: 'updateMessage',
          isForceUpdateKey: 'forceUpdate',
        );

        expect(map['newVersionCode'], equals('2.0.0'));
        expect(map['apkUrl'], equals('https://example.com/app.apk'));
        expect(map['updateMessage'], equals('Updates'));
        expect(map['forceUpdate'], isFalse);
      });

      test('should include optional fields when present', () {
        final publishDate = DateTime(2025, 11, 17);
        final updateInfo = UpdateInfo(
          newVersion: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
          changelog: 'Updates',
          publishDate: publishDate,
          fileSize: 1024000,
          md5: 'abc123',
        );

        final map = updateInfo.toMap();
        expect(map['publishDate'], equals(publishDate.toIso8601String()));
        expect(map['fileSize'], equals(1024000));
        expect(map['md5'], equals('abc123'));
      });

      test('should exclude optional fields when keys are null', () {
        final updateInfo = UpdateInfo(
          newVersion: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
          changelog: 'Updates',
        );

        final map = updateInfo.toMap(
          publishDateKey: null,
          fileSizeKey: null,
          md5Key: null,
        );
        expect(map.containsKey('publishDate'), isFalse);
        expect(map.containsKey('fileSize'), isFalse);
        expect(map.containsKey('md5'), isFalse);
      });

      test('should include null values for optional fields when keys provided', () {
        final updateInfo = UpdateInfo(
          newVersion: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
          changelog: 'Updates',
        );

        final map = updateInfo.toMap();
        // With default keys, fields are included even if values are null
        expect(map.containsKey('publishDate'), isTrue);
        expect(map['publishDate'], isNull);
        expect(map.containsKey('fileSize'), isTrue);
        expect(map['fileSize'], isNull);
        expect(map.containsKey('md5'), isTrue);
        expect(map['md5'], isNull);
      });

      test('should include extra fields', () {
        final updateInfo = UpdateInfo(
          newVersion: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
          changelog: 'Updates',
          extraInfo: {'customField': 'value', 'anotherField': 123},
        );

        final map = updateInfo.toMap();
        expect(map['customField'], equals('value'));
        expect(map['anotherField'], equals(123));
      });
    });

    group('toJson', () {
      test('should convert to JSON string', () {
        final updateInfo = UpdateInfo(
          newVersion: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
          changelog: 'Bug fixes',
          isForceUpdate: true,
        );

        final jsonString = updateInfo.toJson();
        expect(jsonString, contains('"version":"2.0.0"'));
        expect(jsonString, contains('"downloadUrl":"https://example.com/app.apk"'));
        expect(jsonString, contains('"changelog":"Bug fixes"'));
        expect(jsonString, contains('"isForceUpdate":true'));
      });

      test('should convert to JSON with custom keys', () {
        final updateInfo = UpdateInfo(
          newVersion: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
          changelog: 'Updates',
        );

        final jsonString = updateInfo.toJson(
          versionKey: 'newVersionCode',
          downloadUrlKey: 'apkUrl',
        );

        expect(jsonString, contains('"newVersionCode":"2.0.0"'));
        expect(jsonString, contains('"apkUrl":"https://example.com/app.apk"'));
      });
    });

    group('round-trip conversion', () {
      test('should maintain data through fromMap -> toMap', () {
        final originalData = {
          'version': '2.0.0',
          'downloadUrl': 'https://example.com/app.apk',
          'changelog': 'Bug fixes',
          'isForceUpdate': true,
          'fileSize': 1024000,
          'md5': 'abc123',
          'customField': 'custom',
        };

        final updateInfo = UpdateInfo.fromMap(originalData);
        final convertedData = updateInfo.toMap();

        expect(convertedData['version'], equals(originalData['version']));
        expect(convertedData['downloadUrl'], equals(originalData['downloadUrl']));
        expect(convertedData['changelog'], equals(originalData['changelog']));
        expect(convertedData['isForceUpdate'], equals(originalData['isForceUpdate']));
        expect(convertedData['fileSize'], equals(originalData['fileSize']));
        expect(convertedData['md5'], equals(originalData['md5']));
        expect(convertedData['customField'], equals(originalData['customField']));
      });

      test('should maintain data through fromJson -> toJson', () {
        const originalJson = '''
          {
            "version": "2.0.0",
            "downloadUrl": "https://example.com/app.apk",
            "changelog": "Bug fixes",
            "isForceUpdate": true
          }
        ''';

        final updateInfo = UpdateInfo.fromJson(originalJson);
        final convertedJson = updateInfo.toJson();

        // Parse both to compare (ignoring whitespace)
        final updateInfo2 = UpdateInfo.fromJson(convertedJson);
        expect(updateInfo2.newVersion, equals(updateInfo.newVersion));
        expect(updateInfo2.downloadUrl, equals(updateInfo.downloadUrl));
        expect(updateInfo2.changelog, equals(updateInfo.changelog));
        expect(updateInfo2.isForceUpdate, equals(updateInfo.isForceUpdate));
      });
    });
  });
}
