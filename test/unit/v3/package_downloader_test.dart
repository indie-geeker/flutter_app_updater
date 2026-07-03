import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_app_updater/src/actions/update_action.dart';
import 'package:flutter_app_updater/src/download/package_downloader.dart';
import 'package:flutter_app_updater/src/models/update_error_code.dart';
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
          bytes: bytes,
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

    test('rejects missing SHA-256', () async {
      final result = await PackageDownloader(client: client).download(
        action: _action(sha256: ''),
        savePath: _path('app.apk'),
      );

      expect(result.isSuccess, isFalse);
      expect(result.code, UpdateErrorCode.missingRequiredField);
      expect(client.requests, isEmpty);
    });

    test('rejects hash mismatch', () async {
      client.enqueue(
        PackageDownloadResponse(
          statusCode: 200,
          headers: const {},
          bytes: utf8.encode('tampered'),
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
          bytes: utf8.encode(' world'),
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
          bytes: bytes,
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
          bytes: bytes,
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
  final _responses = <PackageDownloadResponse>[];

  void enqueue(PackageDownloadResponse response) {
    _responses.add(response);
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
    return _responses.removeAt(0);
  }
}

class _DownloadRequest {
  final Uri url;
  final Map<String, String> headers;

  _DownloadRequest(this.url, this.headers);
}
