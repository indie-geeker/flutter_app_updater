import 'package:flutter/foundation.dart';

import '../actions/update_action.dart';
import '../download/package_downloader.dart';
import '../models/update_error_code.dart';
import 'download_package_executor.dart';
import 'install_package_executor.dart';
import 'streaming_update_action_executor.dart';
import 'update_action_cancel_token.dart';
import 'update_action_executor.dart';
import 'update_action_event.dart';

class DownloadAndInstallPackageExecutor
    implements StreamingUpdateActionExecutor {
  final DownloadPackageExecutor downloadExecutor;
  final InstallPackageExecutor installExecutor;
  final TargetPlatform targetPlatform;

  DownloadAndInstallPackageExecutor({
    required String downloadDirectory,
    PackageDownloader? downloader,
    InstallPackageExecutor? installExecutor,
    TargetPlatform? targetPlatform,
  })  : downloadExecutor = DownloadPackageExecutor(
          downloadDirectory: downloadDirectory,
          downloader: downloader,
        ),
        targetPlatform = targetPlatform ?? defaultTargetPlatform,
        installExecutor = installExecutor ??
            InstallPackageExecutor(
              targetPlatform: targetPlatform ?? defaultTargetPlatform,
            );

  @override
  bool supports(UpdateAction action) =>
      targetPlatform == TargetPlatform.android &&
      action is DownloadAndInstallPackageAction &&
      action.packageType == PackageType.apk;

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    await for (final event in performStream(action)) {
      if (event case UpdateActionCompleted(:final result)) {
        return result;
      }
    }
    return const UpdateActionResult.failure(
      code: UpdateErrorCode.packageDownloadFailed,
      message: 'Package installation ended without a result.',
    );
  }

  @override
  Stream<UpdateActionEvent> performStream(
    UpdateAction action, {
    UpdateActionCancelToken? cancelToken,
  }) async* {
    yield UpdateActionStarted(action);
    if (action is! DownloadAndInstallPackageAction) {
      yield const UpdateActionCompleted(
        UpdateActionResult.failure(
          code: UpdateErrorCode.noSupportedAction,
          message: 'DownloadAndInstallPackageExecutor only supports '
              'download-and-install package actions.',
        ),
      );
      return;
    }
    if (targetPlatform != TargetPlatform.android) {
      yield const UpdateActionCompleted(
        UpdateActionResult.failure(
          code: UpdateErrorCode.platformNotSupported,
          message: 'Package installation requires Android.',
        ),
      );
      return;
    }
    if (action.packageType != PackageType.apk) {
      yield const UpdateActionCompleted(
        UpdateActionResult.failure(
          code: UpdateErrorCode.manifestInvalid,
          message: 'Only APK packages can be installed locally.',
        ),
      );
      return;
    }

    UpdateActionResult? downloadResult;
    await for (final event in downloadExecutor.performStream(
      DownloadPackageAction(
        packageUrl: action.packageUrl,
        packageType: action.packageType,
        packageSizeBytes: action.packageSizeBytes,
        sha256: action.sha256,
      ),
      cancelToken: cancelToken,
    )) {
      switch (event) {
        case UpdateActionProgress(
            :final downloadedBytes,
            :final totalBytes,
          ):
          yield UpdateActionProgress(
            action: action,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
          );
        case UpdateActionCompleted(:final result):
          downloadResult = result;
        case UpdateActionStarted():
          break;
      }
    }

    final result = downloadResult;
    if (result == null || !result.isSuccess || result.file == null) {
      yield UpdateActionCompleted(
        UpdateActionResult.failure(
          code: result?.code ?? UpdateErrorCode.packageDownloadFailed,
          message: result?.message ?? 'Package download failed.',
        ),
      );
      return;
    }
    if (cancelToken?.isCanceled ?? false) {
      yield const UpdateActionCompleted(
        UpdateActionResult.failure(
          code: UpdateErrorCode.actionCanceled,
          message: 'Package installation canceled.',
        ),
      );
      return;
    }

    final installResult = await installExecutor.perform(
      InstallPackageAction(
        packagePath: result.file!.path,
        packageType: action.packageType,
        packageSizeBytes: action.packageSizeBytes,
        sha256: action.sha256,
      ),
    );
    if (!installResult.isSuccess) {
      yield UpdateActionCompleted(installResult);
      return;
    }

    yield UpdateActionCompleted(
      UpdateActionResult.success(
        file: result.file,
        downloadedBytes: result.downloadedBytes,
        sha256: result.sha256,
      ),
    );
  }
}
