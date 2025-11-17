import 'dart:async';
import 'package:test/test.dart';
import 'package:flutter_app_updater/src/models/update_error.dart';
import '../mocks/mock_http_client.dart';

void main() {
  group('MockHttpClient', () {
    late MockHttpClient mockClient;

    setUp(() {
      mockClient = MockHttpClient();
    });

    tearDown(() {
      mockClient.reset();
    });

    group('basic functionality', () {
      test('should return configured response data', () async {
        final responseData = {'version': '2.0.0', 'downloadUrl': 'https://example.com/app.apk'};
        mockClient.setResponseData(responseData);

        final result = await mockClient.get('https://api.example.com/update');

        expect(result, equals(responseData));
        expect(mockClient.getCallCount, equals(1));
        expect(mockClient.lastUrl, equals('https://api.example.com/update'));
      });

      test('should throw configured error', () async {
        mockClient.mockNetworkError();

        expect(
          () => mockClient.get('https://api.example.com/update'),
          throwsA(isA<UpdateError>()),
        );
      });

      test('should track request details', () async {
        final headers = {'Authorization': 'Bearer token'};
        mockClient.mockSuccessResponse(
          version: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
        );

        await mockClient.get('https://api.example.com/update', headers: headers);

        expect(mockClient.lastUrl, equals('https://api.example.com/update'));
        expect(mockClient.lastHeaders, equals(headers));
      });
    });

    group('mockSuccessResponse', () {
      test('should create valid response with required fields', () async {
        mockClient.mockSuccessResponse(
          version: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
        );

        final result = await mockClient.get('https://api.example.com/update');

        expect(result['version'], equals('2.0.0'));
        expect(result['downloadUrl'], equals('https://example.com/app.apk'));
        expect(result['changelog'], equals('Bug fixes and improvements'));
        expect(result['isForceUpdate'], isFalse);
      });

      test('should include optional fields when provided', () async {
        mockClient.mockSuccessResponse(
          version: '3.0.0',
          downloadUrl: 'https://example.com/v3.apk',
          changelog: 'New features',
          isForceUpdate: true,
          fileSize: 1024000,
          md5: 'abc123',
        );

        final result = await mockClient.get('https://api.example.com/update');

        expect(result['version'], equals('3.0.0'));
        expect(result['isForceUpdate'], isTrue);
        expect(result['fileSize'], equals(1024000));
        expect(result['md5'], equals('abc123'));
      });

      test('should include extra fields', () async {
        mockClient.mockSuccessResponse(
          version: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
          extraFields: {'customField': 'value', 'anotherField': 123},
        );

        final result = await mockClient.get('https://api.example.com/update');

        expect(result['customField'], equals('value'));
        expect(result['anotherField'], equals(123));
      });
    });

    group('error simulation', () {
      test('should simulate network error', () async {
        mockClient.mockNetworkError();

        expect(
          () => mockClient.get('https://api.example.com/update'),
          throwsA(
            predicate((e) =>
                e is UpdateError &&
                e.code == 'NETWORK_ERROR'),
          ),
        );
      });

      test('should simulate server error', () async {
        mockClient.mockServerError(statusCode: 500);

        expect(
          () => mockClient.get('https://api.example.com/update'),
          throwsA(
            predicate((e) =>
                e is UpdateError &&
                e.code == 'SERVER_ERROR'),
          ),
        );
      });

      test('should simulate timeout error', () async {
        mockClient.mockTimeoutError();

        expect(
          () => mockClient.get('https://api.example.com/update'),
          throwsA(isA<TimeoutException>()),
        );
      });

      test('should simulate parse error', () async {
        mockClient.mockParseError();

        expect(
          () => mockClient.get('https://api.example.com/update'),
          throwsA(
            predicate((e) =>
                e is UpdateError &&
                e.code == 'PARSE_ERROR'),
          ),
        );
      });
    });

    group('delay simulation', () {
      test('should simulate network delay', () async {
        mockClient.setDelay(const Duration(milliseconds: 100));
        mockClient.mockSuccessResponse(
          version: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
        );

        final stopwatch = Stopwatch()..start();
        await mockClient.get('https://api.example.com/update');
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(100));
      });
    });

    group('POST requests', () {
      test('should handle POST requests', () async {
        final responseData = {'result': 'success'};
        final requestBody = {'key': 'value'};
        mockClient.setResponseData(responseData);

        final result = await mockClient.post(
          'https://api.example.com/update',
          body: requestBody,
        );

        expect(result, equals(responseData));
        expect(mockClient.postCallCount, equals(1));
        expect(mockClient.lastBody, equals(requestBody));
      });
    });

    group('reset', () {
      test('should reset all state', () async {
        mockClient.mockSuccessResponse(
          version: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
        );
        await mockClient.get('https://api.example.com/update');

        mockClient.reset();

        expect(mockClient.getCallCount, equals(0));
        expect(mockClient.postCallCount, equals(0));
        expect(mockClient.lastUrl, isNull);
        expect(mockClient.lastHeaders, isNull);
        expect(mockClient.lastBody, isNull);
      });
    });

    group('verification helpers', () {
      test('should verify GET was called with URL', () async {
        mockClient.mockSuccessResponse(
          version: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
        );

        await mockClient.get('https://api.example.com/update');

        expect(mockClient.wasGetCalledWith('https://api.example.com/update'), isTrue);
        expect(mockClient.wasGetCalledWith('https://other.example.com/update'), isFalse);
      });

      test('should verify POST was called with URL', () async {
        mockClient.mockSuccessResponse(
          version: '2.0.0',
          downloadUrl: 'https://example.com/app.apk',
        );

        await mockClient.post('https://api.example.com/update');

        expect(mockClient.wasPostCalledWith('https://api.example.com/update'), isTrue);
        expect(mockClient.wasPostCalledWith('https://other.example.com/update'), isFalse);
      });
    });
  });

  group('Helper functions', () {
    test('createMockUpdateResponse should create valid response', () {
      final response = createMockUpdateResponse(
        version: '2.0.0',
        downloadUrl: 'https://example.com/app.apk',
        changelog: 'Updates',
        isForceUpdate: true,
        fileSize: 1024000,
        md5: 'abc123',
      );

      expect(response['version'], equals('2.0.0'));
      expect(response['downloadUrl'], equals('https://example.com/app.apk'));
      expect(response['changelog'], equals('Updates'));
      expect(response['isForceUpdate'], isTrue);
      expect(response['fileSize'], equals(1024000));
      expect(response['md5'], equals('abc123'));
    });

    test('createCustomFieldMockResponse should use custom keys', () {
      final response = createCustomFieldMockResponse(
        versionKey: 'newVersionCode',
        downloadUrlKey: 'apkUrl',
        version: '3.0.0',
        downloadUrl: 'https://example.com/v3.apk',
        extraFields: {'customField': 'value'},
      );

      expect(response['newVersionCode'], equals('3.0.0'));
      expect(response['apkUrl'], equals('https://example.com/v3.apk'));
      expect(response['customField'], equals('value'));
    });
  });
}
