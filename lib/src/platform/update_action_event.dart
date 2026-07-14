import '../actions/update_action.dart';
import 'update_action_executor.dart';

/// Lifecycle event emitted while an explicit update action executes.
sealed class UpdateActionEvent {
  const UpdateActionEvent();
}

/// First event emitted for an action attempt.
class UpdateActionStarted extends UpdateActionEvent {
  /// Action that began execution.
  final UpdateAction action;

  /// Creates a started event for [action].
  const UpdateActionStarted(this.action);
}

/// Byte-transfer progress for a download-related action.
class UpdateActionProgress extends UpdateActionEvent {
  /// Action producing this transfer progress.
  final UpdateAction action;

  /// Bytes transferred so far.
  final int downloadedBytes;

  /// Expected total bytes, when known.
  final int? totalBytes;

  /// Creates a progress event.
  const UpdateActionProgress({
    required this.action,
    required this.downloadedBytes,
    this.totalBytes,
  });

  /// Clamped progress from zero to one, or `null` without a positive total.
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return (downloadedBytes / total).clamp(0.0, 1.0).toDouble();
  }
}

/// Single terminal event for an action attempt.
class UpdateActionCompleted extends UpdateActionEvent {
  /// Structured success or failure result.
  final UpdateActionResult result;

  /// Creates a terminal event containing [result].
  const UpdateActionCompleted(this.result);
}
