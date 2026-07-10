import '../actions/update_action.dart';
import 'update_action_executor.dart';

sealed class UpdateActionEvent {
  const UpdateActionEvent();
}

class UpdateActionStarted extends UpdateActionEvent {
  final UpdateAction action;

  const UpdateActionStarted(this.action);
}

class UpdateActionProgress extends UpdateActionEvent {
  final UpdateAction action;
  final int downloadedBytes;
  final int? totalBytes;

  const UpdateActionProgress({
    required this.action,
    required this.downloadedBytes,
    this.totalBytes,
  });

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return (downloadedBytes / total).clamp(0.0, 1.0).toDouble();
  }
}

class UpdateActionCompleted extends UpdateActionEvent {
  final UpdateActionResult result;

  const UpdateActionCompleted(this.result);
}
