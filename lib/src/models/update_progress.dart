/// 更新下载进度模型
class UpdateProgress {
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

  const UpdateProgress({
    required this.downloaded,
    required this.total,
    this.speed,
    this.estimatedTimeRemaining,
  });

  /// 创建初始进度对象
  factory UpdateProgress.initial(int total) =>
      UpdateProgress(downloaded: 0, total: total);

  /// 创建未知总大小的进度对象
  factory UpdateProgress.unknown() =>
      const UpdateProgress(downloaded: 0, total: 0);

  /// 创建基于当前进度的新进度对象
  UpdateProgress copyWith({
    int? downloaded,
    int? total,
    int? speed,
    int? estimatedTimeRemaining,
  }) {
    return UpdateProgress(
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
      return '$minutes分$remainingSeconds秒';
    } else {
      final hours = (seconds / 3600).floor();
      final remainingMinutes = ((seconds % 3600) / 60).floor();
      return '$hours小时$remainingMinutes分';
    }
  }
}