import 'dart:convert';
import 'dart:io';

import '../core/update_source.dart';

abstract interface class ManifestFetcher {
  Future<Map<String, Object?>> fetch(ManifestUpdateSource source);
}

class ManifestFetchException implements Exception {
  final String message;
  final int? statusCode;

  const ManifestFetchException({
    required this.message,
    this.statusCode,
  });

  @override
  String toString() {
    final status = statusCode == null ? '' : ' (HTTP $statusCode)';
    return 'ManifestFetchException$status: $message';
  }
}

class IoManifestFetcher implements ManifestFetcher {
  const IoManifestFetcher();

  @override
  Future<Map<String, Object?>> fetch(ManifestUpdateSource source) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(source.manifestUrl);
      final headers = source.headers;
      if (headers != null) {
        for (final entry in headers.entries) {
          request.headers.set(entry.key, entry.value);
        }
      }

      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw ManifestFetchException(
          message: 'Manifest request failed with HTTP ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }

      final body = await utf8.decodeStream(response);
      return _rootObject(jsonDecode(body));
    } finally {
      client.close(force: true);
    }
  }

  Map<String, Object?> _rootObject(Object? decoded) {
    if (decoded is! Map) {
      throw const FormatException('Manifest JSON root must be an object.');
    }

    final result = <String, Object?>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        throw const FormatException(
            'Manifest JSON root contains a non-string key.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }
}
