import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_app_updater/src/actions/update_action.dart';
import 'package:flutter_app_updater/src/download/package_downloader.dart';
import 'package:flutter_app_updater/src/models/update_error_code.dart';
import 'package:flutter_app_updater/src/platform/update_action_cancel_token.dart';
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
          headers: {'etag': '"v1"'},
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

    test('reports download progress for each chunk', () async {
      final progress = <PackageDownloadProgress>[];
      final bytes = utf8.encode('hello world');
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: {'content-length': '${bytes.length}'},
          bytes: Stream<List<int>>.fromIterable([
            utf8.encode('hello '),
            utf8.encode('world'),
          ]),
        ),
      );

      final result = await PackageDownloader(client: client).download(
        action: _action(sha256: _sha256(bytes)),
        savePath: _path('app.apk'),
        onProgress: progress.add,
      );

      expect(result.isSuccess, isTrue);
      expect(progress.map((event) => event.receivedBytes), [6, 11]);
      expect(progress.map((event) => event.totalBytes), [11, 11]);
    });

    test('reports null total when content length and package size are unknown',
        () async {
      final progress = <PackageDownloadProgress>[];
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {},
          bytes: Stream.value(utf8.encode('bytes')),
        ),
      );

      await PackageDownloader(client: client).download(
        action: DownloadPackageAction(
          packageUrl: Uri.parse('https://example.com/app.apk'),
          packageType: PackageType.apk,
        ),
        savePath: _path('app.apk'),
        onProgress: progress.add,
      );

      expect(progress.single.totalBytes, isNull);
    });

    test('keeps resume metadata aligned after interrupted chunks', () async {
      final controller = StreamController<List<int>>();
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: {'etag': '"v2"', 'content-length': '10'},
          bytes: controller.stream,
        ),
      );

      final download = PackageDownloader(client: client).download(
        action: _action(),
        savePath: _path('app.apk'),
      );

      controller.add(utf8.encode('12345'));
      await Future<void>.delayed(Duration.zero);
      controller.addError(const SocketException('interrupted'));
      await controller.close();

      final result = await download;

      expect(result.isSuccess, isFalse);
      final partial = File('${_path('app.apk')}.download');
      final metadata = File('${partial.path}.meta');
      expect(await partial.exists(), isTrue);
      expect(await metadata.exists(), isTrue);
      final data = jsonDecode(await metadata.readAsString());
      expect(data, isA<Map<String, Object?>>());
      expect((data as Map<String, Object?>)['downloadedBytes'],
          await partial.length());
    });

    test('stops streaming when cancel token is canceled', () async {
      final token = UpdateActionCancelToken();
      final controller = StreamController<List<int>>();
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: {'content-length': '10'},
          bytes: controller.stream,
        ),
      );

      final download = PackageDownloader(client: client).download(
        action: _action(),
        savePath: _path('app.apk'),
        cancelToken: token,
      );

      controller.add(utf8.encode('12345'));
      token.cancel();
      controller.add(utf8.encode('67890'));
      await controller.close();

      final result = await download;

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.actionCanceled);
    });
  });
}

DownloadPackageAction _action({
  Uri? packageUrl,
  String? sha256,
}) {
  return DownloadPackageAction(
    packageUrl: packageUrl ?? Uri.parse('https://example.com/app.apk'),
    packageType: PackageType.apk,
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
