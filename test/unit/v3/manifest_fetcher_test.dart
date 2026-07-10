import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app_updater/src/core/update_source.dart';
import 'package:flutter_app_updater/src/manifest/manifest_fetcher.dart';
import 'package:flutter_app_updater/src/utils/retry_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HttpServer? server;

  tearDown(() async {
    await server?.close(force: true);
  });

  Uri listen(void Function(HttpRequest request) handler) {
    final activeServer = server!;
    activeServer.listen(handler);
    return Uri.parse(
        'http://${activeServer.address.host}:${activeServer.port}');
  }

  Future<void> startServer() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  }

  ManifestUpdateSource source(Uri baseUri) {
    return UpdateSource.manifest(manifestUrl: baseUri.resolve('/manifest'))
        as ManifestUpdateSource;
  }

  group('IoManifestFetcher', () {
    test('retries a transient server failure and returns the manifest',
        () async {
      await startServer();
      var requests = 0;
      final baseUri = listen((request) async {
        requests++;
        if (requests == 1) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_manifest));
        await request.response.close();
      });
      const fetcher = IoManifestFetcher(
        retryStrategy: RetryStrategy(
          maxAttempts: 1,
          initialDelay: Duration.zero,
          enableJitter: false,
        ),
      );

      final result = await fetcher.fetch(source(baseUri));

      expect(result['appId'], 'com.example.app');
      expect(requests, 2);
    });

    test('rejects responses larger than the configured byte limit', () async {
      await startServer();
      final baseUri = listen((request) async {
        request.response.write('x' * 128);
        await request.response.close();
      });
      const fetcher = IoManifestFetcher(
        maxResponseBytes: 32,
        retryStrategy: RetryStrategy.disabled,
      );

      expect(
        () => fetcher.fetch(source(baseUri)),
        throwsA(
          isA<ManifestFetchException>().having(
            (error) => error.message,
            'message',
            contains('32 bytes'),
          ),
        ),
      );
    });

    test('times out a slow response with a structured fetch error', () async {
      await startServer();
      final baseUri = listen((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        try {
          request.response.write(jsonEncode(_manifest));
          await request.response.close();
        } on Object {
          // The client is expected to close the timed-out request.
        }
      });
      const fetcher = IoManifestFetcher(
        requestTimeout: Duration(milliseconds: 20),
        retryStrategy: RetryStrategy.disabled,
      );

      expect(
        () => fetcher.fetch(source(baseUri)),
        throwsA(
          isA<ManifestFetchException>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });

    test('force closes the HTTP client when a request times out', () async {
      final client = _HangingHttpClient();
      const fetcher = IoManifestFetcher(
        requestTimeout: Duration(milliseconds: 20),
        retryStrategy: RetryStrategy.disabled,
      );
      final hangingSource = UpdateSource.manifest(
        manifestUrl: Uri.parse('https://example.com/manifest.json'),
      ) as ManifestUpdateSource;

      await expectLater(
        HttpOverrides.runZoned(
          () => fetcher.fetch(hangingSource),
          createHttpClient: (_) => client,
        ),
        throwsA(isA<ManifestFetchException>()),
      );
      expect(client.forceCloseCalls, greaterThanOrEqualTo(1));
    });

    test('rejects non-HTTP manifest URLs before opening a request', () async {
      const fetcher = IoManifestFetcher(retryStrategy: RetryStrategy.disabled);
      final invalidSource = UpdateSource.manifest(
        manifestUrl: Uri.parse('file:///tmp/manifest.json'),
      ) as ManifestUpdateSource;

      expect(
        () => fetcher.fetch(invalidSource),
        throwsA(
          isA<ManifestFetchException>().having(
            (error) => error.message,
            'message',
            contains('HTTP or HTTPS'),
          ),
        ),
      );
    });
  });
}

const _manifest = <String, Object?>{
  'schemaVersion': 3,
  'appId': 'com.example.app',
  'channel': 'stable',
  'releases': <Object?>[],
};

class _HangingHttpClient extends Fake implements HttpClient {
  final _request = Completer<HttpClientRequest>();
  int forceCloseCalls = 0;
  Duration? _connectionTimeout;

  @override
  Duration? get connectionTimeout => _connectionTimeout;

  @override
  set connectionTimeout(Duration? value) {
    _connectionTimeout = value;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _request.future;

  @override
  void close({bool force = false}) {
    if (force) {
      forceCloseCalls++;
    }
  }
}
