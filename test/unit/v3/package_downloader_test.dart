import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_app_updater/src/actions/update_action.dart';
import 'package:flutter_app_updater/src/download/package_downloader.dart';
import 'package:flutter_app_updater/src/models/update_error_code.dart';
import 'package:flutter_app_updater/src/platform/update_action_cancel_token.dart';
import 'package:flutter_app_updater/src/utils/retry_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

late Directory _tempDir;
late Map<String, Object?> _resumeVectors;
final Set<String> _executedResumeVectors = <String>{};

void main() {
  late _FakePackageDownloadClient client;

  final fixture = jsonDecode(
    File('test/fixtures/http_resume_vectors.json').readAsStringSync(),
  ) as Map<String, Object?>;
  _resumeVectors = (fixture['vectors'] as Map).cast<String, Object?>();

  setUp(() async {
    _tempDir =
        await Directory.systemTemp.createTemp('package_downloader_test_');
    client = _FakePackageDownloadClient();
  });

  tearDown(() async {
    if (await _tempDir.exists()) {
      await _tempDir.delete(recursive: true);
    }
  });

  tearDownAll(() {
    expect(_executedResumeVectors, _resumeVectors.keys.toSet());
  });

  group('PackageDownloader', () {
    test('closes responses idempotently', () async {
      var closeCalls = 0;
      final response = PackageDownloadResponse(
        statusCode: 200,
        headers: const {},
        bytes: const Stream<List<int>>.empty(),
        onClose: () => closeCalls++,
      );

      await response.close();
      await response.close();

      expect(closeCalls, 1);
    });

    test('uses packageUrl and verifies SHA-256', () async {
      final bytes = utf8.encode('package-bytes');
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: {'etag': '"v1"'},
          bytes: Stream.value(bytes),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(
          packageUrl: Uri.parse('https://example.com/app.apk'),
          sha256: _sha256(bytes),
        ),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isTrue);
      expect(result.file?.readAsStringSync(), 'package-bytes');
      expect(
        client.requests.single.url,
        Uri.parse('https://example.com/app.apk'),
      );
    });

    test('requests identity and verifies an exact clean 200 vector', () async {
      final vector = _vector('clean_200_identity_exact');
      final response = _map(vector['response']);
      final body = utf8.encode(response['body']! as String);
      client.enqueue(
        PackageDownloadResponse(
          statusCode: response['status']! as int,
          headers: {
            'content-encoding': response['contentEncoding']! as String,
            'content-length': '${response['contentLength']}',
          },
          bytes: Stream.value(body),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(
          packageSizeBytes: body.length,
          sha256: vectorSha(vector),
        ),
        savePath: _path('identity.apk'),
      );

      _expectVectorOutcome(vector, result);
      expect(
        client.requests.single.headers['accept-encoding'],
        _map(vector['request'])['acceptEncoding'],
      );
    });

    test('rejects a short clean 200 body and deletes unsafe state', () async {
      final vector = _vector('clean_200_short_body');
      final response = _map(vector['response']);
      client.enqueue(
        PackageDownloadResponse(
          statusCode: response['status']! as int,
          headers: {'content-length': '${response['contentLength']}'},
          bytes: Stream.value(utf8.encode(response['body']! as String)),
        ),
      );

      final savePath = _path('short.apk');
      final result = await PackageDownloader(
        client: client,
        retryStrategy: RetryStrategy.disabled,
      ).download(
        action: _action(
          packageSizeBytes: response['contentLength']! as int,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: savePath,
      );

      _expectVectorOutcome(vector, result);
      expect(await File('$savePath.download').exists(), isFalse);
      expect(await _anyCheckpointExists(savePath), isFalse);
    });

    test('rejects non-identity Content-Encoding without writing', () async {
      final vector = _vector('gzip_rejected');
      final response = _map(vector['response']);
      client.enqueue(
        PackageDownloadResponse(
          statusCode: response['status']! as int,
          headers: {'content-encoding': response['contentEncoding']! as String},
          bytes: Stream.value(utf8.encode(response['body']! as String)),
        ),
      );

      final savePath = _path('gzip.apk');
      final result = await PackageDownloader(
        client: client,
        retryStrategy: RetryStrategy.disabled,
      ).download(action: _action(), savePath: savePath);

      _expectVectorOutcome(vector, result);
      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(await File('$savePath.download').exists(), isFalse);
    });

    test('rejects unsolicited 206 without appending', () async {
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 206,
          headers: const {'content-range': 'bytes 0-4/5'},
          bytes: Stream.value(utf8.encode('hello')),
        ),
      );

      final savePath = _path('unsolicited.apk');
      final result = await PackageDownloader(
        client: client,
        retryStrategy: RetryStrategy.disabled,
      ).download(
        action:
            _action(packageSizeBytes: 5, sha256: _sha256(utf8.encode('hello'))),
        savePath: savePath,
      );

      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(await File('$savePath.download').exists(), isFalse);
    });

    test('downloads packages with complete integrity metadata', () async {
      final bytes = utf8.encode('package-without-hash');
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {},
          bytes: Stream.value(bytes),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: DownloadPackageAction(
          packageUrl: Uri.parse('https://example.com/app.apk'),
          packageType: PackageType.apk,
          packageSizeBytes: bytes.length,
          sha256: _sha256(bytes),
        ),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isTrue);
      expect(result.file?.readAsStringSync(), 'package-without-hash');
      expect(result.sha256, _sha256(bytes));
      expect(
          client.requests.single.url, Uri.parse('https://example.com/app.apk'));
    });

    test('rejects hash mismatch after exact-size verification', () async {
      final vector = _vector('clean_200_hash_mismatch');
      final response = _map(vector['response']);
      client.enqueue(
        PackageDownloadResponse(
          statusCode: response['status']! as int,
          headers: const {},
          bytes: Stream.value(utf8.encode(response['body']! as String)),
        ),
      );

      final body = utf8.encode(response['body']! as String);
      final result = await PackageDownloader(client: client).download(
        action: _action(
          packageSizeBytes: body.length,
          sha256: 'a' * 64,
        ),
        savePath: _path('app.apk'),
      );

      _expectVectorOutcome(vector, result);
      expect(result.code, UpdateErrorCode.packageHashMismatch);
    });

    test('uses a strong ETag checkpoint through Range and If-Range', () async {
      final vector = _vector('strong_etag_resume');
      final checkpoint = _map(vector['checkpoint']);
      final response = _map(vector['response']);
      await _seedCheckpoint(
        savePath: _path('app.apk'),
        body: checkpoint['body']! as String,
        downloadedBytes: checkpoint['bytes']! as int,
        totalBytes: checkpoint['total']! as int,
        etag: checkpoint['etag']! as String,
        sha256: vectorSha(vector),
      );

      client.enqueue(
        PackageDownloadResponse(
          statusCode: response['status']! as int,
          headers: {
            'etag': checkpoint['etag']! as String,
            'content-range': response['contentRange']! as String,
            'content-length': '${response['contentLength']}',
          },
          bytes: Stream.value(utf8.encode(response['body']! as String)),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(
          packageSizeBytes: checkpoint['total']! as int,
          sha256: vectorSha(vector),
        ),
        savePath: _path('app.apk'),
      );

      _expectVectorOutcome(vector, result);
      expect(result.file?.readAsStringSync(), _map(vector['expected'])['body']);
      expect(
        client.requests.single.headers['range'],
        _map(vector['request'])['range'],
      );
      expect(
        client.requests.single.headers['if-range'],
        _map(vector['request'])['ifRange'],
      );
    });

    test('rejects a resumed response with the wrong Content-Range', () async {
      final partialFile = await _seedHelloCheckpoint(_path('app.apk'));
      final vector = _vector('resume_wrong_start');
      final response = _map(vector['response']);
      client.enqueue(
        PackageDownloadResponse(
          statusCode: response['status']! as int,
          headers: {
            'etag': '"v1"',
            'content-range': response['contentRange']! as String,
            'content-length': '${response['contentLength']}',
          },
          bytes: Stream.value(utf8.encode(response['body']! as String)),
        ),
      );

      final result = await PackageDownloader(
        client: client,
        retryStrategy: RetryStrategy.disabled,
      ).download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: _path('app.apk'),
      );

      _expectVectorOutcome(vector, result);
      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(client.requests.single.headers['range'], 'bytes=5-');
      expect(await partialFile.exists(), isFalse);
      expect(await _checkpointSlot(partialFile, 0).exists(), isFalse);
      expect(await _checkpointSlot(partialFile, 1).exists(), isFalse);
    });

    test('rejects resumed body-length and total changes', () async {
      for (final name in ['resume_wrong_body_length', 'resume_changed_total']) {
        final savePath = _path('$name.apk');
        await _seedHelloCheckpoint(savePath);
        final vector = _vector(name);
        final response = _map(vector['response']);
        client.enqueue(
          PackageDownloadResponse(
            statusCode: response['status']! as int,
            headers: {
              'etag': '"v1"',
              'content-range': response['contentRange']! as String,
              'content-length': '${response['contentLength']}',
            },
            bytes: Stream.value(utf8.encode(response['body']! as String)),
          ),
        );

        final result = await PackageDownloader(
          client: client,
          retryStrategy: RetryStrategy.disabled,
        ).download(
          action: _action(
            packageSizeBytes: 11,
            sha256: _sha256(utf8.encode('hello world')),
          ),
          savePath: savePath,
        );

        _expectVectorOutcome(vector, result);
        expect(result.code, UpdateErrorCode.packageDownloadFailed,
            reason: name);
        expect(await File('$savePath.download').exists(), isFalse,
            reason: name);
      }
    });

    test('rejects a resumed response whose strong ETag changed', () async {
      final savePath = _path('changed-etag.apk');
      await _seedHelloCheckpoint(savePath);
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 206,
          headers: const {
            'etag': '"v2"',
            'content-range': 'bytes 5-10/11',
            'content-length': '6',
          },
          bytes: Stream.value(utf8.encode(' world')),
        ),
      );

      final result = await PackageDownloader(
        client: client,
        retryStrategy: RetryStrategy.disabled,
      ).download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: savePath,
      );

      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(await File('$savePath.download').exists(), isFalse);
    });

    test('never resumes a weak ETag checkpoint', () async {
      final vector = _vector('weak_etag_restart');
      final checkpoint = _map(vector['checkpoint']);
      await _seedCheckpoint(
        savePath: _path('app.apk'),
        body: checkpoint['body']! as String,
        downloadedBytes: checkpoint['bytes']! as int,
        totalBytes: checkpoint['total']! as int,
        etag: checkpoint['etag']! as String,
        sha256: _sha256(utf8.encode('fresh')),
      );

      final bytes = utf8.encode('fresh');
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {},
          bytes: Stream.value(bytes),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(packageSizeBytes: bytes.length, sha256: _sha256(bytes)),
        savePath: _path('app.apk'),
      );

      _expectVectorOutcome(vector, result);
      expect(result.file?.readAsStringSync(), 'fresh');
      expect(client.requests.single.headers.containsKey('range'), isFalse);
    });

    test('truncates when a server ignores Range with a clean 200', () async {
      final vector = _vector('range_ignored_200');
      await _seedHelloCheckpoint(
        _path('app.apk'),
        sha256: vectorSha(vector),
        totalBytes: 13,
      );

      final response = _map(vector['response']);
      final bytes = utf8.encode(response['body']! as String);
      client.enqueue(
        PackageDownloadResponse(
          statusCode: response['status']! as int,
          headers: {'content-length': '${response['contentLength']}'},
          bytes: Stream.value(bytes),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action:
            _action(packageSizeBytes: bytes.length, sha256: vectorSha(vector)),
        savePath: _path('app.apk'),
      );

      _expectVectorOutcome(vector, result);
      expect(
        result.file?.readAsStringSync(),
        _map(vector['expected'])['body'],
      );
      expect(client.requests.single.headers['range'], 'bytes=5-');
    });

    test('maps SocketException to package download failure', () async {
      client.enqueueError(const SocketException('offline'));

      final result = await PackageDownloader(client: client).download(
        action: _action(),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.packageDownloadFailed);
    });

    test('maps HandshakeException to package download failure', () async {
      client.enqueueError(const HandshakeException('bad certificate'));

      final result = await PackageDownloader(client: client).download(
        action: _action(),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.packageDownloadFailed);
    });

    test('writes response chunks from a stream', () async {
      final chunks = [
        utf8.encode('large-'),
        utf8.encode('package-'),
        utf8.encode('bytes'),
      ];
      final bytes = chunks.expand((chunk) => chunk).toList();
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {},
          bytes: Stream<List<int>>.fromIterable(chunks),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(
          packageSizeBytes: bytes.length,
          sha256: _sha256(bytes),
        ),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isTrue);
      expect(result.file?.readAsStringSync(), 'large-package-bytes');
    });

    test('reports bounded progress for response chunks', () async {
      final chunks = [utf8.encode('one'), utf8.encode('two')];
      final bytes = chunks.expand((chunk) => chunk).toList();
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: {'content-length': '${bytes.length}'},
          bytes: Stream<List<int>>.fromIterable(chunks),
        ),
      );
      final progress = <PackageDownloadProgress>[];

      final result = await PackageDownloader(client: client).download(
        action: _action(
          packageSizeBytes: bytes.length,
          sha256: _sha256(bytes),
        ),
        savePath: _path('app.apk'),
        onProgress: progress.add,
      );

      expect(result.isSuccess, isTrue);
      expect(progress.map((event) => event.downloadedBytes), [3, 6]);
      expect(progress.map((event) => event.totalBytes), [6, 6]);
      expect(progress.last.fraction, 1);
    });

    test('cancels downloads and deletes partial state', () async {
      final cancelToken = UpdateActionCancelToken();
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: {'etag': '"v1"'},
          bytes: Stream<List<int>>.fromIterable([
            utf8.encode('one'),
            utf8.encode('two'),
          ]),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(),
        savePath: _path('app.apk'),
        cancelToken: cancelToken,
        onProgress: (_) => cancelToken.cancel(),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.actionCanceled);
      expect(await File('${_path('app.apk')}.download').exists(), isFalse);
      expect(await File('${_path('app.apk')}.download.meta').exists(), isFalse);
    });

    test('cancels while waiting for response headers', () async {
      final cancelToken = UpdateActionCancelToken();
      final hangingClient = _HangingPackageDownloadClient();
      final future = PackageDownloader(client: hangingClient).download(
        action: _action(),
        savePath: _path('app.apk'),
        cancelToken: cancelToken,
      );
      await hangingClient.requestStarted.future;

      cancelToken.cancel();
      final result = await future.timeout(const Duration(seconds: 1));

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.actionCanceled);
    });

    test('times out while waiting for response headers', () async {
      final hangingClient = _HangingPackageDownloadClient();

      final result = await PackageDownloader(
        client: hangingClient,
        requestTimeout: const Duration(milliseconds: 10),
        retryStrategy: RetryStrategy.disabled,
      ).download(
        action: _action(),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(result.message, contains('timed out'));
    });

    test('cancels while the response body is stalled', () async {
      final cancelToken = UpdateActionCancelToken();
      final bodyStarted = Completer<void>();
      final streamController = StreamController<List<int>>(
        onListen: bodyStarted.complete,
      );
      var closeCalls = 0;
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {},
          bytes: streamController.stream,
          onClose: () => closeCalls++,
        ),
      );
      final future = PackageDownloader(client: client).download(
        action: _action(),
        savePath: _path('app.apk'),
        cancelToken: cancelToken,
      );
      await bodyStarted.future;

      cancelToken.cancel();
      final result = await future.timeout(const Duration(seconds: 1));

      expect(result.code, UpdateErrorCode.actionCanceled);
      expect(closeCalls, 1);
      await streamController.close();
    });

    test('times out and closes a stalled response body', () async {
      final streamController = StreamController<List<int>>();
      var closeCalls = 0;
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {},
          bytes: streamController.stream,
          onClose: () => closeCalls++,
        ),
      );

      final result = await PackageDownloader(
        client: client,
        idleTimeout: const Duration(milliseconds: 10),
        retryStrategy: RetryStrategy.disabled,
      ).download(
        action: _action(),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(result.message, contains('stalled'));
      expect(closeCalls, 1);
      await streamController.close();
    });

    test('rejects concurrent downloads targeting the same file', () async {
      final cancelToken = UpdateActionCancelToken();
      final hangingClient = _HangingPackageDownloadClient();
      final downloader = PackageDownloader(client: hangingClient);
      final first = downloader.download(
        action: _action(),
        savePath: _path('app.apk'),
        cancelToken: cancelToken,
      );
      await hangingClient.requestStarted.future;

      final second = await downloader
          .download(
            action: _action(),
            savePath: _path('app.apk'),
          )
          .timeout(const Duration(seconds: 1));

      expect(second.code, UpdateErrorCode.downloadInProgress);
      cancelToken.cancel();
      expect((await first).code, UpdateErrorCode.actionCanceled);
    });

    test('enforces maxDownloadBytes while streaming and closes response',
        () async {
      var closeCalls = 0;
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {},
          bytes: Stream.value(utf8.encode('too-large')),
          onClose: () => closeCalls++,
        ),
      );

      final result = await PackageDownloader(
        client: client,
        maxDownloadBytes: 4,
        retryStrategy: RetryStrategy.disabled,
      ).download(
        action: _action(packageSizeBytes: 4, sha256: ''),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.packageTooLarge);
      expect(closeCalls, 1);
      expect(await File('${_path('app.apk')}.download').exists(), isFalse);
    });

    test('rejects oversized declarations before opening the network', () async {
      final result = await PackageDownloader(
        client: client,
        maxDownloadBytes: 4,
      ).download(
        action: _action(packageSizeBytes: 5),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.packageTooLarge);
      expect(client.requests, isEmpty);
    });

    test('closes non-success responses', () async {
      var closeCalls = 0;
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 404,
          headers: const {},
          bytes: const Stream<List<int>>.empty(),
          onClose: () => closeCalls++,
        ),
      );

      final result = await PackageDownloader(
        client: client,
        retryStrategy: RetryStrategy.disabled,
      ).download(
        action: _action(),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isFalse);
      expect(closeCalls, 1);
    });

    test('treats a valid 416 at exact EOF as complete', () async {
      final vector = _vector('range_416_exact_eof');
      final checkpoint = _map(vector['checkpoint']);
      final body = checkpoint['body']! as String;
      final savePath = _path('eof.apk');
      await _seedCheckpoint(
        savePath: savePath,
        body: body,
        downloadedBytes: checkpoint['bytes']! as int,
        totalBytes: checkpoint['total']! as int,
        etag: checkpoint['etag']! as String,
        sha256: _sha256(utf8.encode(body)),
      );
      final response = _map(vector['response']);
      client.enqueue(
        PackageDownloadResponse(
          statusCode: response['status']! as int,
          headers: {'content-range': response['contentRange']! as String},
          bytes: const Stream<List<int>>.empty(),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(
          packageSizeBytes: body.length,
          sha256: _sha256(utf8.encode(body)),
        ),
        savePath: savePath,
      );

      _expectVectorOutcome(vector, result);
      expect(
        result.file?.readAsStringSync(),
        _map(vector['expected'])['body'],
      );
      expect(client.requests, hasLength(1));
    });

    test('malformed 416 gets exactly one clean retry', () async {
      final savePath = _path('malformed-416.apk');
      await _seedHelloCheckpoint(savePath);
      final vector = _vector('range_416_malformed');
      final malformed = _map(vector['response']);
      client.enqueue(
        PackageDownloadResponse(
          statusCode: malformed['status']! as int,
          headers: {'content-range': malformed['contentRange']! as String},
          bytes: const Stream<List<int>>.empty(),
        ),
      );
      final body = utf8.encode('hello world');
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: {'content-length': '${body.length}'},
          bytes: Stream.value(body),
        ),
      );

      final result = await PackageDownloader(
        client: client,
        retryStrategy: RetryStrategy.disabled,
      ).download(
        action: _action(packageSizeBytes: body.length, sha256: _sha256(body)),
        savePath: savePath,
      );

      _expectVectorOutcome(vector, result);
      final expected = _map(vector['expected']);
      final expectedRequests = expected['outcome'] == 'one-clean-retry' ? 2 : 1;
      expect(client.requests, hasLength(expectedRequests));
      expect(client.requests.first.headers['range'], 'bytes=5-');
      expect(client.requests.last.headers.containsKey('range'), isFalse);
    });

    test('overshoot 416 never loops after its one clean retry', () async {
      final vector = _vector('range_416_overshoot');
      final checkpoint = _map(vector['checkpoint']);
      final savePath = _path('overshoot-416.apk');
      await _seedCheckpoint(
        savePath: savePath,
        body: checkpoint['body']! as String,
        downloadedBytes: checkpoint['bytes']! as int,
        totalBytes: checkpoint['total']! as int,
        etag: checkpoint['etag']! as String,
        packageSizeBytes: checkpoint['bytes']! as int,
        sha256: _sha256(utf8.encode(checkpoint['body']! as String)),
      );
      for (var i = 0; i < 2; i++) {
        client.enqueue(
          PackageDownloadResponse(
            statusCode: 416,
            headers: const {'content-range': 'bytes */11'},
            bytes: const Stream<List<int>>.empty(),
          ),
        );
      }

      final result = await PackageDownloader(
        client: client,
        retryStrategy: RetryStrategy.disabled,
      ).download(
        action: _action(
          packageSizeBytes: checkpoint['bytes']! as int,
          sha256: _sha256(utf8.encode(checkpoint['body']! as String)),
        ),
        savePath: savePath,
      );

      _expectVectorOutcome(vector, result, cleanRetryExhausted: true);
      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      final expected = _map(vector['expected']);
      final expectedRequests = expected['outcome'] == 'one-clean-retry' ? 2 : 1;
      expect(client.requests, hasLength(expectedRequests));
      expect(client.requests.last.headers.containsKey('range'), isFalse);
    });

    test('preserves resume headers across manual redirects', () async {
      final savePath = _path('redirect.apk');
      await _seedHelloCheckpoint(savePath);
      final vector = _vector('redirect_resume');
      final redirect = _map(vector['response']);
      client.enqueue(
        PackageDownloadResponse(
          statusCode: redirect['status']! as int,
          headers: {'location': redirect['location']! as String},
          bytes: const Stream<List<int>>.empty(),
        ),
      );
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 206,
          headers: const {
            'etag': '"v1"',
            'content-range': 'bytes 5-10/11',
            'content-length': '6',
          },
          bytes: Stream.value(utf8.encode(' world')),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: savePath,
      );

      _expectVectorOutcome(vector, result);
      expect(client.requests, hasLength(2));
      expect(client.requests.last.url.host, 'cdn.example.com');
      final expected = _map(vector['expected']);
      if (expected['preserveRange'] == true) {
        expect(
          client.requests.last.headers['range'],
          client.requests.first.headers['range'],
        );
        expect(
          client.requests.last.headers['if-range'],
          client.requests.first.headers['if-range'],
        );
      }
    });

    test('rejects HTTPS redirect downgrade', () async {
      final vector = _vector('redirect_https_downgrade');
      final redirect = _map(vector['response']);
      client.enqueue(
        PackageDownloadResponse(
          statusCode: redirect['status']! as int,
          headers: {'location': redirect['location']! as String},
          bytes: const Stream<List<int>>.empty(),
        ),
      );

      final result = await PackageDownloader(
        client: client,
        retryStrategy: RetryStrategy.disabled,
      ).download(action: _action(), savePath: _path('downgrade.apk'));

      _expectVectorOutcome(vector, result);
      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(client.requests, hasLength(1));
    });

    test('allows loopback HTTP tests but rejects production HTTP', () async {
      final rejected = await PackageDownloader(client: client).download(
        action: _action(packageUrl: Uri.parse('http://example.com/app.apk')),
        savePath: _path('insecure.apk'),
      );
      expect(rejected.code, UpdateErrorCode.packageDownloadFailed);
      expect(client.requests, isEmpty);

      final body = utf8.encode('package-bytes');
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: {'content-length': '${body.length}'},
          bytes: Stream.value(body),
        ),
      );
      final allowed = await PackageDownloader(client: client).download(
        action: _action(packageUrl: Uri.parse('http://localhost/app.apk')),
        savePath: _path('loopback.apk'),
      );

      expect(allowed.isSuccess, isTrue);
      expect(client.requests.single.url.host, 'localhost');
    });

    test('bounds redirect loops to five redirects', () async {
      final vector = _vector('redirect_resume');
      final maxRedirects = _map(vector['expected'])['maxRedirects']! as int;
      for (var i = 0; i <= maxRedirects; i++) {
        client.enqueue(
          PackageDownloadResponse(
            statusCode: 302,
            headers: {
              'location': i.isEven
                  ? 'https://cdn.example.com/app.apk'
                  : 'https://example.com/app.apk',
            },
            bytes: const Stream<List<int>>.empty(),
          ),
        );
      }

      final result = await PackageDownloader(
        client: client,
        retryStrategy: RetryStrategy.disabled,
      ).download(action: _action(), savePath: _path('redirect-loop.apk'));

      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(client.requests, hasLength(maxRedirects + 1));
    });

    test('truncates an uncheckpointed tail before resuming', () async {
      final vector = _vector('uncheckpointed_tail');
      final checkpoint = _map(vector['checkpoint']);
      final savePath = _path('tail.apk');
      await _seedCheckpoint(
        savePath: savePath,
        body: checkpoint['body']! as String,
        downloadedBytes: checkpoint['bytes']! as int,
        totalBytes: checkpoint['total']! as int,
        etag: checkpoint['etag']! as String,
        sha256: _sha256(utf8.encode('hello world')),
      );
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 206,
          headers: const {
            'etag': '"v1"',
            'content-range': 'bytes 5-10/11',
            'content-length': '6',
          },
          bytes: Stream.value(utf8.encode(' world')),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: savePath,
      );

      _expectVectorOutcome(vector, result);
      expect(result.file?.readAsStringSync(), 'hello world');
      expect(client.requests.single.headers['range'], 'bytes=5-');
    });

    test('restarts clean when checkpoint bytes are ahead of the file',
        () async {
      final vector = _vector('checkpoint_ahead');
      final checkpoint = _map(vector['checkpoint']);
      final savePath = _path('ahead.apk');
      final fresh = utf8.encode('hello world');
      await _seedCheckpoint(
        savePath: savePath,
        body: checkpoint['body']! as String,
        downloadedBytes: checkpoint['bytes']! as int,
        totalBytes: checkpoint['total']! as int,
        etag: checkpoint['etag']! as String,
        sha256: _sha256(fresh),
      );
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: {'content-length': '${fresh.length}'},
          bytes: Stream.value(fresh),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(packageSizeBytes: fresh.length, sha256: _sha256(fresh)),
        savePath: savePath,
      );

      _expectVectorOutcome(vector, result);
      expect(client.requests.single.headers.containsKey('range'), isFalse);
    });

    test('ignores one corrupt slot and keeps the other valid checkpoint',
        () async {
      final savePath = _path('corrupt-slot.apk');
      final partialFile = await _seedHelloCheckpoint(savePath, revision: 4);
      await _checkpointSlot(partialFile, 1).writeAsString('{corrupt json');
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 206,
          headers: const {
            'etag': '"v1"',
            'content-range': 'bytes 5-10/11',
            'content-length': '6',
          },
          bytes: Stream.value(utf8.encode(' world')),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: savePath,
      );

      expect(result.isSuccess, isTrue);
      expect(client.requests.single.headers['range'], 'bytes=5-');
    });

    test('checkpoint read failures preserve durable state for recovery',
        () async {
      final savePath = _path('checkpoint-read-failure.apk');
      final partialFile = await _seedHelloCheckpoint(savePath);
      final operations = _FaultingFileOperations(
        failReadOnce: (file) => file.path.endsWith('.meta.0'),
      );
      final downloader = PackageDownloader(
        client: client,
        retryStrategy: RetryStrategy.disabled,
        fileOperations: operations,
      );

      final failed = await downloader.download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: savePath,
      );

      expect(failed.code, UpdateErrorCode.packageDownloadFailed);
      expect(client.requests, isEmpty);
      expect(await partialFile.readAsString(), 'hello');
      expect(await _checkpointSlot(partialFile, 0).exists(), isTrue);

      client.enqueue(
        PackageDownloadResponse(
          statusCode: 206,
          headers: const {
            'etag': '"v1"',
            'content-range': 'bytes 5-10/11',
            'content-length': '6',
          },
          bytes: Stream.value(utf8.encode(' world')),
        ),
      );
      final recovered = await downloader.download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: savePath,
      );

      expect(recovered.isSuccess, isTrue);
      expect(client.requests.single.headers['range'], 'bytes=5-');
    });

    test('post-commit metadata cleanup failure is non-fatal and recovers',
        () async {
      final savePath = _path('cleanup-after-commit.apk');
      final partialFile = await _seedHelloCheckpoint(savePath);
      final operations = _FaultingFileOperations(
        failDeleteOnce: (file) =>
            File(savePath).existsSync() && file.path.endsWith('.meta.0'),
      );
      final downloader = PackageDownloader(
        client: client,
        fileOperations: operations,
      );
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 206,
          headers: const {
            'etag': '"v1"',
            'content-range': 'bytes 5-10/11',
            'content-length': '6',
          },
          bytes: Stream.value(utf8.encode(' world')),
        ),
      );

      final committed = await downloader.download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: savePath,
      );

      expect(committed.isSuccess, isTrue);
      expect(await File(savePath).readAsString(), 'hello world');
      expect(await partialFile.exists(), isFalse);
      expect(await _checkpointSlot(partialFile, 0).exists(), isTrue);

      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {'content-length': '11'},
          bytes: Stream.value(utf8.encode('hello world')),
        ),
      );
      final recovered = await downloader.download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: savePath,
      );

      expect(recovered.isSuccess, isTrue);
      expect(client.requests.last.headers.containsKey('range'), isFalse);
      expect(await _checkpointSlot(partialFile, 0).exists(), isFalse);
    });

    test('writes a replacement without deleting the selected valid slot',
        () async {
      final savePath = _path('slot-replacement.apk');
      final partialFile = await _seedHelloCheckpoint(savePath, revision: 4);
      await _writeCheckpointSlot(
        partialFile: partialFile,
        slot: 1,
        revision: 5,
        downloadedBytes: 5,
        totalBytes: 11,
        etag: '"v1"',
        packageSizeBytes: 11,
        sha256: _sha256(utf8.encode('hello world')),
        overrides: const {
          'packageUrl': 'https://stale.example.com/app.apk',
        },
      );
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 206,
          headers: const {
            'etag': '"v1"',
            'content-range': 'bytes 5-10/11',
            'content-length': '6',
          },
          bytes: Stream<List<int>>.multi((controller) {
            controller.add(utf8.encode(' '));
            controller.addError(const SocketException('interrupted'));
            controller.close();
          }),
        ),
      );

      final result = await PackageDownloader(
        client: client,
        retryStrategy: RetryStrategy.disabled,
      ).download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: savePath,
      );

      final selected = _map(
        jsonDecode(await _checkpointSlot(partialFile, 0).readAsString()),
      );
      final replacement = _map(
        jsonDecode(await _checkpointSlot(partialFile, 1).readAsString()),
      );
      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(selected['revision'], 4);
      expect(selected['downloadedBytes'], 5);
      expect(replacement['revision'], 5);
      expect(replacement['downloadedBytes'], 6);
    });

    test('highest valid checkpoint revision wins', () async {
      final savePath = _path('revision.apk');
      final partialFile = await _seedCheckpoint(
        savePath: savePath,
        body: 'hello wor',
        downloadedBytes: 5,
        totalBytes: 11,
        etag: '"v1"',
        sha256: _sha256(utf8.encode('hello world')),
        revision: 1,
      );
      await _writeCheckpointSlot(
        partialFile: partialFile,
        slot: 1,
        revision: 2,
        downloadedBytes: 9,
        totalBytes: 11,
        etag: '"v1"',
        packageSizeBytes: 11,
        sha256: _sha256(utf8.encode('hello world')),
      );
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 206,
          headers: const {
            'etag': '"v1"',
            'content-range': 'bytes 9-10/11',
            'content-length': '2',
          },
          bytes: Stream.value(utf8.encode('ld')),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: savePath,
      );

      expect(result.isSuccess, isTrue);
      expect(client.requests.single.headers['range'], 'bytes=9-');
    });

    test('URL size hash schema and weak ETag changes invalidate checkpoints',
        () async {
      final validHash = _sha256(utf8.encode('hello world'));
      final cases = <String, Map<String, Object?>>{
        'url': {'packageUrl': 'https://other.example.com/app.apk'},
        'size': {'packageSizeBytes': 12},
        'hash': {'sha256': 'a' * 64},
        'schema': {'schemaVersion': 2},
        'etag': {'etag': 'W/"v1"'},
      };

      for (final entry in cases.entries) {
        final savePath = _path('invalid-${entry.key}.apk');
        await _seedCheckpoint(
          savePath: savePath,
          body: 'hello',
          downloadedBytes: 5,
          totalBytes: 11,
          etag: '"v1"',
          sha256: validHash,
          overrides: entry.value,
        );
        final body = utf8.encode('hello world');
        client.enqueue(
          PackageDownloadResponse(
            statusCode: 200,
            headers: {'content-length': '${body.length}'},
            bytes: Stream.value(body),
          ),
        );

        final result = await PackageDownloader(client: client).download(
          action: _action(packageSizeBytes: 11, sha256: validHash),
          savePath: savePath,
        );

        expect(result.isSuccess, isTrue, reason: entry.key);
        expect(
          client.requests.last.headers.containsKey('range'),
          isFalse,
          reason: entry.key,
        );
      }
    });

    test('network failure preserves a durable checkpoint', () async {
      final savePath = _path('offline-resume.apk');
      final partialFile = await _seedHelloCheckpoint(savePath);
      client.enqueueError(const SocketException('offline'));

      final result = await PackageDownloader(
        client: client,
        retryStrategy: RetryStrategy.disabled,
      ).download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: savePath,
      );

      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(client.requests.single.headers['range'], 'bytes=5-');
      expect(await partialFile.readAsString(), 'hello');
      expect(await _checkpointSlot(partialFile, 0).exists(), isTrue);
    });

    test('exhausted transient HTTP retries preserve a durable checkpoint',
        () async {
      final savePath = _path('server-outage-resume.apk');
      final partialFile = await _seedHelloCheckpoint(savePath);
      for (var i = 0; i < 2; i++) {
        client.enqueue(
          PackageDownloadResponse(
            statusCode: 503,
            headers: const {},
            bytes: const Stream<List<int>>.empty(),
          ),
        );
      }

      final result = await PackageDownloader(
        client: client,
        retryStrategy: const RetryStrategy(
          maxAttempts: 1,
          initialDelay: Duration.zero,
          enableJitter: false,
        ),
      ).download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: savePath,
      );

      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(client.requests, hasLength(2));
      expect(client.requests.last.headers['range'], 'bytes=5-');
      expect(await partialFile.readAsString(), 'hello');
      expect(await _checkpointSlot(partialFile, 0).exists(), isTrue);
    });

    for (final statusCode in [408, 429]) {
      test('HTTP $statusCode retries preserve a durable checkpoint', () async {
        final savePath = _path('http-$statusCode-resume.apk');
        final partialFile = await _seedHelloCheckpoint(savePath);
        for (var i = 0; i < 2; i++) {
          client.enqueue(
            PackageDownloadResponse(
              statusCode: statusCode,
              headers: const {},
              bytes: const Stream<List<int>>.empty(),
            ),
          );
        }

        final result = await PackageDownloader(
          client: client,
          retryStrategy: const RetryStrategy(
            maxAttempts: 1,
            initialDelay: Duration.zero,
            enableJitter: false,
          ),
        ).download(
          action: _action(
            packageSizeBytes: 11,
            sha256: _sha256(utf8.encode('hello world')),
          ),
          savePath: savePath,
        );

        expect(result.code, UpdateErrorCode.packageDownloadFailed);
        expect(client.requests, hasLength(2));
        expect(client.requests.last.headers['range'], 'bytes=5-');
        expect(client.requests.last.headers['if-range'], '"v1"');
        expect(await partialFile.readAsString(), 'hello');
        expect(await _checkpointSlot(partialFile, 0).exists(), isTrue);
      });
    }

    test('cancels retry backoff with structured cleanup', () async {
      final savePath = _path('cancel-backoff.apk');
      final partialFile = await _seedHelloCheckpoint(savePath);
      final responseClosed = Completer<void>();
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 503,
          headers: const {},
          bytes: const Stream<List<int>>.empty(),
          onClose: responseClosed.complete,
        ),
      );
      final cancelToken = UpdateActionCancelToken();
      final future = PackageDownloader(
        client: client,
        retryStrategy: const RetryStrategy(
          maxAttempts: 1,
          initialDelay: Duration(minutes: 1),
          enableJitter: false,
        ),
      ).download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: savePath,
        cancelToken: cancelToken,
      );
      await responseClosed.future;
      await Future<void>.delayed(Duration.zero);

      cancelToken.cancel();
      final result = await future.timeout(const Duration(seconds: 1));

      expect(result.code, UpdateErrorCode.actionCanceled);
      expect(await partialFile.exists(), isFalse);
      expect(await _anyCheckpointExists(savePath), isFalse);
    });

    test('retries TLS handshakes and preserves a durable checkpoint', () async {
      final savePath = _path('tls-resume.apk');
      final partialFile = await _seedHelloCheckpoint(savePath);
      client.enqueueError(const HandshakeException('temporary TLS failure'));
      client.enqueueError(const HandshakeException('temporary TLS failure'));

      final result = await PackageDownloader(
        client: client,
        retryStrategy: const RetryStrategy(
          maxAttempts: 1,
          initialDelay: Duration.zero,
          enableJitter: false,
        ),
      ).download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: savePath,
      );

      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(client.requests, hasLength(2));
      expect(client.requests.last.headers['range'], 'bytes=5-');
      expect(await partialFile.readAsString(), 'hello');
      expect(await _checkpointSlot(partialFile, 0).exists(), isTrue);
    });

    test('file write failures are not retried as network failures', () async {
      final savePath = _path('write-error.apk');
      await Directory('$savePath.download').create();
      for (var i = 0; i < 2; i++) {
        client.enqueue(
          PackageDownloadResponse(
            statusCode: 200,
            headers: const {'etag': '"v1"'},
            bytes: Stream.value(utf8.encode('package-bytes')),
          ),
        );
      }

      final result = await PackageDownloader(
        client: client,
        retryStrategy: const RetryStrategy(
          maxAttempts: 1,
          initialDelay: Duration.zero,
          enableJitter: false,
        ),
      ).download(action: _action(), savePath: savePath);

      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(client.requests, hasLength(1));
    });

    test('user cancellation wins over verification failure', () async {
      final cancelToken = UpdateActionCancelToken();
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {'etag': '"v1"'},
          bytes: Stream.value(utf8.encode('tampered')),
        ),
      );

      final savePath = _path('cancel-verify.apk');
      final result = await PackageDownloader(client: client).download(
        action: _action(
          packageSizeBytes: 8,
          sha256: _sha256(utf8.encode('expected')),
        ),
        savePath: savePath,
        cancelToken: cancelToken,
        onProgress: (_) => cancelToken.cancel(),
      );

      expect(result.code, UpdateErrorCode.actionCanceled);
      expect(await File('$savePath.download').exists(), isFalse);
      expect(await _anyCheckpointExists(savePath), isFalse);
    });

    test('checkpoints active durable progress before a terminal stream error',
        () async {
      const checkpointBytes = 4 * 1024 * 1024;
      final firstChunk = List<int>.filled(checkpointBytes, 7);
      final fullBody = [...firstChunk, 8];
      final controller = StreamController<List<int>>();
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: {
            'etag': '"large-v1"',
            'content-length': '${fullBody.length}',
          },
          bytes: controller.stream,
        ),
      );
      final progressReached = Completer<void>();
      final savePath = _path('active-checkpoint.apk');
      final future = PackageDownloader(
        client: client,
        retryStrategy: RetryStrategy.disabled,
      ).download(
        action: _action(
          packageSizeBytes: fullBody.length,
          sha256: _sha256(fullBody),
        ),
        savePath: savePath,
        onProgress: (progress) {
          if (progress.downloadedBytes >= checkpointBytes &&
              !progressReached.isCompleted) {
            progressReached.complete();
          }
        },
      );

      controller.add(firstChunk);
      await progressReached.future;
      final checkpointExistedBeforeError = await _waitForCheckpoint(savePath);
      controller.addError(const SocketException('interrupted'));
      await controller.close();
      final result = await future;

      expect(checkpointExistedBeforeError, isTrue);
      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(await _anyCheckpointExists(savePath), isTrue);
    });

    test('checkpoints after two seconds of active progress without sleeping',
        () async {
      final clock = _ManualCheckpointClock();
      final controller = StreamController<List<int>>();
      final savePath = _path('time-checkpoint.apk');
      var checkpointExistedAtSecondProgress = false;
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {
            'etag': '"v1"',
            'content-length': '11',
          },
          bytes: controller.stream,
        ),
      );
      final firstProgress = Completer<void>();
      final secondProgress = Completer<void>();
      final future = PackageDownloader(
        client: client,
        checkpointPolicy: const PackageDownloadCheckpointPolicy(
          byteInterval: 1024 * 1024,
          timeInterval: Duration(seconds: 2),
        ),
        checkpointClockFactory: () => clock,
      ).download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: savePath,
        onProgress: (progress) {
          if (progress.downloadedBytes == 5 && !firstProgress.isCompleted) {
            firstProgress.complete();
          }
          if (progress.downloadedBytes == 6 && !secondProgress.isCompleted) {
            checkpointExistedAtSecondProgress =
                _checkpointSlot(File('$savePath.download'), 1).existsSync();
            secondProgress.complete();
          }
        },
      );

      controller.add(utf8.encode('hello'));
      await firstProgress.future;
      clock.advance(const Duration(seconds: 2));
      controller.add(utf8.encode(' '));
      await secondProgress.future;
      controller.add(utf8.encode('world'));
      await controller.close();
      final result = await future;

      expect(checkpointExistedAtSecondProgress, isTrue);
      expect(result.isSuccess, isTrue);
    });

    test('retries an interrupted stream using Range and If-Range', () async {
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: {'etag': '"v1"'},
          bytes: Stream<List<int>>.multi((controller) {
            controller.add(utf8.encode('hello'));
            controller.addError(const SocketException('interrupted'));
            controller.close();
          }),
        ),
      );
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 206,
          headers: {
            'etag': '"v1"',
            'content-range': 'bytes 5-10/11',
            'content-length': '6',
          },
          bytes: Stream.value(utf8.encode(' world')),
        ),
      );

      final result = await PackageDownloader(
        client: client,
        retryStrategy: const RetryStrategy(
          maxAttempts: 1,
          initialDelay: Duration.zero,
          enableJitter: false,
        ),
      ).download(
        action: _action(
          packageSizeBytes: 11,
          sha256: _sha256(utf8.encode('hello world')),
        ),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isTrue);
      expect(result.file?.readAsStringSync(), 'hello world');
      expect(client.requests, hasLength(2));
      expect(client.requests[1].headers['range'], 'bytes=5-');
      expect(client.requests[1].headers['if-range'], '"v1"');
    });
  });

  group('IoPackageDownloadClient loopback', () {
    test('sends identity, keeps gzip raw, and rejects nonidentity', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final compressed = gzip.encode(utf8.encode('package-bytes'));
      final acceptEncodings = <String?>[];
      server.listen((request) async {
        acceptEncodings.add(
          request.headers.value(HttpHeaders.acceptEncodingHeader),
        );
        request.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        request.response.contentLength = compressed.length;
        request.response.add(compressed);
        await request.response.close();
      });
      final url = Uri.parse('http://127.0.0.1:${server.port}/package');
      const ioClient = IoPackageDownloadClient();

      try {
        final direct = await ioClient.get(
          url,
          headers: const {'accept-encoding': 'identity'},
        );
        final rawBody = await direct.bytes.expand((chunk) => chunk).toList();
        expect(rawBody, compressed);
        expect(direct.contentEncoding, 'gzip');
        await direct.close();

        final result = await PackageDownloader(
          client: ioClient,
          retryStrategy: RetryStrategy.disabled,
        ).download(
          action: _action(packageUrl: url),
          savePath: _path('real-gzip.apk'),
        );

        expect(result.code, UpdateErrorCode.packageDownloadFailed);
        expect(acceptEncodings, ['identity', 'identity']);
      } finally {
        await server.close(force: true);
      }
    });

    test('cancels a real request waiting for response headers', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestReceived = Completer<void>();
      server.listen((_) {
        if (!requestReceived.isCompleted) {
          requestReceived.complete();
        }
      });
      final url = Uri.parse('http://127.0.0.1:${server.port}/slow');
      final cancelToken = UpdateActionCancelToken();

      try {
        final future = PackageDownloader(
          client: const IoPackageDownloadClient(
            requestTimeout: Duration(seconds: 5),
          ),
          requestTimeout: const Duration(seconds: 5),
        ).download(
          action: _action(packageUrl: url),
          savePath: _path('real-cancel.apk'),
          cancelToken: cancelToken,
        );
        await requestReceived.future;

        cancelToken.cancel();
        final result = await future.timeout(const Duration(seconds: 1));

        expect(result.code, UpdateErrorCode.actionCanceled);
      } finally {
        await server.close(force: true);
      }
    });

    test('preserves resume headers across a real redirect', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final receivedHeaders = <Map<String, String?>>[];
      server.listen((request) async {
        receivedHeaders.add({
          'range': request.headers.value(HttpHeaders.rangeHeader),
          'if-range': request.headers.value('if-range'),
          'accept-encoding':
              request.headers.value(HttpHeaders.acceptEncodingHeader),
        });
        if (request.uri.path == '/start') {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(HttpHeaders.locationHeader, '/final');
        } else {
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(HttpHeaders.etagHeader, '"v1"');
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 5-10/11',
          );
          request.response.contentLength = 6;
          request.response.add(utf8.encode(' world'));
        }
        await request.response.close();
      });
      final url = Uri.parse('http://127.0.0.1:${server.port}/start');
      final savePath = _path('real-redirect.apk');
      await _seedCheckpoint(
        savePath: savePath,
        body: 'hello',
        downloadedBytes: 5,
        totalBytes: 11,
        etag: '"v1"',
        sha256: _sha256(utf8.encode('hello world')),
        overrides: {'packageUrl': url.toString()},
      );

      try {
        final result = await PackageDownloader(
          client: const IoPackageDownloadClient(),
        ).download(
          action: _action(
            packageUrl: url,
            packageSizeBytes: 11,
            sha256: _sha256(utf8.encode('hello world')),
          ),
          savePath: savePath,
        );

        expect(result.isSuccess, isTrue);
        expect(result.file?.readAsStringSync(), 'hello world');
        expect(receivedHeaders, hasLength(2));
        for (final headers in receivedHeaders) {
          expect(headers['range'], 'bytes=5-');
          expect(headers['if-range'], '"v1"');
          expect(headers['accept-encoding'], 'identity');
        }
      } finally {
        await server.close(force: true);
      }
    });
  });
}

Map<String, Object?> _vector(String name) {
  _executedResumeVectors.add(name);
  return _map(_resumeVectors[name]);
}

Map<String, Object?> _map(Object? value) {
  return (value as Map).cast<String, Object?>();
}

void _expectVectorOutcome(
  Map<String, Object?> vector,
  PackageDownloadResult result, {
  bool cleanRetryExhausted = false,
}) {
  final outcome = _map(vector['expected'])['outcome']! as String;
  final expectsSuccess = switch (outcome) {
    'complete' ||
    'clean-restart' ||
    'truncate-to-checkpoint' ||
    'follow' =>
      true,
    'one-clean-retry' => !cleanRetryExhausted,
    'integrity-failure' || 'hash-mismatch' || 'protocol-failure' => false,
    _ => throw StateError('Unknown fixture outcome: $outcome'),
  };
  expect(result.isSuccess, expectsSuccess, reason: outcome);
}

String vectorSha(Map<String, Object?> vector) {
  return _map(vector['expected'])['sha256']! as String;
}

Future<File> _seedHelloCheckpoint(
  String savePath, {
  String? sha256,
  int totalBytes = 11,
  int revision = 1,
}) {
  return _seedCheckpoint(
    savePath: savePath,
    body: 'hello',
    downloadedBytes: 5,
    totalBytes: totalBytes,
    etag: '"v1"',
    sha256: sha256 ?? _sha256(utf8.encode('hello world')),
    revision: revision,
  );
}

Future<File> _seedCheckpoint({
  required String savePath,
  required String body,
  required int downloadedBytes,
  required int totalBytes,
  required String etag,
  required String sha256,
  int? packageSizeBytes,
  int revision = 1,
  Map<String, Object?> overrides = const {},
}) async {
  final partialFile = File('$savePath.download');
  await partialFile.writeAsString(body);
  await _writeCheckpointSlot(
    partialFile: partialFile,
    slot: 0,
    revision: revision,
    downloadedBytes: downloadedBytes,
    totalBytes: totalBytes,
    etag: etag,
    packageSizeBytes: packageSizeBytes ?? totalBytes,
    sha256: sha256,
    overrides: overrides,
  );
  return partialFile;
}

Future<void> _writeCheckpointSlot({
  required File partialFile,
  required int slot,
  required int revision,
  required int downloadedBytes,
  required int totalBytes,
  required String etag,
  required int packageSizeBytes,
  required String sha256,
  Map<String, Object?> overrides = const {},
}) async {
  final metadata = <String, Object?>{
    'schemaVersion': 1,
    'revision': revision,
    'packageUrl': 'https://example.com/app.apk',
    'downloadedBytes': downloadedBytes,
    'packageSizeBytes': packageSizeBytes,
    'sha256': sha256.toLowerCase(),
    'etag': etag,
    'totalBytes': totalBytes,
    ...overrides,
  };
  await _checkpointSlot(partialFile, slot).writeAsString(jsonEncode(metadata));
}

File _checkpointSlot(File partialFile, int slot) {
  return File('${partialFile.path}.meta.$slot');
}

Future<bool> _anyCheckpointExists(String savePath) async {
  final partialFile = File('$savePath.download');
  return await _checkpointSlot(partialFile, 0).exists() ||
      await _checkpointSlot(partialFile, 1).exists();
}

Future<bool> _waitForCheckpoint(String savePath) async {
  for (var i = 0; i < 50; i++) {
    if (await _anyCheckpointExists(savePath)) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return false;
}

DownloadPackageAction _action({
  Uri? packageUrl,
  int? packageSizeBytes,
  String? sha256,
}) {
  return DownloadPackageAction(
    packageUrl: packageUrl ?? Uri.parse('https://example.com/app.apk'),
    packageType: PackageType.apk,
    packageSizeBytes: packageSizeBytes ?? utf8.encode('package-bytes').length,
    sha256: sha256 ?? _sha256(utf8.encode('package-bytes')),
  );
}

String _sha256(List<int> bytes) => crypto.sha256.convert(bytes).toString();

String _path(String name) => '${_tempDir.path}/$name';

class _FakePackageDownloadClient implements PackageDownloadClient {
  final requests = <_DownloadRequest>[];
  final _responses = <Object>[];

  void enqueue(PackageDownloadResponse response) {
    _responses.add(response);
  }

  void enqueueError(Exception error) {
    _responses.add(error);
  }

  @override
  Future<PackageDownloadResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
    UpdateActionCancelToken? cancelToken,
  }) async {
    requests.add(_DownloadRequest(url, Map.of(headers)));
    if (_responses.isEmpty) {
      throw StateError('No response queued.');
    }
    final response = _responses.removeAt(0);
    if (response is Exception) {
      throw response;
    }
    return response as PackageDownloadResponse;
  }
}

class _DownloadRequest {
  final Uri url;
  final Map<String, String> headers;

  _DownloadRequest(this.url, this.headers);
}

class _HangingPackageDownloadClient implements PackageDownloadClient {
  final requestStarted = Completer<void>();
  final _response = Completer<PackageDownloadResponse>();

  @override
  Future<PackageDownloadResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
    UpdateActionCancelToken? cancelToken,
  }) {
    if (!requestStarted.isCompleted) {
      requestStarted.complete();
    }
    return _response.future;
  }
}

class _FaultingFileOperations extends PackageDownloadFileOperations {
  final bool Function(File file)? _failReadOnce;
  final bool Function(File file)? _failDeleteOnce;
  bool _readFailed = false;
  bool _deleteFailed = false;

  _FaultingFileOperations({
    bool Function(File file)? failReadOnce,
    bool Function(File file)? failDeleteOnce,
  })  : _failReadOnce = failReadOnce,
        _failDeleteOnce = failDeleteOnce;

  @override
  Future<String> readAsString(File file) {
    if (!_readFailed && (_failReadOnce?.call(file) ?? false)) {
      _readFailed = true;
      throw FileSystemException('Injected checkpoint read failure', file.path);
    }
    return super.readAsString(file);
  }

  @override
  Future<void> delete(File file) {
    if (!_deleteFailed && (_failDeleteOnce?.call(file) ?? false)) {
      _deleteFailed = true;
      throw FileSystemException('Injected metadata delete failure', file.path);
    }
    return super.delete(file);
  }
}

class _ManualCheckpointClock implements PackageDownloadCheckpointClock {
  Duration _elapsed = Duration.zero;

  @override
  Duration get elapsed => _elapsed;

  void advance(Duration duration) {
    _elapsed += duration;
  }

  @override
  void reset() {
    _elapsed = Duration.zero;
  }
}
