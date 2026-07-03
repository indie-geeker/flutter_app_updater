import '../actions/update_action.dart';
import '../download/package_downloader.dart';
import '../models/update_error_code.dart';
import 'download_package_executor.dart';
import 'install_package_executor.dart';
import 'update_action_executor.dart';

class DownloadAndInstallPackageExecutor implements UpdateActionExecutor {
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
  bool supports(UpdateAction action) => action is DownloadAndInstallPackageAction;

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
}
