import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../actions/update_action.dart';
import '../models/update_error_code.dart';
import 'package_download_result.dart';

export 'package_download_result.dart';

abstract class PackageDownloadClient {
  Future<PackageDownloadResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
  });
}

class PackageDownloadResponse {
  final int statusCode;
  final Map<String, String> headers;
  final List<int> bytes;

  const PackageDownloadResponse({
    required this.statusCode,
    required this.headers,
    required this.bytes,
  });

  String? get etag => _header('etag');

  String? get lastModified => _header('last-modified');

  String? _header(String name) {
    return headers[name] ?? headers[name.toLowerCase()];
  }
}

class IoPackageDownloadClient implements PackageDownloadClient {
  @override
  Future<PackageDownloadResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      headers.forEach(request.headers.set);
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }

      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        if (values.isNotEmpty) {
          responseHeaders[name.toLowerCase()] = values.join(',');
        }
      });

      return PackageDownloadResponse(
        statusCode: response.statusCode,
        headers: responseHeaders,
        bytes: bytes,
      );
    } finally {
      client.close();
    }
  }
}

class PackageDownloader {
  final PackageDownloadClient client;

  PackageDownloader({
    PackageDownloadClient? client,
  }) : client = client ?? IoPackageDownloadClient();

  Future<PackageDownloadResult> download({
    required DownloadPackageAction action,
    required String savePath,
  }) async {
    if (action.sha256.trim().isEmpty) {
      return const PackageDownloadResult.failure(
        code: UpdateErrorCode.missingRequiredField,
        message: 'sha256 is required for package downloads.',
      );
    }

    final targetFile = File(savePath);
    final partialFile = File('$savePath.download');
    final metadataFile = File('${partialFile.path}.meta');

    try {
      await targetFile.parent.create(recursive: true);
      final resume = await _readResumeMetadata(
        action: action,
        partialFile: partialFile,
        metadataFile: metadataFile,
      );

      final requestHeaders = <String, String>{};
      if (resume != null) {
        requestHeaders['range'] = 'bytes=${resume.downloadedBytes}-';
        requestHeaders['if-range'] = resume.validator;
      }

      final response = await client.get(
        action.packageUrl,
        headers: requestHeaders,
      );

      final isResumeResponse = resume != null && response.statusCode == 206;
      final isCleanResponse = response.statusCode == 200;
      if (!isResumeResponse && !isCleanResponse) {
        return PackageDownloadResult.failure(
          code: UpdateErrorCode.packageDownloadFailed,
          message:
              'Unexpected package download status: ${response.statusCode}.',
        );
      }

      final sink = partialFile.openWrite(
        mode: isResumeResponse ? FileMode.append : FileMode.write,
      );
      sink.add(response.bytes);
      await sink.flush();
      await sink.close();

      await _writeResumeMetadata(
        action: action,
        response: response,
        partialFile: partialFile,
        metadataFile: metadataFile,
      );

      final actualSha256 = await _sha256Of(partialFile);
      if (actualSha256 != action.sha256.toLowerCase().trim()) {
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
        return const PackageDownloadResult.failure(
          code: UpdateErrorCode.packageHashMismatch,
          message: 'Package SHA-256 does not match.',
        );
      }

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      final finalFile = await partialFile.rename(savePath);
      if (await metadataFile.exists()) {
        await metadataFile.delete();
      }

      return PackageDownloadResult.success(
        file: finalFile,
        downloadedBytes: await finalFile.length(),
        sha256: actualSha256,
      );
    } on FileSystemException catch (error) {
      return PackageDownloadResult.failure(
        code: UpdateErrorCode.packageDownloadFailed,
        message: error.message,
      );
    } on FormatException catch (error) {
      return PackageDownloadResult.failure(
        code: UpdateErrorCode.packageDownloadFailed,
        message: error.message,
      );
    }
  }

  Future<_ResumeMetadata?> _readResumeMetadata({
    required DownloadPackageAction action,
    required File partialFile,
    required File metadataFile,
  }) async {
    if (!await partialFile.exists() || !await metadataFile.exists()) {
      return null;
    }

    final data = jsonDecode(await metadataFile.readAsString());
    if (data is! Map<String, Object?>) {
      return null;
    }

    final packageUrl = data['packageUrl'];
    final downloadedBytes = data['downloadedBytes'];
    final etag = data['etag'];
    final lastModified = data['lastModified'];
    final validator = etag is String && etag.isNotEmpty
        ? etag
        : lastModified is String && lastModified.isNotEmpty
            ? lastModified
            : null;

    if (packageUrl != action.packageUrl.toString() ||
        downloadedBytes is! int ||
        downloadedBytes <= 0 ||
        validator == null ||
        await partialFile.length() != downloadedBytes) {
      return null;
    }

    return _ResumeMetadata(
      downloadedBytes: downloadedBytes,
      validator: validator,
    );
  }

  Future<void> _writeResumeMetadata({
    required DownloadPackageAction action,
    required PackageDownloadResponse response,
    required File partialFile,
    required File metadataFile,
  }) async {
    final data = <String, Object?>{
      'packageUrl': action.packageUrl.toString(),
      'etag': response.etag,
      'lastModified': response.lastModified,
      'downloadedBytes': await partialFile.length(),
    };
    await metadataFile.writeAsString(jsonEncode(data));
  }

  Future<String> _sha256Of(File file) async {
    return crypto.sha256.bind(file.openRead()).first.then((digest) {
      return digest.toString().toLowerCase();
    });
  }
}

class _ResumeMetadata {
  final int downloadedBytes;
  final String validator;

  const _ResumeMetadata({
    required this.downloadedBytes,
    required this.validator,
  });
}
