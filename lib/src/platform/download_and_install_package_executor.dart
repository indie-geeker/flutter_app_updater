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
    return _perform(action);
  }

  @override
  Stream<UpdateActionEvent> performStream(
    UpdateAction action, {
    UpdateActionCancelToken? cancelToken,
  }) async* {
    yield UpdateActionStarted(action);
    await for (final event in _performStreamBody(
      action,
      cancelToken: cancelToken,
    )) {
      yield event;
    }
  }

  Future<UpdateActionResult> _perform(UpdateAction action) async {
    if (action is! DownloadAndInstallPackageAction) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.noSupportedAction,
        message: 'DownloadAndInstallPackageExecutor only supports '
            'download-and-install package actions.',
      );
    }

    if (action.packageType != PackageType.apk) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.manifestInvalid,
        message: 'Only APK packages can be downloaded and installed locally.',
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

  Stream<UpdateActionEvent> _performStreamBody(
    UpdateAction action, {
    UpdateActionCancelToken? cancelToken,
  }) async* {
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

    if (action.packageType != PackageType.apk) {
      yield const UpdateActionCompleted(
        UpdateActionResult.failure(
          code: UpdateErrorCode.manifestInvalid,
          message: 'Only APK packages can be downloaded and installed locally.',
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

    final installResult = await installExecutor.perform(
      InstallPackageAction(
        packagePath: result.file!.path,
        packageType: action.packageType,
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
