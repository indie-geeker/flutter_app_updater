import 'update_error.dart';
import 'update_info.dart';

/// 更新检查结果类型。
enum UpdateCheckOutcome {
  /// 服务端返回了比当前版本更新的版本。
  available,

  /// 检查成功，但当前版本已经是最新。
  notAvailable,

  /// 检查失败，例如网络、解析或版本格式错误。
  failed,
}

/// 更新检查结果。
///
/// 用于区分“没有更新”和“检查失败”。旧的 `checkForUpdate()` 仍返回
/// `UpdateInfo?`，需要错误细节时使用 `checkForUpdateResult()`。
class UpdateCheckResult {
  /// 结果类型。
  final UpdateCheckOutcome outcome;

  /// 可用更新信息，仅 [UpdateCheckOutcome.available] 时有值。
  final UpdateInfo? updateInfo;

  /// 失败信息，仅 [UpdateCheckOutcome.failed] 时有值。
  final UpdateError? error;

  const UpdateCheckResult._({
    required this.outcome,
    this.updateInfo,
    this.error,
  });

  /// 创建“有更新”结果。
  factory UpdateCheckResult.available(UpdateInfo updateInfo) {
    return UpdateCheckResult._(
      outcome: UpdateCheckOutcome.available,
      updateInfo: updateInfo,
    );
  }

  /// 创建“无更新”结果。
  const factory UpdateCheckResult.notAvailable() = _NotAvailableResult;

  /// 创建“检查失败”结果。
  factory UpdateCheckResult.failed(UpdateError error) {
    return UpdateCheckResult._(
      outcome: UpdateCheckOutcome.failed,
      error: error,
    );
  }

  /// 是否有更新。
  bool get isAvailable => outcome == UpdateCheckOutcome.available;

  /// 是否无更新。
  bool get isNotAvailable => outcome == UpdateCheckOutcome.notAvailable;

  /// 是否检查失败。
  bool get isFailed => outcome == UpdateCheckOutcome.failed;
}

class _NotAvailableResult extends UpdateCheckResult {
  const _NotAvailableResult()
      : super._(outcome: UpdateCheckOutcome.notAvailable);
}
