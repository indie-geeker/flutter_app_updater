/// 应用更新状态枚举
enum AppUpdateStatus {
  /// 初始状态
  idle,
  
  /// 正在检查更新
  checking,
  
  /// 有可用更新
  available,
  
  /// 无可用更新
  notAvailable,
  
  /// 正在下载更新
  downloading,
  
  /// 下载暂停
  paused,
  
  /// 下载完成
  downloaded,
  
  /// 已取消
  canceled,
  
  /// 发生错误
  error,
}

/// 更新下载进度模型
class AppUpdateProgress {
  /// 已下载的字节数
  final int downloaded;
  
  /// 总字节数
  final int total;
  
  /// 下载速度（字节/秒）
  final int? speed;
  
  /// 估计剩余时间（秒）
  final int? estimatedTimeRemaining;
  
  /// 计算下载进度百分比 (0.0 - 1.0)
  double get progress => 
      total > 0 ? downloaded / total : 0.0;
  
  /// 计算进度百分比 (0 - 100)
  int get progressPercentage => 
      (progress * 100).round();

  const AppUpdateProgress({
    required this.downloaded,
    required this.total,
    this.speed,
    this.estimatedTimeRemaining,
  });
  
  /// 创建初始进度对象
  factory AppUpdateProgress.initial(int total) => 
      AppUpdateProgress(downloaded: 0, total: total);
      
  /// 创建未知总大小的进度对象
  factory AppUpdateProgress.unknown() => 
      const AppUpdateProgress(downloaded: 0, total: 0);
  
  /// 创建基于当前进度的新进度对象
  AppUpdateProgress copyWith({
    int? downloaded,
    int? total,
    int? speed,
    int? estimatedTimeRemaining,
  }) {
    return AppUpdateProgress(
      downloaded: downloaded ?? this.downloaded,
      total: total ?? this.total,
      speed: speed ?? this.speed,
      estimatedTimeRemaining: estimatedTimeRemaining ?? this.estimatedTimeRemaining,
    );
  }
  
  @override
  String toString() {
    return 'AppUpdateProgress(downloaded: $downloaded, total: $total, '
           'progress: ${(progress * 100).toStringAsFixed(1)}%, '
           'speed: ${_formatSpeed()}, '
           'estimatedTimeRemaining: ${_formatTime()})';
  }
  
  /// 格式化速度为人类可读格式
  String _formatSpeed() {
    if (speed == null) return 'unknown';
    
    if (speed! < 1024) {
      return '$speed B/s';
    } else if (speed! < 1024 * 1024) {
      return '${(speed! / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${(speed! / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
  }
  
  /// 格式化剩余时间为人类可读格式
  String _formatTime() {
    if (estimatedTimeRemaining == null) return 'unknown';
    
    final seconds = estimatedTimeRemaining!;
    if (seconds < 60) {
      return '$seconds秒';
    } else if (seconds < 3600) {
      final minutes = (seconds / 60).floor();
      final remainingSeconds = seconds % 60;
      return '$minutes分${remainingSeconds}秒';
    } else {
      final hours = (seconds / 3600).floor();
      final remainingMinutes = ((seconds % 3600) / 60).floor();
      return '$hours小时${remainingMinutes}分';
    }
  }
}

/// 更新错误类
class AppUpdateError {
  /// 错误代码
  final String code;
  
  /// 错误消息
  final String message;
  
  /// 原始异常
  final dynamic exception;

  const AppUpdateError({
    required this.code,
    required this.message,
    this.exception,
  });
  
  /// 预定义错误：网络错误
  factory AppUpdateError.network(dynamic exception) => 
      AppUpdateError(
        code: 'NETWORK_ERROR',
        message: '网络连接失败，请检查网络设置',
        exception: exception,
      );
  
  /// 预定义错误：服务器错误
  factory AppUpdateError.server(dynamic exception) => 
      AppUpdateError(
        code: 'SERVER_ERROR',
        message: '服务器响应错误，请稍后再试',
        exception: exception,
      );
  
  /// 预定义错误：下载错误
  factory AppUpdateError.download(dynamic exception) => 
      AppUpdateError(
        code: 'DOWNLOAD_ERROR',
        message: '下载更新文件失败',
        exception: exception,
      );
      
  /// 预定义错误：解析错误
  factory AppUpdateError.parse(dynamic exception) => 
      AppUpdateError(
        code: 'PARSE_ERROR',
        message: '解析更新信息失败',
        exception: exception,
      );
      
  /// 预定义错误：应用错误
  factory AppUpdateError.application(dynamic exception) => 
      AppUpdateError(
        code: 'APPLICATION_ERROR',
        message: '应用程序错误',
        exception: exception,
      );
      
  /// 预定义错误：文件错误
  factory AppUpdateError.file(dynamic exception) => 
      AppUpdateError(
        code: 'FILE_ERROR',
        message: '文件操作错误',
        exception: exception,
      );

  @override
  String toString() => 'AppUpdateError(code: $code, message: $message)';
}
