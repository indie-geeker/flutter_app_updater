import 'dart:async';

import '../actions/update_action.dart';
import '../download/package_downloader.dart';
import '../models/update_error_code.dart';
import 'download_package_executor.dart';
import 'install_package_executor.dart';
import 'streaming_update_action_executor.dart';
import 'update_action_event.dart';
import 'update_action_executor.dart';

class DownloadAndInstallPackageExecutor
    implements UpdateActionExecutor, StreamingUpdateActionExecutor {
  final DownloadPackageExecutor downloadExecutor;
  final InstallPackageExecutor installExecutor;

  DownloadAndInstallPackageExecutor({
    required String downloadDirectory,
    PackageDownloader? downloader,
    InstallPackageExecutor? installExecutor,
  })  : downloadExecutor = DownloadPackageExecutor(
          downloadDirectory: downloadDirectory,
          downloader: downloader,
        ),
        installExecutor = installExecutor ?? InstallPackageExecutor();

  @override
  bool supports(UpdateAction action) =>
      action is DownloadAndInstallPackageAction;

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    if (action is! DownloadAndInstallPackageAction) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.noSupportedAction,
        message: 'DownloadAndInstallPackageExecutor only supports '
            'download-and-install package actions.',
      );
    }

    final downloadResult = await downloadExecutor.perform(
      DownloadPackageAction(
        packageUrl: action.packageUrl,
        packageType: action.packageType,
        packageSizeBytes: action.packageSizeBytes,
        sha256: action.sha256,
      ),
    );

    if (!downloadResult.isSuccess || downloadResult.file == null) {
      return UpdateActionResult.failure(
        code: downloadResult.code ?? UpdateErrorCode.packageDownloadFailed,
        message: downloadResult.message ?? 'Package download failed.',
      );
    }

    final installResult = await installExecutor.perform(
      InstallPackageAction(
        packagePath: downloadResult.file!.path,
        packageType: action.packageType,
      ),
    );

    if (!installResult.isSuccess) {
      return installResult;
    }

    return UpdateActionResult.success(
      file: downloadResult.file,
      downloadedBytes: downloadResult.downloadedBytes,
      sha256: downloadResult.sha256,
    );
  }

  @override
  Stream<UpdateActionEvent> performStream(UpdateAction action) {
    var isActive = true;
    final cancelCompleter = Completer<void>();
    StreamSubscription<UpdateActionEvent>? downloadSubscription;
    late final StreamController<UpdateActionEvent> controller;
    controller = StreamController<UpdateActionEvent>(
      onListen: () {
        unawaited(
          _performDownloadAndInstallStream(
            action: action,
            controller: controller,
            isActive: () => isActive,
            cancelSignal: cancelCompleter.future,
            setDownloadSubscription: (subscription) {
              downloadSubscription = subscription;
            },
          ),
        );
      },
      onCancel: () async {
        isActive = false;
        if (!cancelCompleter.isCompleted) {
          cancelCompleter.complete();
        }
        await downloadSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> _performDownloadAndInstallStream({
    required UpdateAction action,
    required StreamController<UpdateActionEvent> controller,
    required bool Function() isActive,
    required Future<void> cancelSignal,
    required void Function(StreamSubscription<UpdateActionEvent> subscription)
        setDownloadSubscription,
  }) async {
    void add(UpdateActionEvent event) {
      if (isActive() && !controller.isClosed) {
        controller.add(event);
      }
    }

    try {
      add(UpdateActionStarted(action));

      if (action is! DownloadAndInstallPackageAction) {
        add(
          const UpdateActionFailed(
            UpdateActionResult.failure(
              code: UpdateErrorCode.noSupportedAction,
              message: 'DownloadAndInstallPackageExecutor only supports '
                  'download-and-install package actions.',
            ),
          ),
        );
        return;
      }

      final downloadResult = await _collectDownloadEvents(
        action: _downloadAction(action),
        add: add,
        cancelSignal: cancelSignal,
        setDownloadSubscription: setDownloadSubscription,
      );

      if (!isActive()) {
        return;
      }

      if (downloadResult == null ||
          !downloadResult.isSuccess ||
          downloadResult.file == null) {
        add(
          UpdateActionFailed(
            UpdateActionResult.failure(
              code:
                  downloadResult?.code ?? UpdateErrorCode.packageDownloadFailed,
              message: downloadResult?.message ?? 'Package download failed.',
            ),
          ),
        );
        return;
      }

      final packagePath = downloadResult.file!.path;
      add(UpdateInstallStarted(packagePath: packagePath));

      final installResult = await installExecutor.perform(
        InstallPackageAction(
          packagePath: packagePath,
          packageType: action.packageType,
        ),
      );

      if (!installResult.isSuccess) {
        if (installResult.code ==
            UpdateErrorCode.packageInstallPermissionRequired) {
          add(UpdateInstallPermissionRequired(packagePath: packagePath));
        }
        add(UpdateActionFailed(installResult));
        return;
      }

      add(
        UpdateActionCompleted(
          UpdateActionResult.success(
            file: downloadResult.file,
            downloadedBytes: downloadResult.downloadedBytes,
            sha256: downloadResult.sha256,
          ),
        ),
      );
    } finally {
      if (!controller.isClosed) {
        await controller.close();
      }
    }
  }

  Future<UpdateActionResult?> _collectDownloadEvents({
    required DownloadPackageAction action,
    required void Function(UpdateActionEvent event) add,
    required Future<void> cancelSignal,
    required void Function(StreamSubscription<UpdateActionEvent> subscription)
        setDownloadSubscription,
  }) async {
    final completed = Completer<UpdateActionResult?>();
    final canceled = Object();
    UpdateActionResult? downloadResult;
    UpdateActionResult? failureResult;

    final subscription = downloadExecutor.performStream(action).listen(
      (event) {
        switch (event) {
          case UpdateActionStarted():
          case UpdateActionCompleted():
            break;
          case UpdateDownloadProgress():
            add(event);
          case UpdateDownloadCompleted(:final result):
            downloadResult = result;
            add(event);
          case UpdateInstallStarted():
          case UpdateInstallPermissionRequired():
            add(event);
          case UpdateActionFailed(:final result):
            failureResult = result;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!completed.isCompleted) {
          completed.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completed.isCompleted) {
          completed.complete(failureResult ?? downloadResult);
        }
      },
      cancelOnError: true,
    );
    setDownloadSubscription(subscription);

    final result = await Future.any<Object?>([
      completed.future,
      cancelSignal.then<Object?>((_) => canceled),
    ]);

    if (identical(result, canceled)) {
      return null;
    }
    return result as UpdateActionResult?;
  }

  DownloadPackageAction _downloadAction(
      DownloadAndInstallPackageAction action) {
    return DownloadPackageAction(
      packageUrl: action.packageUrl,
      packageType: action.packageType,
      packageSizeBytes: action.packageSizeBytes,
      sha256: action.sha256,
    );
  }
}
