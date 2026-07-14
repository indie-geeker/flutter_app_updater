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

  String? get contentEncoding => _header('content-encoding');

  String? get location => _header('location');

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
    final normalizedName = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == normalizedName) {
        return entry.value;
      }
    }
    return null;
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
    final client = HttpClient()
      ..connectionTimeout = connectionTimeout
      ..autoUncompress = false;
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
    request.followRedirects = false;
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

class PackageDownloadFileOperations {
  const PackageDownloadFileOperations();

  Future<String> readAsString(File file) => file.readAsString();

  Future<void> delete(File file) => file.delete();
}

class PackageDownloadCheckpointPolicy {
  final int byteInterval;
  final Duration timeInterval;

  const PackageDownloadCheckpointPolicy({
    this.byteInterval = 4 * 1024 * 1024,
    this.timeInterval = const Duration(seconds: 2),
  }) : assert(byteInterval > 0);
}

abstract class PackageDownloadCheckpointClock {
  Duration get elapsed;

  void reset();
}

class _StopwatchCheckpointClock implements PackageDownloadCheckpointClock {
  final Stopwatch _stopwatch = Stopwatch()..start();

  @override
  Duration get elapsed => _stopwatch.elapsed;

  @override
  void reset() => _stopwatch.reset();
}

PackageDownloadCheckpointClock _createCheckpointClock() {
  return _StopwatchCheckpointClock();
}

class PackageDownloader {
  static const defaultMaxDownloadBytes = 1024 * 1024 * 1024;
  static const _checkpointSchemaVersion = 1;
  static const _maxRedirects = 5;
  static final Set<String> _activeSavePaths = <String>{};

  final PackageDownloadClient client;
  final int maxDownloadBytes;
  final RetryStrategy retryStrategy;
  final Duration requestTimeout;
  final Duration idleTimeout;
  final PackageDownloadFileOperations fileOperations;
  final PackageDownloadCheckpointPolicy checkpointPolicy;
  final PackageDownloadCheckpointClock Function() checkpointClockFactory;

  PackageDownloader({
    PackageDownloadClient? client,
    this.maxDownloadBytes = defaultMaxDownloadBytes,
    this.retryStrategy = RetryStrategy.standard,
    this.requestTimeout = const Duration(seconds: 30),
    this.idleTimeout = const Duration(seconds: 30),
    PackageDownloadFileOperations? fileOperations,
    this.checkpointPolicy = const PackageDownloadCheckpointPolicy(),
    PackageDownloadCheckpointClock Function()? checkpointClockFactory,
  })  : assert(maxDownloadBytes > 0),
        assert(requestTimeout > Duration.zero),
        assert(idleTimeout > Duration.zero),
        assert(checkpointPolicy.timeInterval > Duration.zero),
        client = client ?? const IoPackageDownloadClient(),
        fileOperations =
            fileOperations ?? const PackageDownloadFileOperations(),
        checkpointClockFactory =
            checkpointClockFactory ?? _createCheckpointClock;

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

    if (declaredSize <= 0) {
      return const PackageDownloadResult.failure(
        code: UpdateErrorCode.manifestInvalid,
        message: 'packageSizeBytes must be a positive integer.',
      );
    }
    if (declaredSize > maxDownloadBytes) {
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
    var cleanRetryUsed = false;
    var forceClean = false;
    while (true) {
      try {
        return await _downloadOnce(
          action: action,
          targetFile: targetFile,
          partialFile: partialFile,
          metadataFile: metadataFile,
          onProgress: onProgress,
          cancelToken: cancelToken,
          forceClean: forceClean,
        );
      } on _CleanRetryRequired {
        if (cleanRetryUsed) {
          await _cleanupPartialState(partialFile, metadataFile);
          return const PackageDownloadResult.failure(
            code: UpdateErrorCode.packageDownloadFailed,
            message: 'The server rejected both resumed and clean requests.',
          );
        }
        cleanRetryUsed = true;
        forceClean = true;
        await _cleanupPartialState(partialFile, metadataFile);
        continue;
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
        if (cancelToken?.isCanceled ?? false) {
          await _cleanupPartialState(partialFile, metadataFile);
          return const PackageDownloadResult.failure(
            code: UpdateErrorCode.actionCanceled,
            message: 'Package download canceled.',
          );
        }
        if (_shouldRetry(error, retryNumber)) {
          final delay = retryStrategy.getDelay(retryNumber);
          retryNumber++;
          forceClean = false;
          if (delay > Duration.zero) {
            try {
              await _waitForRetry(delay, cancelToken);
            } on _PackageDownloadCanceled {
              await _cleanupPartialState(partialFile, metadataFile);
              return const PackageDownloadResult.failure(
                code: UpdateErrorCode.actionCanceled,
                message: 'Package download canceled.',
              );
            }
          }
          continue;
        }
        if (!_shouldPreserveCheckpoint(error)) {
          await _cleanupPartialState(partialFile, metadataFile);
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
    required bool forceClean,
  }) async {
    if (cancelToken?.isCanceled ?? false) {
      throw const _PackageDownloadCanceled();
    }

    final resume = forceClean
        ? null
        : await _readResumeMetadata(
            action: action,
            partialFile: partialFile,
            metadataFile: metadataFile,
          );
    final requestHeaders = <String, String>{'accept-encoding': 'identity'};
    if (resume != null) {
      requestHeaders['range'] = 'bytes=${resume.downloadedBytes}-';
      requestHeaders['if-range'] = resume.etag;
    }

    final response = await _getResponseFollowingRedirects(
      url: action.packageUrl,
      headers: requestHeaders,
      cancelToken: cancelToken,
    );
    try {
      _validateContentEncoding(response);

      if (response.statusCode == 416 && resume != null) {
        final serverLength = _unsatisfiedRangeLength(response.contentRange);
        if (serverLength == resume.downloadedBytes &&
            serverLength == resume.totalBytes) {
          return _verifyAndFinalize(
            action: action,
            targetFile: targetFile,
            partialFile: partialFile,
            metadataFile: metadataFile,
            cancelToken: cancelToken,
          );
        }
        throw const _CleanRetryRequired();
      }

      final isResumeResponse = resume != null && response.statusCode == 206;
      final isCleanResponse = response.statusCode == 200;
      if (!isResumeResponse && !isCleanResponse) {
        if (response.statusCode == 206) {
          throw const _InvalidResumeResponse(
            'The server sent an unsolicited partial response.',
          );
        }
        throw _PackageHttpException(response.statusCode);
      }

      final initialDownloadedBytes =
          isResumeResponse ? resume.downloadedBytes : 0;
      final contentRange = isResumeResponse
          ? _validatedContentRange(
              response,
              expectedStart: initialDownloadedBytes,
              expectedTotal: resume.totalBytes,
              expectedEtag: resume.etag,
            )
          : null;
      final totalBytes = action.packageSizeBytes;
      final rangedTotalBytes = contentRange?.totalBytes;
      if (rangedTotalBytes != null &&
          (rangedTotalBytes > maxDownloadBytes ||
              rangedTotalBytes != action.packageSizeBytes)) {
        throw const _PackageSizeExceeded(
          'Resumed package size exceeds the allowed byte limit.',
        );
      }
      _validateResponseSize(
        response: response,
        initialDownloadedBytes: initialDownloadedBytes,
        declaredSize: action.packageSizeBytes,
      );

      final isCleanRestart = resume != null && isCleanResponse;
      if (isCleanRestart) {
        await _cleanupMetadata(metadataFile);
      }

      await _writeResponseBytes(
        action: action,
        response: response,
        partialFile: partialFile,
        metadataFile: metadataFile,
        append: isResumeResponse,
        initialDownloadedBytes: initialDownloadedBytes,
        totalBytes: totalBytes,
        previousRevision: isCleanRestart ? 0 : resume?.revision ?? 0,
        previousSlot: isCleanRestart ? -1 : resume?.slot ?? -1,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );

      return _verifyAndFinalize(
        action: action,
        targetFile: targetFile,
        partialFile: partialFile,
        metadataFile: metadataFile,
        cancelToken: cancelToken,
        expectedSize: action.packageSizeBytes,
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
    required int previousRevision,
    required int previousSlot,
    required void Function(PackageDownloadProgress progress)? onProgress,
    required UpdateActionCancelToken? cancelToken,
  }) async {
    var downloadedBytes = initialDownloadedBytes;
    var lastCheckpointBytes = initialDownloadedBytes;
    var revision = previousRevision;
    var checkpointSlot = previousSlot;
    final checkpointClock = checkpointClockFactory();
    RandomAccessFile file;
    try {
      file = await partialFile.open(mode: FileMode.writeOnlyAppend);
      if (!append) {
        await file.truncate(0);
        await file.setPosition(0);
      } else {
        await file.setPosition(initialDownloadedBytes);
      }
    } on FileSystemException catch (error, stackTrace) {
      Error.throwWithStackTrace(_StorageFailure(error), stackTrace);
    }

    Object? failure;
    StackTrace? failureStackTrace;
    try {
      final iterator = StreamIterator<List<int>>(response.bytes);
      try {
        while (await _moveNext(iterator, cancelToken)) {
          final chunk = iterator.current;
          if (cancelToken?.isCanceled ?? false) {
            throw const _PackageDownloadCanceled();
          }
          final nextDownloadedBytes = downloadedBytes + chunk.length;
          final effectiveLimit = action.packageSizeBytes;
          if (nextDownloadedBytes > effectiveLimit ||
              nextDownloadedBytes > maxDownloadBytes) {
            throw const _PackageSizeExceeded(
              'Package download exceeds the allowed byte limit.',
            );
          }
          try {
            await file.writeFrom(chunk);
          } on FileSystemException catch (error, stackTrace) {
            Error.throwWithStackTrace(_StorageFailure(error), stackTrace);
          }
          downloadedBytes = nextDownloadedBytes;

          final checkpointDue = downloadedBytes - lastCheckpointBytes >=
                  checkpointPolicy.byteInterval ||
              checkpointClock.elapsed >= checkpointPolicy.timeInterval;
          if (checkpointDue &&
              _canCheckpoint(
                action: action,
                response: response,
                totalBytes: totalBytes,
              )) {
            final checkpoint = await _flushAndCheckpoint(
              file: file,
              action: action,
              response: response,
              metadataFile: metadataFile,
              downloadedBytes: downloadedBytes,
              totalBytes: totalBytes!,
              previousRevision: revision,
              previousSlot: checkpointSlot,
            );
            revision = checkpoint.revision;
            checkpointSlot = checkpoint.slot;
            lastCheckpointBytes = downloadedBytes;
            checkpointClock.reset();
          }
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
      try {
        await file.flush();
      } on FileSystemException catch (error, stackTrace) {
        Error.throwWithStackTrace(_StorageFailure(error), stackTrace);
      }
    } catch (error, stackTrace) {
      failure = error;
      failureStackTrace = stackTrace;
    } finally {
      try {
        await file.close();
      } on FileSystemException catch (error, stackTrace) {
        if (failure == null) {
          failure = _StorageFailure(error);
          failureStackTrace = stackTrace;
        }
      }
    }

    final terminalFailure = failure;
    if (terminalFailure != null) {
      if ((cancelToken?.isCanceled ?? false) &&
          terminalFailure is! _PackageSizeExceeded) {
        throw const _PackageDownloadCanceled();
      }
      if (_isNetworkError(terminalFailure) &&
          downloadedBytes > lastCheckpointBytes &&
          _canCheckpoint(
            action: action,
            response: response,
            totalBytes: totalBytes,
          )) {
        RandomAccessFile? checkpointFile;
        try {
          checkpointFile = await partialFile.open(mode: FileMode.append);
          await checkpointFile.setPosition(downloadedBytes);
          await _flushAndCheckpoint(
            file: checkpointFile,
            action: action,
            response: response,
            metadataFile: metadataFile,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes!,
            previousRevision: revision,
            previousSlot: checkpointSlot,
          );
        } on FileSystemException catch (error, stackTrace) {
          Error.throwWithStackTrace(_StorageFailure(error), stackTrace);
        } finally {
          await checkpointFile?.close();
        }
      }
      Error.throwWithStackTrace(terminalFailure, failureStackTrace!);
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

  Future<PackageDownloadResponse> _getResponseFollowingRedirects({
    required Uri url,
    required Map<String, String> headers,
    required UpdateActionCancelToken? cancelToken,
  }) async {
    var currentUrl = url;
    for (var redirectCount = 0;; redirectCount++) {
      _validateDownloadUrl(currentUrl);
      final response = await _getResponse(
        url: currentUrl,
        headers: headers,
        cancelToken: cancelToken,
      );
      if (!_isRedirect(response.statusCode)) {
        return response;
      }

      if (redirectCount >= _maxRedirects) {
        await response.close();
        throw const _InvalidResumeResponse(
          'Package download exceeded five redirects.',
        );
      }
      final location = response.location;
      if (location == null || location.trim().isEmpty) {
        await response.close();
        throw const _InvalidResumeResponse(
          'Package redirect is missing a Location header.',
        );
      }
      final parsedLocation = Uri.tryParse(location.trim());
      if (parsedLocation == null) {
        await response.close();
        throw const _InvalidResumeResponse(
          'Package redirect has an invalid Location header.',
        );
      }
      final nextUrl = currentUrl.resolveUri(parsedLocation);
      if (currentUrl.scheme == 'https' && nextUrl.scheme != 'https') {
        await response.close();
        throw const _InvalidResumeResponse(
          'Package redirect cannot downgrade HTTPS.',
        );
      }
      _validateDownloadUrl(nextUrl);
      await response.close();
      currentUrl = nextUrl;
    }
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
    required int declaredSize,
  }) {
    final contentLength = response.contentLength;
    if (contentLength == null || contentLength < 0) {
      return;
    }
    final responseTotal = initialDownloadedBytes + contentLength;
    if (responseTotal > maxDownloadBytes || responseTotal > declaredSize) {
      throw const _PackageSizeExceeded(
        'Package response exceeds the allowed byte limit.',
      );
    }
  }

  _ContentRange _validatedContentRange(
    PackageDownloadResponse response, {
    required int expectedStart,
    required int expectedTotal,
    required String expectedEtag,
  }) {
    final value = response.contentRange;
    final match = value == null
        ? null
        : RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value.trim());
    if (match == null) {
      throw const _InvalidResumeResponse(
        'Resumed response has an invalid Content-Range header.',
      );
    }

    final start = int.parse(match.group(1)!);
    final end = int.parse(match.group(2)!);
    final totalBytes = int.parse(match.group(3)!);
    final contentLength = response.contentLength;
    if (start != expectedStart ||
        end < start ||
        contentLength == null ||
        contentLength != end - start + 1 ||
        totalBytes != expectedTotal ||
        totalBytes <= end ||
        response.etag != expectedEtag ||
        !_isStrongEtag(response.etag)) {
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
    final expectedSize = action.packageSizeBytes;
    final expectedSha256 = _normalizedSha256(action.sha256);
    if (expectedSha256 == null) {
      await _cleanupPartialState(partialFile, metadataFile);
      return null;
    }

    final candidates = <_ResumeMetadata>[];
    for (var slot = 0; slot < 2; slot++) {
      final metadata = await _readCheckpointSlot(
        _checkpointSlot(metadataFile, slot),
        slot,
      );
      if (metadata != null &&
          metadata.packageUrl == action.packageUrl.toString() &&
          metadata.packageSizeBytes == expectedSize &&
          metadata.sha256 == expectedSha256 &&
          metadata.totalBytes == expectedSize &&
          metadata.downloadedBytes > 0 &&
          metadata.downloadedBytes <= metadata.totalBytes &&
          metadata.downloadedBytes <= maxDownloadBytes &&
          _isStrongEtag(metadata.etag)) {
        candidates.add(metadata);
      }
    }

    if (candidates.isEmpty || !await partialFile.exists()) {
      await _cleanupPartialState(partialFile, metadataFile);
      return null;
    }

    candidates.sort((left, right) => right.revision.compareTo(left.revision));
    final checkpoint = candidates.first;
    final fileLength = await partialFile.length();
    if (fileLength < checkpoint.downloadedBytes) {
      await _cleanupPartialState(partialFile, metadataFile);
      return null;
    }
    if (fileLength > checkpoint.downloadedBytes) {
      RandomAccessFile? file;
      try {
        file = await partialFile.open(mode: FileMode.writeOnlyAppend);
        await file.truncate(checkpoint.downloadedBytes);
        await file.flush();
      } on FileSystemException catch (error, stackTrace) {
        Error.throwWithStackTrace(_StorageFailure(error), stackTrace);
      } finally {
        await file?.close();
      }
    }
    return checkpoint;
  }

  Future<_ResumeMetadata?> _readCheckpointSlot(
    File slotFile,
    int slot,
  ) async {
    if (!await slotFile.exists()) {
      return null;
    }
    try {
      final data = jsonDecode(await fileOperations.readAsString(slotFile));
      if (data is! Map<String, Object?> ||
          data['schemaVersion'] != _checkpointSchemaVersion ||
          data['revision'] is! int ||
          data['packageUrl'] is! String ||
          data['downloadedBytes'] is! int ||
          data['packageSizeBytes'] is! int ||
          data['sha256'] is! String ||
          data['etag'] is! String ||
          data['totalBytes'] is! int) {
        return null;
      }
      final revision = data['revision']! as int;
      if (revision <= 0) {
        return null;
      }
      return _ResumeMetadata(
        slot: slot,
        revision: revision,
        packageUrl: data['packageUrl']! as String,
        downloadedBytes: data['downloadedBytes']! as int,
        packageSizeBytes: data['packageSizeBytes']! as int,
        sha256: (data['sha256']! as String).trim().toLowerCase(),
        etag: data['etag']! as String,
        totalBytes: data['totalBytes']! as int,
      );
    } on FormatException {
      return null;
    } on FileSystemException catch (error, stackTrace) {
      Error.throwWithStackTrace(_CheckpointReadFailure(error), stackTrace);
    }
  }

  bool _canCheckpoint({
    required DownloadPackageAction action,
    required PackageDownloadResponse response,
    required int? totalBytes,
  }) {
    final expectedSize = action.packageSizeBytes;
    return _normalizedSha256(action.sha256) != null &&
        totalBytes == expectedSize &&
        _isStrongEtag(response.etag);
  }

  Future<_CheckpointPosition> _flushAndCheckpoint({
    required RandomAccessFile file,
    required DownloadPackageAction action,
    required PackageDownloadResponse response,
    required File metadataFile,
    required int downloadedBytes,
    required int totalBytes,
    required int previousRevision,
    required int previousSlot,
  }) async {
    try {
      await file.flush();
    } on FileSystemException catch (error, stackTrace) {
      Error.throwWithStackTrace(_StorageFailure(error), stackTrace);
    }

    final nextRevision = previousRevision + 1;
    final nextSlot = previousSlot < 0 ? nextRevision % 2 : 1 - previousSlot;
    final slotFile = _checkpointSlot(metadataFile, nextSlot);
    final temporaryFile = File('${slotFile.path}.tmp');
    final metadata = <String, Object?>{
      'schemaVersion': _checkpointSchemaVersion,
      'revision': nextRevision,
      'packageUrl': action.packageUrl.toString(),
      'downloadedBytes': downloadedBytes,
      'packageSizeBytes': action.packageSizeBytes,
      'sha256': _normalizedSha256(action.sha256),
      'etag': response.etag,
      'totalBytes': totalBytes,
    };

    RandomAccessFile? metadataHandle;
    try {
      await _deleteIfExists(temporaryFile);
      metadataHandle = await temporaryFile.open(mode: FileMode.write);
      await metadataHandle.writeFrom(utf8.encode(jsonEncode(metadata)));
      await metadataHandle.flush();
      await metadataHandle.close();
      metadataHandle = null;
      await _deleteIfExists(slotFile);
      await temporaryFile.rename(slotFile.path);
      return _CheckpointPosition(revision: nextRevision, slot: nextSlot);
    } on FileSystemException catch (error, stackTrace) {
      Error.throwWithStackTrace(_StorageFailure(error), stackTrace);
    } finally {
      await metadataHandle?.close();
      await _deleteIfExists(temporaryFile);
    }
  }

  Future<PackageDownloadResult> _verifyAndFinalize({
    required DownloadPackageAction action,
    required File targetFile,
    required File partialFile,
    required File metadataFile,
    required UpdateActionCancelToken? cancelToken,
    int? expectedSize,
  }) async {
    if (cancelToken?.isCanceled ?? false) {
      throw const _PackageDownloadCanceled();
    }
    final downloadedBytes = await partialFile.length();
    final requiredSize = expectedSize ?? action.packageSizeBytes;
    if (downloadedBytes != requiredSize) {
      await _cleanupPartialState(partialFile, metadataFile);
      return PackageDownloadResult.failure(
        code: UpdateErrorCode.packageDownloadFailed,
        message: 'Downloaded package size $downloadedBytes does not match '
            'declared size $requiredSize.',
      );
    }

    final expectedSha256 = _normalizedSha256(action.sha256);
    String? actualSha256;
    if (expectedSha256 != null) {
      actualSha256 = await _sha256Of(partialFile);
      if (cancelToken?.isCanceled ?? false) {
        throw const _PackageDownloadCanceled();
      }
      if (actualSha256 != expectedSha256) {
        await _cleanupPartialState(partialFile, metadataFile);
        return const PackageDownloadResult.failure(
          code: UpdateErrorCode.packageHashMismatch,
          message: 'Package SHA-256 does not match.',
        );
      }
    }

    final finalFile = await _replaceTargetFile(partialFile, targetFile);
    try {
      await _cleanupMetadata(metadataFile);
    } on FileSystemException {
      // The verified target is already committed. Stale metadata is harmless
      // without the partial file and will be cleaned on the next invocation.
    }
    return PackageDownloadResult.success(
      file: finalFile,
      downloadedBytes: await finalFile.length(),
      sha256: actualSha256,
    );
  }

  void _validateContentEncoding(PackageDownloadResponse response) {
    final encoding = response.contentEncoding?.trim().toLowerCase();
    if (encoding != null && encoding.isNotEmpty && encoding != 'identity') {
      throw const _InvalidResumeResponse(
        'Package response must use identity content encoding.',
      );
    }
  }

  int? _unsatisfiedRangeLength(String? value) {
    if (value == null) {
      return null;
    }
    final match = RegExp(r'^bytes \*/(\d+)$').firstMatch(value.trim());
    return match == null ? null : int.parse(match.group(1)!);
  }

  bool _isRedirect(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  void _validateDownloadUrl(Uri url) {
    final isLoopbackHttp = url.scheme == 'http' &&
        (url.host == 'localhost' ||
            url.host == '127.0.0.1' ||
            url.host == '::1');
    if (url.scheme != 'https' && !isLoopbackHttp) {
      throw const _InvalidResumeResponse(
        'Package URL must use HTTPS (loopback HTTP is test-only).',
      );
    }
  }

  bool _isStrongEtag(String? value) {
    if (value == null) {
      return false;
    }
    final normalized = value.trim();
    return normalized.length >= 2 &&
        normalized.startsWith('"') &&
        normalized.endsWith('"') &&
        !normalized.startsWith('W/');
  }

  bool _isNetworkError(Object error) {
    return error is SocketException ||
        error is TimeoutException ||
        error is HandshakeException ||
        error is HttpException;
  }

  bool _shouldPreserveCheckpoint(Object error) {
    return error is _CheckpointReadFailure ||
        _isNetworkError(error) ||
        (error is _PackageHttpException &&
            _isRetryableHttpStatus(error.statusCode));
  }

  bool _shouldRetry(Object error, int retryNumber) {
    if (!retryStrategy.canRetry(retryNumber)) {
      return false;
    }
    if (error is _PackageHttpException) {
      return _isRetryableHttpStatus(error.statusCode);
    }
    if (error is _StorageFailure) {
      return false;
    }
    return _isNetworkError(error) &&
        retryStrategy.shouldRetry(error, retryNumber);
  }

  bool _isRetryableHttpStatus(int statusCode) {
    return statusCode == 408 ||
        statusCode == 429 ||
        (statusCode >= 500 && statusCode < 600);
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
    await _cleanupMetadata(metadataFile);
  }

  Future<void> _cleanupMetadata(File metadataFile) async {
    await _deleteIfExists(metadataFile);
    for (var slot = 0; slot < 2; slot++) {
      final slotFile = _checkpointSlot(metadataFile, slot);
      await _deleteIfExists(File('${slotFile.path}.tmp'));
      await _deleteIfExists(slotFile);
    }
  }

  File _checkpointSlot(File metadataFile, int slot) {
    return File('${metadataFile.path}.$slot');
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await fileOperations.delete(file);
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
  final int slot;
  final int revision;
  final String packageUrl;
  final int downloadedBytes;
  final int packageSizeBytes;
  final String sha256;
  final String etag;
  final int totalBytes;

  const _ResumeMetadata({
    required this.slot,
    required this.revision,
    required this.packageUrl,
    required this.downloadedBytes,
    required this.packageSizeBytes,
    required this.sha256,
    required this.etag,
    required this.totalBytes,
  });
}

class _CheckpointPosition {
  final int revision;
  final int slot;

  const _CheckpointPosition({
    required this.revision,
    required this.slot,
  });
}

class _CleanRetryRequired implements Exception {
  const _CleanRetryRequired();
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

class _StorageFailure implements Exception {
  final FileSystemException error;

  const _StorageFailure(this.error);

  @override
  String toString() => error.message;
}

class _CheckpointReadFailure extends _StorageFailure {
  const _CheckpointReadFailure(super.error);
}

class _ContentRange {
  final int? totalBytes;

  const _ContentRange({required this.totalBytes});
}
