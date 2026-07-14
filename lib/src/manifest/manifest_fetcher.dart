import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../core/update_source.dart';
import '../utils/retry_strategy.dart';
import '../utils/trusted_update_uri.dart';
import 'fetched_manifest.dart';

/// Transport boundary for retrieving exact remote manifest bytes.
abstract interface class ManifestFetcher {
  /// Fetches [source] without decoding its response body.
  ///
  /// Implementations should throw [ManifestFetchException] for transport
  /// failures so callers can return a structured update-check result.
  Future<FetchedManifest> fetch(ManifestUpdateSource source);
}

/// Describes a remote manifest transport failure.
class ManifestFetchException implements Exception {
  /// Human-readable transport diagnostic.
  final String message;

  /// HTTP status code, when a response was received.
  final int? statusCode;

  /// Creates a transport failure with an optional HTTP [statusCode].
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

/// Secure `dart:io` implementation of [ManifestFetcher].
///
/// It requires trusted HTTPS by default, follows at most [maxRedirects]
/// manually, rejects HTTPS downgrade, removes caller headers after a
/// cross-origin redirect, bounds the full request duration and response size,
/// and retries only transient failures.
class IoManifestFetcher implements ManifestFetcher {
  /// Maximum number of validated redirects per request.
  static const maxRedirects = 5;

  /// Maximum time allowed to establish a network connection.
  final Duration connectionTimeout;

  /// Maximum duration for the complete fetch, including response streaming.
  final Duration requestTimeout;

  /// Maximum accepted response body size.
  final int maxResponseBytes;

  /// Backoff policy for transient network and server failures.
  final RetryStrategy retryStrategy;

  /// Creates a bounded secure fetcher.
  ///
  /// [fetch] throws [ArgumentError] if either timeout is not positive.
  const IoManifestFetcher({
    this.connectionTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 20),
    this.maxResponseBytes = 1024 * 1024,
    this.retryStrategy = RetryStrategy.standard,
  }) : assert(maxResponseBytes > 0);

  @override
  Future<FetchedManifest> fetch(ManifestUpdateSource source) async {
    if (connectionTimeout.inMicroseconds <= 0 ||
        requestTimeout.inMicroseconds <= 0) {
      throw ArgumentError('Manifest timeouts must be greater than zero.');
    }
    _requireTrustedUri(source.manifestUrl, source);

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

  Future<FetchedManifest> _fetchOnce(
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

  Future<FetchedManifest> _fetchWithClient(
    HttpClient client,
    ManifestUpdateSource source,
  ) async {
    var currentUri = source.manifestUrl;
    var redirectCount = 0;
    while (true) {
      _requireTrustedUri(currentUri, source);
      final request = await client.getUrl(currentUri);
      request.followRedirects = false;
      final headers = source.headers;
      if (headers != null && isSameOrigin(source.manifestUrl, currentUri)) {
        for (final entry in headers.entries) {
          request.headers.set(entry.key, entry.value);
        }
      }

      final response = await request.close();
      if (_isRedirect(response.statusCode)) {
        if (redirectCount >= maxRedirects) {
          throw const ManifestFetchException(
            message: 'Manifest request exceeded the redirect limit of 5.',
          );
        }
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || location.trim().isEmpty) {
          throw const ManifestFetchException(
            message: 'Manifest redirect is missing a Location header.',
          );
        }
        await _drain(response);
        final nextUri = currentUri.resolve(location);
        _requireTrustedUri(nextUri, source);
        currentUri = nextUri;
        redirectCount++;
        continue;
      }

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

      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = values.join(',');
      });
      return FetchedManifest(
        bodyBytes: bodyBytes.takeBytes(),
        finalUri: currentUri,
        responseHeaders: Map.unmodifiable(responseHeaders),
      );
    }
  }

  void _requireTrustedUri(Uri uri, ManifestUpdateSource source) {
    try {
      requireTrustedHttpsUri(
        uri,
        allowInsecureLoopback: source.allowInsecureLoopback,
        field: 'manifestUrl',
      );
    } on ArgumentError catch (error) {
      throw ManifestFetchException(message: error.message.toString());
    }
  }

  bool _isRedirect(int statusCode) {
    return statusCode == HttpStatus.movedPermanently ||
        statusCode == HttpStatus.found ||
        statusCode == HttpStatus.seeOther ||
        statusCode == HttpStatus.temporaryRedirect ||
        statusCode == HttpStatus.permanentRedirect;
  }

  Future<void> _drain(HttpClientResponse response) async {
    if (response.contentLength > maxResponseBytes) {
      throw ManifestFetchException(
        message: 'Manifest redirect response exceeds $maxResponseBytes bytes.',
      );
    }
    var receivedBytes = 0;
    await for (final chunk in response) {
      receivedBytes += chunk.length;
      if (receivedBytes > maxResponseBytes) {
        throw ManifestFetchException(
          message:
              'Manifest redirect response exceeds $maxResponseBytes bytes.',
        );
      }
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
}
