/// 应用更新状态枚举
enum UpdateStatus {
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