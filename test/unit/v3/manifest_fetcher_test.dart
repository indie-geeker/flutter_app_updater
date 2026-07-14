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
    return UpdateSource.manifest(
      manifestUrl: baseUri.resolve('/manifest'),
      expectedAppId: 'com.example.app',
      allowInsecureLoopback: true,
    ) as ManifestUpdateSource;
  }

  group('IoManifestFetcher', () {
    test('rejects public HTTP before opening a request', () async {
      final client = _RoutingHttpClient((_, __) => _okResponse());
      final publicHttpSource = UpdateSource.manifest(
        manifestUrl: Uri.parse('http://updates.example.com/manifest.json'),
        expectedAppId: 'com.example.app',
      ) as ManifestUpdateSource;

      await expectLater(
        HttpOverrides.runZoned(
          () => const IoManifestFetcher().fetch(publicHttpSource),
          createHttpClient: (_) => client,
        ),
        throwsA(isA<ManifestFetchException>()),
      );
      expect(client.requests, isEmpty);
    });

    test('rejects loopback HTTP by default', () async {
      final client = _RoutingHttpClient((_, __) => _okResponse());
      final loopbackSource = UpdateSource.manifest(
        manifestUrl: Uri.parse('http://127.0.0.1/manifest.json'),
        expectedAppId: 'com.example.app',
      ) as ManifestUpdateSource;

      await expectLater(
        HttpOverrides.runZoned(
          () => const IoManifestFetcher().fetch(loopbackSource),
          createHttpClient: (_) => client,
        ),
        throwsA(isA<ManifestFetchException>()),
      );
      expect(client.requests, isEmpty);
    });

    test('accepts HTTPS manifest URLs', () async {
      final client = _RoutingHttpClient((_, __) => _okResponse());
      final httpsSource = UpdateSource.manifest(
        manifestUrl: Uri.parse('https://updates.example.com/manifest.json'),
        expectedAppId: 'com.example.app',
      ) as ManifestUpdateSource;

      final result = await HttpOverrides.runZoned(
        () => const IoManifestFetcher().fetch(httpsSource),
        createHttpClient: (_) => client,
      );

      expect(result['appId'], 'com.example.app');
      expect(client.requests, hasLength(1));
    });

    test('limits redirects to five', () async {
      final client = _RoutingHttpClient(
        (_, requestNumber) => _redirectResponse('/hop-$requestNumber'),
      );
      final redirectingSource = UpdateSource.manifest(
        manifestUrl: Uri.parse('https://updates.example.com/start'),
        expectedAppId: 'com.example.app',
      ) as ManifestUpdateSource;

      await expectLater(
        HttpOverrides.runZoned(
          () => const IoManifestFetcher().fetch(redirectingSource),
          createHttpClient: (_) => client,
        ),
        throwsA(
          isA<ManifestFetchException>().having(
            (error) => error.message,
            'message',
            contains('redirect'),
          ),
        ),
      );
      expect(client.requests, hasLength(6));
    });

    test('revalidates redirects and rejects HTTPS downgrade', () async {
      final client = _RoutingHttpClient(
        (_, __) => _redirectResponse('http://updates.example.com/insecure'),
      );
      final redirectingSource = UpdateSource.manifest(
        manifestUrl: Uri.parse('https://updates.example.com/start'),
        expectedAppId: 'com.example.app',
      ) as ManifestUpdateSource;

      await expectLater(
        HttpOverrides.runZoned(
          () => const IoManifestFetcher().fetch(redirectingSource),
          createHttpClient: (_) => client,
        ),
        throwsA(isA<ManifestFetchException>()),
      );
      expect(client.requests, hasLength(1));
    });

    test('rejects URI user information before opening a request', () async {
      final client = _RoutingHttpClient((_, __) => _okResponse());
      final credentialSource = UpdateSource.manifest(
        manifestUrl: Uri.parse(
          'https://user:password@updates.example.com/manifest.json',
        ),
        expectedAppId: 'com.example.app',
      ) as ManifestUpdateSource;

      await expectLater(
        HttpOverrides.runZoned(
          () => const IoManifestFetcher().fetch(credentialSource),
          createHttpClient: (_) => client,
        ),
        throwsA(isA<ManifestFetchException>()),
      );
      expect(client.requests, isEmpty);
    });

    test('drops caller headers on cross-origin redirects', () async {
      final client = _RoutingHttpClient(
        (uri, __) => uri.host == 'updates.example.com'
            ? _redirectResponse('https://cdn.example.com/manifest.json')
            : _okResponse(),
      );
      final redirectingSource = UpdateSource.manifest(
        manifestUrl: Uri.parse('https://updates.example.com/start'),
        expectedAppId: 'com.example.app',
        headers: const {'authorization': 'Bearer secret'},
      ) as ManifestUpdateSource;

      await HttpOverrides.runZoned(
        () => const IoManifestFetcher().fetch(redirectingSource),
        createHttpClient: (_) => client,
      );

      expect(client.requests, hasLength(2));
      expect(
        client.requests.first.headers.value('authorization'),
        'Bearer secret',
      );
      expect(client.requests.last.headers.value('authorization'), isNull);
    });

    test('keeps caller headers on same-origin redirects', () async {
      final client = _RoutingHttpClient(
        (uri, __) => uri.path == '/start'
            ? _redirectResponse('/manifest.json')
            : _okResponse(),
      );
      final redirectingSource = UpdateSource.manifest(
        manifestUrl: Uri.parse('https://updates.example.com/start'),
        expectedAppId: 'com.example.app',
        headers: const {'authorization': 'Bearer secret'},
      ) as ManifestUpdateSource;

      await HttpOverrides.runZoned(
        () => const IoManifestFetcher().fetch(redirectingSource),
        createHttpClient: (_) => client,
      );

      expect(client.requests, hasLength(2));
      for (final request in client.requests) {
        expect(request.headers.value('authorization'), 'Bearer secret');
      }
    });

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
        expectedAppId: 'com.example.app',
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
        expectedAppId: 'com.example.app',
      ) as ManifestUpdateSource;

      expect(
        () => fetcher.fetch(invalidSource),
        throwsA(
          isA<ManifestFetchException>().having(
            (error) => error.message,
            'message',
            contains('absolute URL'),
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

class _RoutingHttpClient extends Fake implements HttpClient {
  final HttpClientResponse Function(Uri uri, int requestNumber) responder;
  final requests = <_RecordedRequest>[];
  Duration? _connectionTimeout;

  _RoutingHttpClient(this.responder);

  @override
  Duration? get connectionTimeout => _connectionTimeout;

  @override
  set connectionTimeout(Duration? value) {
    _connectionTimeout = value;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final request = _RecordedRequest(
      url,
      () => responder(url, requests.length),
    );
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) {}
}

class _RecordedRequest extends Fake implements HttpClientRequest {
  @override
  final Uri uri;
  final HttpClientResponse Function() response;
  final _MemoryHeaders _headers = _MemoryHeaders();
  bool _followRedirects = true;

  _RecordedRequest(this.uri, this.response);

  @override
  HttpHeaders get headers => _headers;

  @override
  bool get followRedirects => _followRedirects;

  @override
  set followRedirects(bool value) {
    _followRedirects = value;
  }

  @override
  Future<HttpClientResponse> close() async => response();
}

class _MemoryHeaders extends Fake implements HttpHeaders {
  final values = <String, String>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) => values[name.toLowerCase()];
}

class _MemoryResponse extends Fake implements HttpClientResponse {
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  final HttpHeaders headers;
  final Stream<List<int>> _body;

  _MemoryResponse({
    required this.statusCode,
    required List<int> body,
    String? location,
  })  : contentLength = body.length,
        headers = _MemoryHeaders()
          ..set(HttpHeaders.locationHeader, location ?? ''),
        _body = Stream<List<int>>.value(body);

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _body.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

HttpClientResponse _okResponse() => _MemoryResponse(
      statusCode: HttpStatus.ok,
      body: utf8.encode(jsonEncode(_manifest)),
    );

HttpClientResponse _redirectResponse(String location) => _MemoryResponse(
      statusCode: HttpStatus.found,
      body: const [],
      location: location,
    );
