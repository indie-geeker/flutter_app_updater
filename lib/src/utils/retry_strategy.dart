import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../models/update_error.dart';

/// 重试策略配置类
///
/// 提供智能重试机制，支持：
/// - 可配置的重试次数
/// - 指数退避算法
/// - 最大延迟限制
/// - 基于错误类型的智能判断
///
/// 示例:
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
///     break; // 成功，退出重试循环
///   } catch (e) {
///     if (strategy.shouldRetry(e, attempt)) {
///       final delay = strategy.getDelay(attempt);
///       await Future.delayed(delay);
///       continue; // 继续重试
///     }
///     rethrow; // 不应该重试，抛出异常
///   }
/// }
/// ```
class RetryStrategy {
  /// 最大重试次数（不包括首次尝试）
  final int maxAttempts;

  /// 首次重试的初始延迟
  final Duration initialDelay;

  /// 指数退避因子
  ///
  /// 每次重试的延迟时间 = initialDelay * (backoffFactor ^ attemptNumber)
  /// 例如：backoffFactor=2.0 时，延迟序列为 1s, 2s, 4s, 8s...
  final double backoffFactor;

  /// 最大延迟时间
  ///
  /// 防止延迟时间无限增长
  final Duration maxDelay;

  /// 是否启用抖动
  ///
  /// 抖动可以防止大量客户端同时重试，分散服务器负载
  /// 启用时会在延迟时间上添加0-25%的随机偏移
  final bool enableJitter;

  /// 创建重试策略
  ///
  /// [maxAttempts] 最大重试次数，默认3次
  /// [initialDelay] 初始延迟，默认1秒
  /// [backoffFactor] 退避因子，默认2.0（指数增长）
  /// [maxDelay] 最大延迟，默认30秒
  /// [enableJitter] 是否启用抖动，默认true
  const RetryStrategy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(seconds: 1),
    this.backoffFactor = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    this.enableJitter = true,
  }) : assert(maxAttempts >= 0, '最大重试次数不能为负数'),
       assert(backoffFactor > 0, '退避因子必须大于0');

  /// 禁用重试的策略
  static const disabled = RetryStrategy(maxAttempts: 0);

  /// 快速重试策略（适用于临时网络问题）
  static const fast = RetryStrategy(
    maxAttempts: 5,
    initialDelay: Duration(milliseconds: 500),
    backoffFactor: 1.5,
    maxDelay: Duration(seconds: 10),
  );

  /// 标准重试策略（默认推荐）
  static const standard = RetryStrategy(
    maxAttempts: 3,
    initialDelay: Duration(seconds: 1),
    backoffFactor: 2.0,
    maxDelay: Duration(seconds: 30),
  );

  /// 保守重试策略（适用于服务器压力大的情况）
  static const conservative = RetryStrategy(
    maxAttempts: 2,
    initialDelay: Duration(seconds: 3),
    backoffFactor: 3.0,
    maxDelay: Duration(minutes: 2),
  );

  /// 计算指定重试次数的延迟时间
  ///
  /// 使用指数退避算法：delay = initialDelay * (backoffFactor ^ attemptNumber)
  ///
  /// [attemptNumber] 当前重试次数（从0开始，0表示第一次重试）
  /// 返回计算后的延迟时间，不会超过maxDelay
  Duration getDelay(int attemptNumber) {
    if (attemptNumber < 0) {
      return Duration.zero;
    }

    // 计算指数退避延迟
    final baseDelay = initialDelay.inMilliseconds *
        math.pow(backoffFactor, attemptNumber);

    // 限制最大延迟
    var delayMs = math.min(baseDelay, maxDelay.inMilliseconds.toDouble());

    // 添加抖动（0-25%的随机偏移）
    if (enableJitter && delayMs > 0) {
      final jitter = delayMs * 0.25 * math.Random().nextDouble();
      delayMs = delayMs + jitter;
    }

    return Duration(milliseconds: delayMs.round());
  }

  /// 判断是否可以继续重试
  ///
  /// [attemptNumber] 当前重试次数（从0开始）
  /// 返回true表示还可以继续重试
  bool canRetry(int attemptNumber) {
    return attemptNumber < maxAttempts;
  }

  /// 判断是否应该对给定的错误进行重试
  ///
  /// 根据错误类型智能判断：
  /// - 网络错误（SocketException, TimeoutException）: 可重试
  /// - 服务器错误（5xx）: 可重试
  /// - 客户端错误（4xx）: 不可重试
  /// - 解析错误: 不可重试
  /// - 文件错误: 不可重试
  ///
  /// [error] 发生的错误
  /// [attemptNumber] 当前重试次数（从0开始）
  /// 返回true表示应该重试
  bool shouldRetry(Object error, int attemptNumber) {
    // 检查是否还有重试次数
    if (!canRetry(attemptNumber)) {
      return false;
    }

    // 如果是UpdateError，检查错误代码
    if (error is UpdateError) {
      return _shouldRetryUpdateError(error);
    }

    // 如果是原始异常，检查异常类型
    if (error is Exception) {
      return _shouldRetryException(error);
    }

    // 其他错误类型默认不重试
    return false;
  }

  /// 判断UpdateError是否应该重试
  bool _shouldRetryUpdateError(UpdateError error) {
    switch (error.code) {
      // 网络相关错误 - 可重试
      case 'NETWORK_ERROR':
      case 'TIMEOUT':
      case 'CONNECTION_ERROR':
        return true;

      // 服务器错误 - 可重试
      case 'SERVER_ERROR':
      case 'SERVICE_UNAVAILABLE':
        return true;

      // 客户端错误 - 不可重试
      case 'PARSE_ERROR':
      case 'INVALID_RESPONSE':
      case 'MISSING_URL':
      case 'MISSING_VERSION':
      case 'INVALID_METHOD':
      case 'INVALID_BODY':
        return false;

      // 文件相关错误 - 不可重试
      case 'FILE_ERROR':
      case 'MD5_MISMATCH':
        return false;

      // 权限相关错误 - 不可重试
      case 'PERMISSION_DENIED':
      case 'PLATFORM_NOT_SUPPORTED':
        return false;

      // 未知错误 - 检查原始异常
      default:
        if (error.exception != null) {
          return _shouldRetryException(error.exception!);
        }
        return false;
    }
  }

  /// 判断原始异常是否应该重试
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
