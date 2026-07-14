import 'package:flutter_app_updater/flutter_app_updater.dart';

import 'demo_scenario.dart';

class SimulatedUpdateExecutor implements StreamingUpdateActionExecutor {
  final DemoOutcome outcome;
  final Duration duration;
  final int totalBytes;
  final bool succeedOnRetry;

  int _attemptCount = 0;

  SimulatedUpdateExecutor({
    required this.outcome,
    required this.duration,
    required this.totalBytes,
    this.succeedOnRetry = false,
  });

  int get attemptCount => _attemptCount;

  @override
  bool supports(UpdateAction action) {
    return action is OpenStoreAction ||
        action is OpenAndroidMarketAction ||
        action is DownloadPackageAction ||
        action is InstallPackageAction ||
        action is DownloadAndInstallPackageAction ||
        action is OpenInstallerAction;
  }

  static bool supportsOutcome(UpdateAction action, DemoOutcome outcome) {
    return switch (outcome) {
      DemoOutcome.success ||
      DemoOutcome.platformNotSupported ||
      DemoOutcome.actionFailed =>
        true,
      DemoOutcome.downloadFailed ||
      DemoOutcome.hashMismatch =>
        _isDownloadRelated(action),
      DemoOutcome.installPermissionRequired => _isInstallation(action),
    };
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
    _attemptCount++;
    yield UpdateActionStarted(action);

    if (_isDownloadRelated(action)) {
      final stepDelay = Duration(
        microseconds: duration.inMicroseconds ~/ 4,
      );
      for (final percent in const [25, 50, 75, 100]) {
        if (_isCanceled(cancelToken)) {
          yield const UpdateActionCompleted(_canceledResult);
          return;
        }
        await Future<void>.delayed(stepDelay);
        if (_isCanceled(cancelToken)) {
          yield const UpdateActionCompleted(_canceledResult);
          return;
        }
        yield UpdateActionProgress(
          action: action,
          downloadedBytes: totalBytes * percent ~/ 100,
          totalBytes: totalBytes,
        );
      }
    } else {
      if (_isCanceled(cancelToken)) {
        yield const UpdateActionCompleted(_canceledResult);
        return;
      }
      await Future<void>.delayed(duration);
      if (_isCanceled(cancelToken)) {
        yield const UpdateActionCompleted(_canceledResult);
        return;
      }
    }

    yield UpdateActionCompleted(_terminalResult(action));
  }

  UpdateActionResult _terminalResult(UpdateAction action) {
    final effectiveOutcome =
        succeedOnRetry && _attemptCount > 1 ? DemoOutcome.success : outcome;
    if (!supportsOutcome(action, effectiveOutcome)) {
      return UpdateActionResult.failure(
        code: UpdateErrorCode.actionFailed,
        message:
            'The configured ${effectiveOutcome.name} outcome is not available '
            'for ${action.runtimeType}.',
      );
    }
    return switch (effectiveOutcome) {
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

  static bool _isDownloadRelated(UpdateAction action) {
    return action is DownloadPackageAction ||
        action is DownloadAndInstallPackageAction ||
        action is OpenInstallerAction;
  }

  static bool _isInstallation(UpdateAction action) {
    return action is InstallPackageAction ||
        action is DownloadAndInstallPackageAction;
  }

  static bool _isCanceled(UpdateActionCancelToken? token) {
    return token?.isCanceled ?? false;
  }

  static const _canceledResult = UpdateActionResult.failure(
    code: UpdateErrorCode.actionCanceled,
    message: 'The simulated update was canceled.',
  );
}
