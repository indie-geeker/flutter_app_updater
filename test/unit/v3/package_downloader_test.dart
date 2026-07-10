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

void main() {
  late _FakePackageDownloadClient client;

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

    test('downloads packages without SHA-256', () async {
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
        ),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isTrue);
      expect(result.file?.readAsStringSync(), 'package-without-hash');
      expect(result.sha256, isNull);
      expect(
          client.requests.single.url, Uri.parse('https://example.com/app.apk'));
    });

    test('rejects hash mismatch only when SHA-256 is provided', () async {
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {},
          bytes: Stream.value(utf8.encode('tampered')),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(sha256: 'a' * 64),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.packageHashMismatch);
    });

    test('resumes only when ETag still matches through If-Range', () async {
      final partialFile = File('${_path('app.apk')}.download');
      await partialFile.writeAsString('hello');
      await File('${partialFile.path}.meta').writeAsString(jsonEncode({
        'packageUrl': 'https://example.com/app.apk',
        'etag': '"v1"',
        'downloadedBytes': 5,
      }));

      client.enqueue(
        PackageDownloadResponse(
          statusCode: 206,
          headers: {
            'etag': '"v1"',
            'content-range': 'bytes 5-10/11',
          },
          bytes: Stream.value(utf8.encode(' world')),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(sha256: _sha256(utf8.encode('hello world'))),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isTrue);
      expect(result.file?.readAsStringSync(), 'hello world');
      expect(client.requests.single.headers['range'], 'bytes=5-');
      expect(client.requests.single.headers['if-range'], '"v1"');
    });

    test('rejects a resumed response with the wrong Content-Range', () async {
      final partialFile = File('${_path('app.apk')}.download');
      await partialFile.writeAsString('hello');
      await File('${partialFile.path}.meta').writeAsString(jsonEncode({
        'packageUrl': 'https://example.com/app.apk',
        'etag': '"v1"',
        'downloadedBytes': 5,
      }));
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 206,
          headers: {
            'etag': '"v1"',
            'content-range': 'bytes 0-5/11',
          },
          bytes: Stream.value(utf8.encode(' world')),
        ),
      );

      final result = await PackageDownloader(
        client: client,
        retryStrategy: RetryStrategy.disabled,
      ).download(
        action: _action(sha256: ''),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.packageDownloadFailed);
      expect(await partialFile.exists(), isFalse);
      expect(await File('${partialFile.path}.meta').exists(), isFalse);
    });

    test('starts clean when resume metadata has no validators', () async {
      final partialFile = File('${_path('app.apk')}.download');
      await partialFile.writeAsString('stale');
      await File('${partialFile.path}.meta').writeAsString(jsonEncode({
        'packageUrl': 'https://example.com/app.apk',
        'downloadedBytes': 5,
      }));

      final bytes = utf8.encode('fresh');
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {},
          bytes: Stream.value(bytes),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(sha256: _sha256(bytes)),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isTrue);
      expect(result.file?.readAsStringSync(), 'fresh');
      expect(client.requests.single.headers.containsKey('range'), isFalse);
    });

    test('falls back to clean download when Range is unsupported', () async {
      final partialFile = File('${_path('app.apk')}.download');
      await partialFile.writeAsString('partial');
      await File('${partialFile.path}.meta').writeAsString(jsonEncode({
        'packageUrl': 'https://example.com/app.apk',
        'lastModified': 'Fri, 03 Jul 2026 10:00:00 GMT',
        'downloadedBytes': 7,
      }));

      final bytes = utf8.encode('fresh-package');
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: {
            'last-modified': 'Fri, 03 Jul 2026 10:00:00 GMT',
          },
          bytes: Stream.value(bytes),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(sha256: _sha256(bytes)),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isTrue);
      expect(result.file?.readAsStringSync(), 'fresh-package');
      expect(client.requests.single.headers['range'], 'bytes=7-');
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
        action: _action(sha256: _sha256(bytes)),
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
        action: _action(sha256: _sha256(bytes)),
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
        action: _action(sha256: ''),
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
        action: _action(sha256: _sha256(utf8.encode('hello world'))),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isTrue);
      expect(result.file?.readAsStringSync(), 'hello world');
      expect(client.requests, hasLength(2));
      expect(client.requests[1].headers['range'], 'bytes=5-');
      expect(client.requests[1].headers['if-range'], '"v1"');
    });
  });
}

DownloadPackageAction _action({
  Uri? packageUrl,
  int? packageSizeBytes,
  String? sha256,
}) {
  return DownloadPackageAction(
    packageUrl: packageUrl ?? Uri.parse('https://example.com/app.apk'),
    packageType: PackageType.apk,
    packageSizeBytes: packageSizeBytes,
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
