import 'package:flutter_app_updater/flutter_app_updater.dart';

import 'demo_scenario.dart';

class SimulatedUpdateExecutor implements StreamingUpdateActionExecutor {
  final DemoOutcome outcome;
  final Duration duration;
  final int totalBytes;

  const SimulatedUpdateExecutor({
    required this.outcome,
    required this.duration,
    required this.totalBytes,
  });

  @override
  bool supports(UpdateAction action) {
    return action is OpenStoreAction ||
        action is OpenAndroidMarketAction ||
        action is DownloadAndInstallPackageAction ||
        action is OpenInstallerAction;
  }

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    await for (final event in performStream(action)) {
      if (event case UpdateActionCompleted(:final result)) {
        return result;
      }
    }
    return const UpdateActionResult.failure(
      code: UpdateErrorCode.actionFailed,
      message: 'Simulation ended without a terminal result.',
    );
  }

  @override
  Stream<UpdateActionEvent> performStream(
    UpdateAction action, {
    UpdateActionCancelToken? cancelToken,
  }) async* {
    yield UpdateActionStarted(action);
    final stepDelay = Duration(
      microseconds: duration.inMicroseconds ~/ 4,
    );

    for (final percent in const [25, 50, 75, 100]) {
      if (cancelToken?.isCanceled ?? false) {
        yield const UpdateActionCompleted(
          UpdateActionResult.failure(
            code: UpdateErrorCode.actionCanceled,
            message: 'The simulated update was canceled.',
          ),
        );
        return;
      }

      await Future<void>.delayed(stepDelay);

      if (cancelToken?.isCanceled ?? false) {
        yield const UpdateActionCompleted(
          UpdateActionResult.failure(
            code: UpdateErrorCode.actionCanceled,
            message: 'The simulated update was canceled.',
          ),
        );
        return;
      }

      yield UpdateActionProgress(
        action: action,
        downloadedBytes: totalBytes * percent ~/ 100,
        totalBytes: totalBytes,
      );
    }

    yield UpdateActionCompleted(_terminalResult());
  }

  UpdateActionResult _terminalResult() {
    return switch (outcome) {
      DemoOutcome.success => const UpdateActionResult.success(),
      DemoOutcome.downloadFailed => const UpdateActionResult.failure(
          code: UpdateErrorCode.packageDownloadFailed,
          message: 'The simulated download failed.',
        ),
      DemoOutcome.hashMismatch => const UpdateActionResult.failure(
          code: UpdateErrorCode.packageHashMismatch,
          message: 'The simulated package hash did not match.',
        ),
      DemoOutcome.installPermissionRequired => const UpdateActionResult.failure(
          code: UpdateErrorCode.packageInstallPermissionRequired,
          message: 'Install permission is required for this simulated update.',
        ),
      DemoOutcome.platformNotSupported => const UpdateActionResult.failure(
          code: UpdateErrorCode.platformNotSupported,
          message: 'The simulated platform does not support this action.',
        ),
      DemoOutcome.actionFailed => const UpdateActionResult.failure(
          code: UpdateErrorCode.actionFailed,
          message: 'The simulated update action failed.',
        ),
    };
  }
}
