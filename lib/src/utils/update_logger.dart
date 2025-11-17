import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// 日志级别枚举
enum LogLevel {
  /// 不输出任何日志
  none,

  /// 仅输出错误日志
  error,

  /// 输出错误和警告日志
  warning,

  /// 输出错误、警告和信息日志
  info,

  /// 输出所有日志（包括调试信息）
  debug,
}

/// 应用更新日志工具类
///
/// 提供分级日志功能，可以通过 [setLogLevel] 控制日志输出级别
/// 在生产环境中建议设置为 [LogLevel.error] 或 [LogLevel.none]
class UpdateLogger {
  UpdateLogger._();

  /// 当前日志级别，默认为 debug 模式下为 info，release 模式下为 error
  static LogLevel _logLevel = kDebugMode ? LogLevel.info : LogLevel.error;

  /// 设置日志级别
  ///
  /// [level] 要设置的日志级别
  ///
  /// 示例：
  /// ```dart
  /// // 只输出错误日志
  /// UpdateLogger.setLogLevel(LogLevel.error);
  ///
  /// // 输出所有日志
  /// UpdateLogger.setLogLevel(LogLevel.debug);
  ///
  /// // 关闭所有日志
  /// UpdateLogger.setLogLevel(LogLevel.none);
  /// ```
  static void setLogLevel(LogLevel level) {
    _logLevel = level;
  }

  /// 获取当前日志级别
  static LogLevel getLogLevel() {
    return _logLevel;
  }

  /// 输出调试日志
  ///
  /// [message] 日志消息
  /// [tag] 日志标签，默认为 'UpdateLogger'
  ///
  /// 仅在日志级别为 [LogLevel.debug] 时输出
  static void debug(String message, {String tag = 'UpdateLogger'}) {
    if (_logLevel.index >= LogLevel.debug.index) {
      _log('DEBUG', message, tag);
    }
  }

  /// 输出信息日志
  ///
  /// [message] 日志消息
  /// [tag] 日志标签，默认为 'UpdateLogger'
  ///
  /// 在日志级别为 [LogLevel.info] 或更高时输出
  static void info(String message, {String tag = 'UpdateLogger'}) {
    if (_logLevel.index >= LogLevel.info.index) {
      _log('INFO', message, tag);
    }
  }

  /// 输出警告日志
  ///
  /// [message] 日志消息
  /// [tag] 日志标签，默认为 'UpdateLogger'
  ///
  /// 在日志级别为 [LogLevel.warning] 或更高时输出
  static void warning(String message, {String tag = 'UpdateLogger'}) {
    if (_logLevel.index >= LogLevel.warning.index) {
      _log('WARNING', message, tag);
    }
  }

  /// 输出错误日志
  ///
  /// [message] 日志消息
  /// [error] 错误对象（可选）
  /// [stackTrace] 堆栈跟踪（可选）
  /// [tag] 日志标签，默认为 'UpdateLogger'
  ///
  /// 在日志级别为 [LogLevel.error] 或更高时输出
  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String tag = 'UpdateLogger',
  }) {
    if (_logLevel.index >= LogLevel.error.index) {
      _log('ERROR', message, tag);
      if (error != null) {
        debugPrint('[$tag] Error Object: $error');
      }
      if (stackTrace != null) {
        debugPrint('[$tag] Stack Trace:\n$stackTrace');
      }
    }
  }

  /// 内部日志输出方法
  static void _log(String level, String message, String tag) {
    final timestamp = DateTime.now().toIso8601String();
    debugPrint('[$timestamp] [$tag] [$level] $message');
  }

  /// 格式化JSON输出（用于调试）
  ///
  /// [json] 要格式化的JSON对象
  /// [maxLength] 最大输出长度，默认1000字符
  ///
  /// 返回格式化后的字符串
  static String formatJson(Map<String, dynamic> json, {int maxLength = 1000}) {
    try {
      final prettyString = json.toString();
      if (prettyString.length > maxLength) {
        return '${prettyString.substring(0, maxLength)}... (截断，完整长度: ${prettyString.length})';
      }
      return prettyString;
    } catch (e) {
      return json.toString();
    }
  }
}
