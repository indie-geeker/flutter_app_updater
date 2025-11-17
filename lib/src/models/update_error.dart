/// 更新错误类
class UpdateError {
  /// 错误代码
  final String code;

  /// 错误消息
  final String message;

  /// 原始异常
  final dynamic exception;

  /// 堆栈跟踪信息
  final StackTrace? stackTrace;

  const UpdateError({
    required this.code,
    required this.message,
    this.exception,
    this.stackTrace,
  });

  /// 预定义错误：网络错误
  factory UpdateError.network(dynamic exception, [StackTrace? stackTrace]) =>
      UpdateError(
        code: 'NETWORK_ERROR',
        message: '网络连接失败，请检查网络设置',
        exception: exception,
        stackTrace: stackTrace ?? StackTrace.current,
      );

  /// 预定义错误：服务器错误
  factory UpdateError.server(dynamic exception, [StackTrace? stackTrace]) =>
      UpdateError(
        code: 'SERVER_ERROR',
        message: '服务器响应错误，请稍后再试',
        exception: exception,
        stackTrace: stackTrace ?? StackTrace.current,
      );

  /// 预定义错误：下载错误
  factory UpdateError.download(dynamic exception, [StackTrace? stackTrace]) =>
      UpdateError(
        code: 'DOWNLOAD_ERROR',
        message: '下载更新文件失败',
        exception: exception,
        stackTrace: stackTrace ?? StackTrace.current,
      );

  /// 预定义错误：解析错误
  factory UpdateError.parse(dynamic exception, [StackTrace? stackTrace]) =>
      UpdateError(
        code: 'PARSE_ERROR',
        message: '解析更新信息失败',
        exception: exception,
        stackTrace: stackTrace ?? StackTrace.current,
      );

  /// 预定义错误：应用错误
  factory UpdateError.application(dynamic exception, [StackTrace? stackTrace]) =>
      UpdateError(
        code: 'APPLICATION_ERROR',
        message: '应用程序错误',
        exception: exception,
        stackTrace: stackTrace ?? StackTrace.current,
      );

  /// 预定义错误：文件错误
  factory UpdateError.file(dynamic exception, [StackTrace? stackTrace]) =>
      UpdateError(
        code: 'FILE_ERROR',
        message: '文件操作错误',
        exception: exception,
        stackTrace: stackTrace ?? StackTrace.current,
      );

  @override
  String toString() {
    final buffer = StringBuffer('UpdateError(code: $code, message: $message)');
    if (exception != null) {
      buffer.write('\nException: $exception');
    }
    if (stackTrace != null) {
      buffer.write('\nStackTrace:\n$stackTrace');
    }
    return buffer.toString();
  }
}