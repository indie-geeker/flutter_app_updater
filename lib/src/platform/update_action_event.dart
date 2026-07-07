import '../actions/update_action.dart';
import 'update_action_executor.dart';

sealed class UpdateActionEvent {
  const UpdateActionEvent();
}

class UpdateActionStarted extends UpdateActionEvent {
  final UpdateAction action;

  const UpdateActionStarted(this.action);
}

class UpdateDownloadProgress extends UpdateActionEvent {
  final int receivedBytes;
  final int? totalBytes;

  const UpdateDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return receivedBytes / total;
  }
}

class UpdateDownloadCompleted extends UpdateActionEvent {
  final UpdateActionResult result;

  const UpdateDownloadCompleted(this.result);
}

class UpdateInstallStarted extends UpdateActionEvent {
  final String packagePath;

  const UpdateInstallStarted({required this.packagePath});
}

class UpdateInstallPermissionRequired extends UpdateActionEvent {
  final String packagePath;

  const UpdateInstallPermissionRequired({required this.packagePath});
}

class UpdateActionCompleted extends UpdateActionEvent {
  final UpdateActionResult result;

  const UpdateActionCompleted(this.result);
}

class UpdateActionFailed extends UpdateActionEvent {
  final UpdateActionResult result;

  const UpdateActionFailed(this.result);
}
