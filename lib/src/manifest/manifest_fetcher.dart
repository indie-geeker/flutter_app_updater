import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/update_source.dart';
import '../utils/retry_strategy.dart';

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
  final Duration connectionTimeout;
  final Duration requestTimeout;
  final int maxResponseBytes;
  final RetryStrategy retryStrategy;

  const IoManifestFetcher({
    this.connectionTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 20),
    this.maxResponseBytes = 1024 * 1024,
    this.retryStrategy = RetryStrategy.standard,
  }) : assert(maxResponseBytes > 0);

  @override
  Future<Map<String, Object?>> fetch(ManifestUpdateSource source) async {
    if (connectionTimeout.inMicroseconds <= 0 ||
        requestTimeout.inMicroseconds <= 0) {
      throw ArgumentError('Manifest timeouts must be greater than zero.');
    }
    _validateScheme(source.manifestUrl);

    var retryNumber = 0;
    while (true) {
      try {
        return await _fetchOnce(source);
      } on FormatException {
        rethrow;
      } catch (error) {
        if (_shouldRetry(error, retryNumber)) {
          final delay = retryStrategy.getDelay(retryNumber);
          retryNumber++;
          if (delay > Duration.zero) {
            await Future<void>.delayed(delay);
          }
          continue;
        }
        throw _structuredException(error);
      }
    }
  }

  Future<Map<String, Object?>> _fetchOnce(
    ManifestUpdateSource source,
  ) async {
    final client = HttpClient()..connectionTimeout = connectionTimeout;
    try {
      return await _fetchWithClient(client, source).timeout(
        requestTimeout,
        onTimeout: () {
          client.close(force: true);
          throw TimeoutException('Manifest request timed out.');
        },
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, Object?>> _fetchWithClient(
    HttpClient client,
    ManifestUpdateSource source,
  ) async {
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
    if (response.contentLength > maxResponseBytes) {
      throw ManifestFetchException(
        message: 'Manifest response exceeds $maxResponseBytes bytes.',
      );
    }

    final bodyBytes = BytesBuilder(copy: false);
    var receivedBytes = 0;
    await for (final chunk in response) {
      receivedBytes += chunk.length;
      if (receivedBytes > maxResponseBytes) {
        throw ManifestFetchException(
          message: 'Manifest response exceeds $maxResponseBytes bytes.',
        );
      }
      bodyBytes.add(chunk);
    }

    final body = utf8.decode(bodyBytes.takeBytes());
    return _rootObject(jsonDecode(body));
  }

  void _validateScheme(Uri url) {
    if ((url.scheme != 'http' && url.scheme != 'https') || !url.hasAuthority) {
      throw const ManifestFetchException(
        message: 'Manifest URL must be an absolute HTTP or HTTPS URL.',
      );
    }
  }

  bool _shouldRetry(Object error, int retryNumber) {
    if (!retryStrategy.canRetry(retryNumber)) {
      return false;
    }
    if (error is ManifestFetchException) {
      final statusCode = error.statusCode;
      return statusCode != null && statusCode >= 500 && statusCode < 600;
    }
    return retryStrategy.shouldRetry(error, retryNumber);
  }

  ManifestFetchException _structuredException(Object error) {
    if (error is ManifestFetchException) {
      return error;
    }
    if (error is TimeoutException) {
      return ManifestFetchException(
        message: 'Manifest request timed out after '
            '${requestTimeout.inMilliseconds} ms.',
      );
    }
    return ManifestFetchException(
      message: 'Manifest request failed: $error',
    );
  }

  Map<String, Object?> _rootObject(Object? decoded) {
    if (decoded is! Map) {
      throw const FormatException('Manifest JSON root must be an object.');
    }

    final result = <String, Object?>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        throw const FormatException(
          'Manifest JSON root contains a non-string key.',
        );
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }
}
