import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../tool/verification/android_background_download_server.dart';

void main() {
  group('AndroidBackgroundDownloadServer', () {
    late AndroidBackgroundDownloadServer server;
    final payload = List<int>.generate(32, (index) => index);

    setUp(() async {
      server = await AndroidBackgroundDownloadServer.start(
        address: InternetAddress.loopbackIPv4,
        port: 0,
        payload: payload,
      );
    });

    tearDown(() => server.close());

    test('serves a clean 200 response with a strong ETag', () async {
      final response = await _request(server, '/artifact');

      expect(response.statusCode, HttpStatus.ok);
      expect(
          response.headers.value(HttpHeaders.etagHeader), '"verification-v1"');
      expect(response.body, payload);
      expect(response.headers.contentLength, payload.length);
    });

    test('serves the requested suffix as a precise 206 response', () async {
      final response = await _request(
        server,
        '/artifact',
        headers: {
          HttpHeaders.rangeHeader: 'bytes=11-',
          HttpHeaders.ifRangeHeader: '"verification-v1"',
        },
      );

      expect(response.statusCode, HttpStatus.partialContent);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 11-31/32',
      );
      expect(response.headers.contentLength, 21);
      expect(response.body, payload.sublist(11));
    });

    test('falls back to 200 when If-Range does not match', () async {
      final response = await _request(
        server,
        '/artifact',
        headers: {
          HttpHeaders.rangeHeader: 'bytes=11-',
          HttpHeaders.ifRangeHeader: '"old"',
        },
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.body, payload);
    });

    test('can deliberately ignore a Range request', () async {
      await _control(server, {'mode': 'ignoreRange'});

      final response = await _request(
        server,
        '/artifact',
        headers: {HttpHeaders.rangeHeader: 'bytes=11-'},
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(response.body, payload);
      expect(response.headers.value(HttpHeaders.contentRangeHeader), isNull);
    });

    test('emits configurable weak and changing ETags', () async {
      await _control(server, {'etagMode': 'weak'});
      final weak = await _request(server, '/artifact');
      expect(weak.headers.value(HttpHeaders.etagHeader), 'W/"verification-v1"');

      await _control(server, {'etagMode': 'changing'});
      final first = await _request(server, '/artifact');
      final second = await _request(server, '/artifact');
      expect(
          first.headers.value(HttpHeaders.etagHeader), '"verification-v1-1"');
      expect(
          second.headers.value(HttpHeaders.etagHeader), '"verification-v1-2"');
    });

    test('returns an exact 416 at and beyond the payload length', () async {
      for (final offset in [payload.length, payload.length + 1]) {
        final response = await _request(
          server,
          '/artifact',
          headers: {HttpHeaders.rangeHeader: 'bytes=$offset-'},
        );
        expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
        expect(
          response.headers.value(HttpHeaders.contentRangeHeader),
          'bytes */${payload.length}',
        );
        expect(response.body, isEmpty);
      }
    });

    test('can force exact and malformed 416 responses', () async {
      await _control(server, {'mode': 'exact416'});
      final exact = await _request(server, '/artifact');
      expect(exact.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      expect(
        exact.headers.value(HttpHeaders.contentRangeHeader),
        'bytes */${payload.length}',
      );

      await _control(server, {'mode': 'malformed416'});
      final malformed = await _request(server, '/artifact');
      expect(malformed.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      expect(
        malformed.headers.value(HttpHeaders.contentRangeHeader),
        'bytes */not-a-number',
      );
    });

    test('disconnects after the configured number of body bytes', () async {
      await _control(server, {
        'mode': 'disconnect',
        'disconnectAfterBytes': 7,
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(server.uri.resolve('/artifact'));
      final response = await request.close();
      final received = <int>[];
      Object? failure;
      try {
        await for (final chunk in response) {
          received.addAll(chunk);
        }
      } catch (error) {
        failure = error;
      }

      expect(response.statusCode, HttpStatus.ok);
      expect(response.contentLength, payload.length);
      expect(received, payload.sublist(0, 7));
      expect(failure, isNotNull);
    });

    test('can deliver the full payload before an incomplete chunked close',
        () async {
      await _control(server, {
        'mode': 'disconnect',
        'disconnectAfterBytes': payload.length,
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(server.uri.resolve('/artifact'));
      final response = await request.close();
      final received = <int>[];
      Object? failure;
      try {
        await for (final chunk in response) {
          received.addAll(chunk);
        }
      } catch (error) {
        failure = error;
      }

      expect(response.statusCode, HttpStatus.ok);
      expect(response.contentLength, -1);
      expect(
        response.headers.value(HttpHeaders.transferEncodingHeader),
        contains('chunked'),
      );
      expect(received, payload);
      expect(failure, isNotNull);
    });

    test('paces a slow response by configured chunks', () async {
      await _control(server, {
        'mode': 'slow',
        'chunkSize': 8,
        'delayPerChunkMs': 20,
      });

      final stopwatch = Stopwatch()..start();
      final response = await _request(server, '/artifact');
      stopwatch.stop();

      expect(response.body, payload);
      expect(stopwatch.elapsed,
          greaterThanOrEqualTo(const Duration(milliseconds: 60)));
    });

    test('serves an oversized body with chunked transfer encoding', () async {
      await _control(server, {
        'mode': 'oversizedChunked',
        'chunkSize': 5,
        'oversizedBytes': 9,
      });

      final response = await _request(server, '/artifact');

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentLength, -1);
      expect(
        response.headers.value(HttpHeaders.transferEncodingHeader),
        contains('chunked'),
      );
      expect(response.body.length, payload.length + 9);
      expect(response.body.take(payload.length), payload);
    });

    test('exposes health and atomic control state as JSON', () async {
      final health = await _request(server, '/healthz');
      final healthJson =
          jsonDecode(utf8.decode(health.body)) as Map<String, dynamic>;
      expect(health.statusCode, HttpStatus.ok);
      expect(healthJson['status'], 'ok');
      expect(healthJson['sha256'], sha256.convert(payload).toString());

      final changed = await _control(server, {
        'mode': 'slow',
        'etagMode': 'weak',
        'chunkSize': 4,
        'delayPerChunkMs': 3,
      });
      final fetched = await _request(server, '/control');
      final fetchedJson =
          jsonDecode(utf8.decode(fetched.body)) as Map<String, dynamic>;

      expect(changed['mode'], 'slow');
      expect(changed['etagMode'], 'weak');
      expect(
          changed['artifactUrl'], server.uri.resolve('/artifact').toString());
      expect(changed['length'], payload.length);
      expect(changed['sha256'], sha256.convert(payload).toString());
      expect(fetchedJson, changed);
    });

    test('rejects invalid control requests without changing state', () async {
      final before = await _readControl(server);
      final invalidMode = await _request(
        server,
        '/control',
        method: 'POST',
        body: utf8.encode(jsonEncode({'mode': 'unknown'})),
        headers: {HttpHeaders.contentTypeHeader: ContentType.json.mimeType},
      );
      final invalidNumber = await _request(
        server,
        '/control',
        method: 'POST',
        body: utf8.encode(jsonEncode({'chunkSize': 0})),
        headers: {HttpHeaders.contentTypeHeader: ContentType.json.mimeType},
      );

      expect(invalidMode.statusCode, HttpStatus.badRequest);
      expect(invalidNumber.statusCode, HttpStatus.badRequest);
      expect(await _readControl(server), before);
    });

    test('records response decisions and clears observations on control update',
        () async {
      final initial = await _readControl(server);
      expect(initial['observations'], isEmpty);

      await _request(
        server,
        '/artifact',
        headers: {
          HttpHeaders.rangeHeader: 'bytes=11-',
          HttpHeaders.ifRangeHeader: '"verification-v1"',
        },
      );
      await _request(
        server,
        '/artifact',
        headers: {
          HttpHeaders.rangeHeader: 'bytes=13-',
          HttpHeaders.ifRangeHeader: '"stale"',
        },
      );

      final rangeObservations =
          (await _readControl(server))['observations'] as List<dynamic>;
      expect(rangeObservations, [
        {
          'sequence': 1,
          'requestRange': 'bytes=11-',
          'requestIfRange': '"verification-v1"',
          'responseStatus': HttpStatus.partialContent,
          'responseContentRange': 'bytes 11-31/32',
          'responseEtag': '"verification-v1"',
          'sentBytes': 21,
        },
        {
          'sequence': 2,
          'requestRange': 'bytes=13-',
          'requestIfRange': '"stale"',
          'responseStatus': HttpStatus.ok,
          'responseContentRange': null,
          'responseEtag': '"verification-v1"',
          'sentBytes': payload.length,
        },
      ]);

      final reset = await _control(server, {'mode': 'exact416'});
      expect(reset['observations'], isEmpty);
      await _request(server, '/artifact');
      expect((await _readControl(server))['observations'], [
        {
          'sequence': 1,
          'requestRange': null,
          'requestIfRange': null,
          'responseStatus': HttpStatus.requestedRangeNotSatisfiable,
          'responseContentRange': 'bytes */32',
          'responseEtag': '"verification-v1"',
          'sentBytes': 0,
        },
      ]);

      await _control(server, {
        'mode': 'disconnect',
        'disconnectAfterBytes': 7,
      });
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(server.uri.resolve('/artifact'));
      final response = await request.close();
      await expectLater(response.drain<void>(), throwsA(anything));

      expect((await _readControl(server))['observations'], [
        {
          'sequence': 1,
          'requestRange': null,
          'requestIfRange': null,
          'responseStatus': HttpStatus.ok,
          'responseContentRange': null,
          'responseEtag': '"verification-v1"',
          'sentBytes': 7,
        },
      ]);
    });
  });

  group('ServerCliOptions', () {
    test('defaults to a loopback host and the documented port', () {
      final options = ServerCliOptions.parse(const []);

      expect(options.host, '127.0.0.1');
      expect(options.port, 18080);
      expect(options.artifactPath, isNull);
    });

    test('accepts a loopback host, ephemeral port, and artifact', () {
      final options = ServerCliOptions.parse(const [
        '--host',
        '::1',
        '--port',
        '0',
        '--artifact',
        '/tmp/app.apk',
      ]);

      expect(options.host, '::1');
      expect(options.port, 0);
      expect(options.artifactPath, '/tmp/app.apk');
    });

    test('rejects unsafe hosts, invalid ports, and unknown arguments', () {
      expect(
        () => ServerCliOptions.parse(const ['--host', '0.0.0.0']),
        throwsFormatException,
      );
      expect(
        () => ServerCliOptions.parse(const ['--port', '65536']),
        throwsFormatException,
      );
      expect(
        () => ServerCliOptions.parse(const ['--wat']),
        throwsFormatException,
      );
    });
  });

  group('readArtifactBytes', () {
    test('rejects directories even when the path exists', () async {
      final directory = await Directory.systemTemp.createTemp('updater-server');
      addTearDown(() => directory.delete(recursive: true));

      await expectLater(
        readArtifactBytes(directory.path),
        throwsA(
          isA<ArtifactInputException>().having(
            (error) => error.message,
            'message',
            contains('regular file'),
          ),
        ),
      );
    });

    test('rejects files larger than the configured safety limit', () async {
      final directory = await Directory.systemTemp.createTemp('updater-server');
      addTearDown(() => directory.delete(recursive: true));
      final artifact = File('${directory.path}/app.apk');
      await artifact.writeAsBytes([1, 2]);

      await expectLater(
        readArtifactBytes(artifact.path, maximumBytes: 1),
        throwsA(
          isA<ArtifactInputException>().having(
            (error) => error.message,
            'message',
            contains('1 bytes'),
          ),
        ),
      );
    });
  });
}

Future<Map<String, dynamic>> _control(
  AndroidBackgroundDownloadServer server,
  Map<String, dynamic> patch,
) async {
  final response = await _request(
    server,
    '/control',
    method: 'POST',
    body: utf8.encode(jsonEncode(patch)),
    headers: {HttpHeaders.contentTypeHeader: ContentType.json.mimeType},
  );
  expect(response.statusCode, HttpStatus.ok);
  return jsonDecode(utf8.decode(response.body)) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _readControl(
  AndroidBackgroundDownloadServer server,
) async {
  final response = await _request(server, '/control');
  expect(response.statusCode, HttpStatus.ok);
  return jsonDecode(utf8.decode(response.body)) as Map<String, dynamic>;
}

Future<_TestResponse> _request(
  AndroidBackgroundDownloadServer server,
  String path, {
  String method = 'GET',
  Map<String, String> headers = const {},
  List<int>? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, server.uri.resolve(path));
    headers.forEach(request.headers.set);
    if (body != null) {
      request.add(body);
    }
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    return _TestResponse(response.statusCode, response.headers, bytes);
  } finally {
    client.close(force: true);
  }
}

final class _TestResponse {
  const _TestResponse(this.statusCode, this.headers, this.body);

  final int statusCode;
  final HttpHeaders headers;
  final List<int> body;
}
