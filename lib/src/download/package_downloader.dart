import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import '../actions/update_action.dart';
import '../models/update_error_code.dart';
import '../platform/update_action_cancel_token.dart';
import '../utils/retry_strategy.dart';
import 'package_download_result.dart';

export 'package_download_result.dart';

abstract class PackageDownloadClient {
  Future<PackageDownloadResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
    UpdateActionCancelToken? cancelToken,
  });
}

class PackageDownloadResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Stream<List<int>> bytes;
  final FutureOr<void> Function()? _onClose;
  bool _isClosed = false;

  PackageDownloadResponse({
    required this.statusCode,
    required this.headers,
    required this.bytes,
    FutureOr<void> Function()? onClose,
  }) : _onClose = onClose;

  String? get etag => _header('etag');

  String? get lastModified => _header('last-modified');

  String? get contentRange => _header('content-range');

  int? get contentLength {
    final value = _header('content-length');
    return value == null ? null : int.tryParse(value);
  }

  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;
    await _onClose?.call();
  }

  String? _header(String name) {
    return headers[name] ?? headers[name.toLowerCase()];
  }
}

class IoPackageDownloadClient implements PackageDownloadClient {
  final Duration connectionTimeout;
  final Duration requestTimeout;

  const IoPackageDownloadClient({
    this.connectionTimeout = const Duration(seconds: 10),
    this.requestTimeout = const Duration(seconds: 30),
  });

  @override
  Future<PackageDownloadResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
    UpdateActionCancelToken? cancelToken,
  }) async {
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw const FormatException(
        'Package URL must use HTTP or HTTPS.',
      );
    }
    final client = HttpClient()..connectionTimeout = connectionTimeout;
    try {
      final requestFuture = _open(client, url, headers);
      final futures = <Future<PackageDownloadResponse>>[requestFuture];
      if (cancelToken != null) {
        futures.add(
          cancelToken.whenCanceled.then<PackageDownloadResponse>((_) {
            client.close(force: true);
            throw const _PackageDownloadCanceled();
          }),
        );
      }
      return await Future.any(futures).timeout(
        requestTimeout,
        onTimeout: () {
          client.close(force: true);
          throw TimeoutException(
            'Package request timed out after $requestTimeout.',
          );
        },
      );
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }

  Future<PackageDownloadResponse> _open(
    HttpClient client,
    Uri url,
    Map<String, String> headers,
  ) async {
    final request = await client.getUrl(url);
    headers.forEach(request.headers.set);
    final response = await request.close();

    final responseHeaders = <String, String>{};
    response.headers.forEach((name, values) {
      if (values.isNotEmpty) {
        responseHeaders[name.toLowerCase()] = values.join(',');
      }
    });

    return PackageDownloadResponse(
      statusCode: response.statusCode,
      headers: responseHeaders,
      bytes: response,
      onClose: () => client.close(force: true),
    );
  }
}

class PackageDownloader {
  static const defaultMaxDownloadBytes = 1024 * 1024 * 1024;
  static final Set<String> _activeSavePaths = <String>{};

  final PackageDownloadClient client;
  final int maxDownloadBytes;
  final RetryStrategy retryStrategy;
  final Duration requestTimeout;
  final Duration idleTimeout;

  PackageDownloader({
    PackageDownloadClient? client,
    this.maxDownloadBytes = defaultMaxDownloadBytes,
    this.retryStrategy = RetryStrategy.standard,
    this.requestTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 30),
  })  : assert(maxDownloadBytes > 0),
        assert(requestTimeout > Duration.zero),
        assert(idleTimeout > Duration.zero),
        client = client ?? const IoPackageDownloadClient();

  Future<PackageDownloadResult> download({
    required DownloadPackageAction action,
    required String savePath,
    void Function(PackageDownloadProgress progress)? onProgress,
    UpdateActionCancelToken? cancelToken,
  }) async {
    final lockKey = File(savePath).absolute.path;
    if (!_activeSavePaths.add(lockKey)) {
      return const PackageDownloadResult.failure(
        code: UpdateErrorCode.downloadInProgress,
        message: 'A package download is already writing to this path.',
      );
    }
    try {
      return await _downloadUnlocked(
        action: action,
        savePath: savePath,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    } finally {
      _activeSavePaths.remove(lockKey);
    }
  }

  Future<PackageDownloadResult> _downloadUnlocked({
    required DownloadPackageAction action,
    required String savePath,
    void Function(PackageDownloadProgress progress)? onProgress,
    UpdateActionCancelToken? cancelToken,
  }) async {
    final targetFile = File(savePath);
    final partialFile = File('$savePath.download');
    final metadataFile = File('${partialFile.path}.meta');
    final declaredSize = action.packageSizeBytes;

    if (declaredSize != null && declaredSize <= 0) {
      return const PackageDownloadResult.failure(
        code: UpdateErrorCode.manifestInvalid,
        message: 'packageSizeBytes must be a positive integer.',
      );
    }
    if (declaredSize != null && declaredSize > maxDownloadBytes) {
      return PackageDownloadResult.failure(
        code: UpdateErrorCode.packageTooLarge,
        message: 'Declared package size exceeds the $maxDownloadBytes byte '
            'download limit.',
      );
    }
    if (cancelToken?.isCanceled ?? false) {
      await _cleanupPartialState(partialFile, metadataFile);
      return const PackageDownloadResult.failure(
        code: UpdateErrorCode.actionCanceled,
        message: 'Package download canceled.',
      );
    }

    try {
      await targetFile.parent.create(recursive: true);
    } on FileSystemException catch (error) {
      return PackageDownloadResult.failure(
        code: UpdateErrorCode.packageDownloadFailed,
        message: error.message,
      );
    }

    var retryNumber = 0;
    while (true) {
      try {
        return await _downloadOnce(
          action: action,
          targetFile: targetFile,
          partialFile: partialFile,
          metadataFile: metadataFile,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
      } on _PackageDownloadCanceled {
        await _cleanupPartialState(partialFile, metadataFile);
        return const PackageDownloadResult.failure(
          code: UpdateErrorCode.actionCanceled,
          message: 'Package download canceled.',
        );
      } on _PackageSizeExceeded catch (error) {
        await _cleanupPartialState(partialFile, metadataFile);
        return PackageDownloadResult.failure(
          code: UpdateErrorCode.packageTooLarge,
          message: error.message,
        );
      } on _InvalidResumeResponse catch (error) {
        await _cleanupPartialState(partialFile, metadataFile);
        return PackageDownloadResult.failure(
          code: UpdateErrorCode.packageDownloadFailed,
          message: error.message,
        );
      } catch (error) {
        if (_shouldRetry(error, retryNumber)) {
          final delay = retryStrategy.getDelay(retryNumber);
          retryNumber++;
          if (delay > Duration.zero) {
            await _waitForRetry(delay, cancelToken);
          }
          continue;
        }
        return PackageDownloadResult.failure(
          code: UpdateErrorCode.packageDownloadFailed,
          message:
              error is FileSystemException ? error.message : error.toString(),
        );
      }
    }
  }

  Future<PackageDownloadResult> _downloadOnce({
    required DownloadPackageAction action,
    required File targetFile,
    required File partialFile,
    required File metadataFile,
    required void Function(PackageDownloadProgress progress)? onProgress,
    required UpdateActionCancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCanceled ?? false) {
      throw const _PackageDownloadCanceled();
    }

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

    final response = await _getResponse(
      url: action.packageUrl,
      headers: requestHeaders,
      cancelToken: cancelToken,
    );
    try {
      final isResumeResponse = resume != null && response.statusCode == 206;
      final isCleanResponse = response.statusCode == 200;
      if (!isResumeResponse && !isCleanResponse) {
        throw _PackageHttpException(response.statusCode);
      }

      final initialDownloadedBytes =
          isResumeResponse ? resume.downloadedBytes : 0;
      final contentRange = isResumeResponse
          ? _validatedContentRange(
              response,
              expectedStart: initialDownloadedBytes,
            )
          : null;
      final totalBytes = action.packageSizeBytes ??
          contentRange?.totalBytes ??
          _responseTotalBytes(response, initialDownloadedBytes);
      final rangedTotalBytes = contentRange?.totalBytes;
      if (rangedTotalBytes != null &&
          (rangedTotalBytes > maxDownloadBytes ||
              (action.packageSizeBytes != null &&
                  rangedTotalBytes != action.packageSizeBytes))) {
        throw const _PackageSizeExceeded(
          'Resumed package size exceeds the allowed byte limit.',
        );
      }
      _validateResponseSize(
        response: response,
        initialDownloadedBytes: initialDownloadedBytes,
        declaredSize: action.packageSizeBytes,
      );

      await _writeResponseBytes(
        action: action,
        response: response,
        partialFile: partialFile,
        metadataFile: metadataFile,
        append: isResumeResponse,
        initialDownloadedBytes: initialDownloadedBytes,
        totalBytes: totalBytes,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );

      final downloadedBytes = await partialFile.length();
      final expectedSize = action.packageSizeBytes ?? contentRange?.totalBytes;
      if (expectedSize != null && downloadedBytes != expectedSize) {
        await _cleanupPartialState(partialFile, metadataFile);
        return PackageDownloadResult.failure(
          code: UpdateErrorCode.packageDownloadFailed,
          message: 'Downloaded package size $downloadedBytes does not match '
              'declared size $expectedSize.',
        );
      }

      final expectedSha256 = _normalizedSha256(action.sha256);
      String? actualSha256;
      if (expectedSha256 != null) {
        actualSha256 = await _sha256Of(partialFile);
        if (actualSha256 != expectedSha256) {
          await _cleanupPartialState(partialFile, metadataFile);
          return const PackageDownloadResult.failure(
            code: UpdateErrorCode.packageHashMismatch,
            message: 'Package SHA-256 does not match.',
          );
        }
      }

      final finalFile = await _replaceTargetFile(partialFile, targetFile);
      await _deleteIfExists(metadataFile);
      return PackageDownloadResult.success(
        file: finalFile,
        downloadedBytes: await finalFile.length(),
        sha256: actualSha256,
      );
    } finally {
      await response.close();
    }
  }

  Future<void> _writeResponseBytes({
    required DownloadPackageAction action,
    required PackageDownloadResponse response,
    required File partialFile,
    required File metadataFile,
    required bool append,
    required int initialDownloadedBytes,
    required int? totalBytes,
    required void Function(PackageDownloadProgress progress)? onProgress,
    required UpdateActionCancelToken? cancelToken,
  }) async {
    var downloadedBytes = initialDownloadedBytes;
    Object? streamFailure;
    StackTrace? failureStackTrace;
    final sink = partialFile.openWrite(
      mode: append ? FileMode.append : FileMode.write,
    );
    try {
      final iterator = StreamIterator<List<int>>(response.bytes);
      try {
        while (await _moveNext(iterator, cancelToken)) {
          final chunk = iterator.current;
          if (cancelToken?.isCanceled ?? false) {
            throw const _PackageDownloadCanceled();
          }
          final nextDownloadedBytes = downloadedBytes + chunk.length;
          final effectiveLimit = action.packageSizeBytes ?? maxDownloadBytes;
          if (nextDownloadedBytes > effectiveLimit ||
              nextDownloadedBytes > maxDownloadBytes) {
            throw const _PackageSizeExceeded(
              'Package download exceeds the allowed byte limit.',
            );
          }
          sink.add(chunk);
          downloadedBytes = nextDownloadedBytes;
          onProgress?.call(
            PackageDownloadProgress(
              downloadedBytes: downloadedBytes,
              totalBytes: totalBytes,
            ),
          );
        }
      } finally {
        await iterator.cancel();
      }
      if (cancelToken?.isCanceled ?? false) {
        throw const _PackageDownloadCanceled();
      }
      await sink.flush();
    } catch (error, stackTrace) {
      streamFailure = error;
      failureStackTrace = stackTrace;
    } finally {
      await sink.close();
    }

    final failure = streamFailure;
    if (failure != null) {
      if ((cancelToken?.isCanceled ?? false) &&
          failure is! _PackageSizeExceeded) {
        throw const _PackageDownloadCanceled();
      }
      if (failure is! _PackageDownloadCanceled &&
          failure is! _PackageSizeExceeded) {
        await _writeResumeMetadata(
          action: action,
          response: response,
          partialFile: partialFile,
          metadataFile: metadataFile,
        );
      }
      Error.throwWithStackTrace(failure, failureStackTrace!);
    }
  }

  Future<bool> _moveNext(
    StreamIterator<List<int>> iterator,
    UpdateActionCancelToken? cancelToken,
  ) {
    final next = iterator.moveNext().timeout(
          idleTimeout,
          onTimeout: () => throw TimeoutException(
            'Package response stalled for longer than $idleTimeout.',
          ),
        );
    if (cancelToken == null) {
      return next;
    }
    return Future.any<bool>([
      next,
      cancelToken.whenCanceled.then<bool>((_) {
        throw const _PackageDownloadCanceled();
      }),
    ]);
  }

  Future<PackageDownloadResponse> _getResponse({
    required Uri url,
    required Map<String, String> headers,
    required UpdateActionCancelToken? cancelToken,
  }) {
    final networkCancelToken = UpdateActionCancelToken();
    cancelToken?.whenCanceled.then((_) => networkCancelToken.cancel());
    final request = client
        .get(
      url,
      headers: headers,
      cancelToken: networkCancelToken,
    )
        .timeout(
      requestTimeout,
      onTimeout: () {
        networkCancelToken.cancel();
        throw TimeoutException(
          'Package request timed out after $requestTimeout.',
        );
      },
    );
    unawaited(
      request.then<void>(
        (response) async {
          if (networkCancelToken.isCanceled) {
            await response.close();
          }
        },
        onError: (Object _, StackTrace __) {},
      ),
    );
    if (cancelToken == null) {
      return request;
    }
    return Future.any<PackageDownloadResponse>([
      request,
      cancelToken.whenCanceled.then<PackageDownloadResponse>((_) {
        throw const _PackageDownloadCanceled();
      }),
    ]);
  }

  Future<void> _waitForRetry(
    Duration delay,
    UpdateActionCancelToken? cancelToken,
  ) async {
    if (cancelToken == null) {
      await Future<void>.delayed(delay);
      return;
    }
    await Future.any<void>([
      Future<void>.delayed(delay),
      cancelToken.whenCanceled.then<void>((_) {
        throw const _PackageDownloadCanceled();
      }),
    ]);
  }

  Future<File> _replaceTargetFile(File partialFile, File targetFile) async {
    final backupFile = File('${targetFile.path}.previous');
    await _deleteIfExists(backupFile);
    final hadTarget = await targetFile.exists();
    if (hadTarget) {
      await targetFile.rename(backupFile.path);
    }
    try {
      final finalFile = await partialFile.rename(targetFile.path);
      await _deleteIfExists(backupFile);
      return finalFile;
    } catch (_) {
      if (hadTarget && await backupFile.exists()) {
        await _deleteIfExists(targetFile);
        await backupFile.rename(targetFile.path);
      }
      rethrow;
    }
  }

  void _validateResponseSize({
    required PackageDownloadResponse response,
    required int initialDownloadedBytes,
    required int? declaredSize,
  }) {
    final contentLength = response.contentLength;
    if (contentLength == null || contentLength < 0) {
      return;
    }
    final responseTotal = initialDownloadedBytes + contentLength;
    if (responseTotal > maxDownloadBytes ||
        (declaredSize != null && responseTotal > declaredSize)) {
      throw const _PackageSizeExceeded(
        'Package response exceeds the allowed byte limit.',
      );
    }
  }

  int? _responseTotalBytes(
    PackageDownloadResponse response,
    int initialDownloadedBytes,
  ) {
    final contentLength = response.contentLength;
    if (contentLength == null || contentLength < 0) {
      return null;
    }
    return initialDownloadedBytes + contentLength;
  }

  _ContentRange _validatedContentRange(
    PackageDownloadResponse response, {
    required int expectedStart,
  }) {
    final value = response.contentRange;
    final match = value == null
        ? null
        : RegExp(r'^bytes (\d+)-(\d+)/(\d+|\*)$').firstMatch(value.trim());
    if (match == null) {
      throw const _InvalidResumeResponse(
        'Resumed response has an invalid Content-Range header.',
      );
    }

    final start = int.parse(match.group(1)!);
    final end = int.parse(match.group(2)!);
    final totalText = match.group(3)!;
    final totalBytes = totalText == '*' ? null : int.parse(totalText);
    final contentLength = response.contentLength;
    if (start != expectedStart ||
        end < start ||
        (contentLength != null && contentLength != end - start + 1) ||
        (totalBytes != null && (totalBytes <= end || totalBytes <= 0))) {
      throw const _InvalidResumeResponse(
        'Resumed response does not match the requested byte range.',
      );
    }
    return _ContentRange(totalBytes: totalBytes);
  }

  Future<_ResumeMetadata?> _readResumeMetadata({
    required DownloadPackageAction action,
    required File partialFile,
    required File metadataFile,
  }) async {
    if (!await partialFile.exists() || !await metadataFile.exists()) {
      return null;
    }

    try {
      final data = jsonDecode(await metadataFile.readAsString());
      if (data is! Map<String, Object?>) {
        await _cleanupPartialState(partialFile, metadataFile);
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
          downloadedBytes > maxDownloadBytes ||
          validator == null ||
          await partialFile.length() != downloadedBytes) {
        await _cleanupPartialState(partialFile, metadataFile);
        return null;
      }

      return _ResumeMetadata(
        downloadedBytes: downloadedBytes,
        validator: validator,
      );
    } on FormatException {
      await _cleanupPartialState(partialFile, metadataFile);
      return null;
    }
  }

  Future<void> _writeResumeMetadata({
    required DownloadPackageAction action,
    required PackageDownloadResponse response,
    required File partialFile,
    required File metadataFile,
  }) async {
    final validator = response.etag ?? response.lastModified;
    if (validator == null || validator.isEmpty || !await partialFile.exists()) {
      await _deleteIfExists(metadataFile);
      return;
    }
    final downloadedBytes = await partialFile.length();
    if (downloadedBytes <= 0) {
      await _deleteIfExists(metadataFile);
      return;
    }
    await metadataFile.writeAsString(jsonEncode({
      'packageUrl': action.packageUrl.toString(),
      'etag': response.etag,
      'lastModified': response.lastModified,
      'downloadedBytes': downloadedBytes,
    }));
  }

  bool _shouldRetry(Object error, int retryNumber) {
    if (!retryStrategy.canRetry(retryNumber)) {
      return false;
    }
    if (error is _PackageHttpException) {
      return error.statusCode >= 500 && error.statusCode < 600;
    }
    return retryStrategy.shouldRetry(error, retryNumber);
  }

  Future<String> _sha256Of(File file) async {
    return crypto.sha256.bind(file.openRead()).first.then((digest) {
      return digest.toString().toLowerCase();
    });
  }

  Future<void> _cleanupPartialState(
    File partialFile,
    File metadataFile,
  ) async {
    await _deleteIfExists(partialFile);
    await _deleteIfExists(metadataFile);
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  String? _normalizedSha256(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
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

class _PackageDownloadCanceled implements Exception {
  const _PackageDownloadCanceled();
}

class _PackageSizeExceeded implements Exception {
  final String message;

  const _PackageSizeExceeded(this.message);
}

class _PackageHttpException implements Exception {
  final int statusCode;

  const _PackageHttpException(this.statusCode);

  @override
  String toString() => 'Unexpected package download status: $statusCode.';
}

class _InvalidResumeResponse implements Exception {
  final String message;

  const _InvalidResumeResponse(this.message);
}

class _ContentRange {
  final int? totalBytes;

  const _ContentRange({required this.totalBytes});
}
