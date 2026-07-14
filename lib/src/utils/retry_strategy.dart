import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../models/update_error_code.dart';

/// Immutable exponential-backoff policy for transient updater failures.
///
/// A retry number is zero-based and counts retries after the initial attempt.
/// Integrity, signature, schema, identity, permission, and configuration
/// failures are deliberately non-retryable.
///
/// Example:
/// ```dart
/// final strategy = RetryStrategy(
///   maxAttempts: 3,
///   initialDelay: Duration(seconds: 1),
///   backoffFactor: 2.0,
/// );
///
/// for (int attempt = 0; attempt < strategy.maxAttempts; attempt++) {
///   try {
///     await doSomething();
///     break;
///   } catch (e) {
///     if (strategy.shouldRetry(e, attempt)) {
///       final delay = strategy.getDelay(attempt);
///       await Future.delayed(delay);
///       continue;
///     }
///     rethrow;
///   }
/// }
/// ```
class RetryStrategy {
  /// Maximum retries after the initial attempt.
  final int maxAttempts;

  /// Delay before the first retry.
  final Duration initialDelay;

  /// Multiplier applied for each subsequent retry.
  final double backoffFactor;

  /// Upper bound for a computed retry delay.
  final Duration maxDelay;

  /// Whether to add a random zero-to-25-percent delay to spread client load.
  final bool enableJitter;

  /// Creates a retry policy.
  ///
  /// Assertions require a nonnegative [maxAttempts] and positive
  /// [backoffFactor].
  const RetryStrategy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffFactor = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    this.enableJitter = true,
  })  : assert(maxAttempts >= 0, '最大重试次数不能为负数'),
        assert(backoffFactor > 0, '退避因子必须大于0');

  /// Policy that never retries.
  static const disabled = RetryStrategy(maxAttempts: 0);

  /// Fast policy for short-lived network interruptions.
  static const fast = RetryStrategy(
    maxAttempts: 5,
    initialDelay: Duration(milliseconds: 500),
    backoffFactor: 1.5,
    maxDelay: Duration(seconds: 10),
  );

  /// General-purpose default retry policy.
  static const standard = RetryStrategy(
    maxAttempts: 3,
    initialDelay: Duration(seconds: 1),
    backoffFactor: 2.0,
    maxDelay: Duration(seconds: 30),
  );

  /// Conservative policy for a service under sustained load.
  static const conservative = RetryStrategy(
    maxAttempts: 2,
    initialDelay: Duration(seconds: 3),
    backoffFactor: 3.0,
    maxDelay: Duration(minutes: 2),
  );

  /// Returns the bounded exponential delay for [attemptNumber].
  ///
  /// A negative retry number returns [Duration.zero].
  Duration getDelay(int attemptNumber) {
    if (attemptNumber < 0) {
      return Duration.zero;
    }

    // 计算指数退避延迟
    final baseDelay =
        initialDelay.inMilliseconds * math.pow(backoffFactor, attemptNumber);

    // 限制最大延迟
    var delayMs = math.min(baseDelay, maxDelay.inMilliseconds.toDouble());

    // 添加抖动（0-25%的随机偏移）
    if (enableJitter && delayMs > 0) {
      final jitter = delayMs * 0.25 * math.Random().nextDouble();
      delayMs = delayMs + jitter;
    }

    return Duration(milliseconds: delayMs.round());
  }

  /// Whether [attemptNumber] is within [maxAttempts].
  bool canRetry(int attemptNumber) {
    return attemptNumber < maxAttempts;
  }

  /// Whether [error] is transient and another retry remains.
  ///
  /// Network timeouts, socket/TLS failures, selected server errors, manifest
  /// fetch failures, and package download failures may retry. Trust and local
  /// deterministic failures do not.
  bool shouldRetry(Object error, int attemptNumber) {
    // 检查是否还有重试次数
    if (!canRetry(attemptNumber)) {
      return false;
    }

    // 如果是v3结构化错误码，检查错误类型
    if (error is UpdateErrorCode) {
      return _shouldRetryUpdateErrorCode(error);
    }

    // 如果是原始异常，检查异常类型
    if (error is Exception) {
      return _shouldRetryException(error);
    }

    // 其他错误类型默认不重试
    return false;
  }

  /// Classifies structured updater failure codes.
  bool _shouldRetryUpdateErrorCode(UpdateErrorCode code) {
    return switch (code) {
      UpdateErrorCode.manifestFetchFailed ||
      UpdateErrorCode.packageDownloadFailed =>
        true,
      UpdateErrorCode.configurationInvalid ||
      UpdateErrorCode.manifestSignatureRequired ||
      UpdateErrorCode.manifestSignatureInvalid ||
      UpdateErrorCode.manifestInvalid ||
      UpdateErrorCode.appIdMismatch ||
      UpdateErrorCode.unsupportedSchemaVersion ||
      UpdateErrorCode.unsupportedActionType ||
      UpdateErrorCode.missingRequiredField ||
      UpdateErrorCode.legacyFieldNotSupported ||
      UpdateErrorCode.noMatchingRelease ||
      UpdateErrorCode.noSupportedAction ||
      UpdateErrorCode.storeNotAvailable ||
      UpdateErrorCode.marketNotAvailable ||
      UpdateErrorCode.packageTooLarge ||
      UpdateErrorCode.packageHashMismatch ||
      UpdateErrorCode.packageSignatureInvalid ||
      UpdateErrorCode.packageInstallPermissionRequired ||
      UpdateErrorCode.packageFileNotFound ||
      UpdateErrorCode.packageInstallFailed ||
      UpdateErrorCode.installerOpenFailed ||
      UpdateErrorCode.platformNotSupported ||
      UpdateErrorCode.backgroundDownloadUnavailable ||
      UpdateErrorCode.backgroundDownloadNotFound ||
      UpdateErrorCode.backgroundDownloadStartRejected ||
      UpdateErrorCode.backgroundDownloadInvalidState ||
      UpdateErrorCode.backgroundStorageUnavailable ||
      UpdateErrorCode.downloadInProgress ||
      UpdateErrorCode.actionFailed ||
      UpdateErrorCode.actionCanceled =>
        false,
    };
  }

  /// Classifies raw transport and filesystem exceptions.
  bool _shouldRetryException(Object exception) {
    // 网络相关异常 - 可重试
    if (exception is SocketException) {
      return true;
    }

    if (exception is TimeoutException) {
      return true;
    }

    if (exception is HandshakeException) {
      return true;
    }

    // HTTP异常 - 根据状态码判断
    if (exception is HttpException) {
      // 5xx 服务器错误 - 可重试
      // 4xx 客户端错误 - 不可重试
      // 这里需要从消息中提取状态码，简化处理
      final message = exception.message.toLowerCase();
      if (message.contains('500') ||
          message.contains('502') ||
          message.contains('503') ||
          message.contains('504')) {
        return true;
      }
      return false;
    }

    // 文件系统异常 - 不可重试
    if (exception is FileSystemException) {
      return false;
    }

    // 格式异常 - 不可重试
    if (exception is FormatException) {
      return false;
    }

    // 其他异常默认不重试
    return false;
  }

  @override
  String toString() {
    return 'RetryStrategy('
        'maxAttempts: $maxAttempts, '
        'initialDelay: ${initialDelay.inMilliseconds}ms, '
        'backoffFactor: $backoffFactor, '
        'maxDelay: ${maxDelay.inSeconds}s, '
        'enableJitter: $enableJitter'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is RetryStrategy &&
        other.maxAttempts == maxAttempts &&
        other.initialDelay == initialDelay &&
        other.backoffFactor == backoffFactor &&
        other.maxDelay == maxDelay &&
        other.enableJitter == enableJitter;
  }

  @override
  int get hashCode {
    return Object.hash(
      maxAttempts,
      initialDelay,
      backoffFactor,
      maxDelay,
      enableJitter,
    );
  }
}
