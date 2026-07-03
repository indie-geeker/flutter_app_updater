import 'dart:io';

import '../actions/update_action.dart';
import '../download/package_downloader.dart';
import '../models/update_error_code.dart';
import 'update_action_executor.dart';

class DownloadPackageExecutor implements UpdateActionExecutor {
  final PackageDownloader downloader;
  final String downloadDirectory;

  DownloadPackageExecutor({
    required this.downloadDirectory,
    PackageDownloader? downloader,
  }) : downloader = downloader ?? PackageDownloader();

  @override
  bool supports(UpdateAction action) => action is DownloadPackageAction;

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    if (action is! DownloadPackageAction) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.noSupportedAction,
        message: 'DownloadPackageExecutor only supports package downloads.',
      );
    }

    if (downloadDirectory.trim().isEmpty) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.missingRequiredField,
        message: 'downloadDirectory is required for package downloads.',
      );
    }

    final result = await downloader.download(
      action: action,
      savePath: _savePath(action),
    );

    if (!result.isSuccess) {
      return UpdateActionResult.failure(
        code: result.code ?? UpdateErrorCode.packageDownloadFailed,
        message: result.message ?? 'Package download failed.',
      );
    }

    return UpdateActionResult.success(
      file: result.file,
      downloadedBytes: result.downloadedBytes,
      sha256: result.sha256,
    );
  }

  String _savePath(DownloadPackageAction action) {
    final separator = Platform.pathSeparator;
    final directory = downloadDirectory.endsWith(separator)
        ? downloadDirectory.substring(0, downloadDirectory.length - 1)
        : downloadDirectory;
    return '$directory$separator${_packageFilename(action)}';
  }

  String _packageFilename(DownloadPackageAction action) {
    final lastSegment = action.packageUrl.pathSegments.isEmpty
        ? ''
        : action.packageUrl.pathSegments.last;
    if (_isSafeFilename(lastSegment)) {
      return lastSegment;
    }

    final prefix = action.sha256.length >= 12
        ? action.sha256.substring(0, 12)
        : action.sha256;
    return 'package-$prefix.${action.packageType.name}';
  }

  bool _isSafeFilename(String value) {
    if (value.isEmpty || value == '.' || value == '..') {
      return false;
    }
    return !value.contains('/') &&
        !value.contains(r'\') &&
        !value.contains(RegExp(r'[\x00-\x1F]'));
  }
}
