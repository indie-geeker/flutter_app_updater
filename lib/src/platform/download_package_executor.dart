import 'dart:async';
import 'dart:io';

import '../actions/update_action.dart';
import '../download/package_downloader.dart';
import '../models/update_error_code.dart';
import '../utils/safe_artifact_filename.dart';
import 'streaming_update_action_executor.dart';
import 'update_action_cancel_token.dart';
import 'update_action_executor.dart';
import 'update_action_event.dart';

class DownloadPackageExecutor implements StreamingUpdateActionExecutor {
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
    await for (final event in performStream(action)) {
      if (event case UpdateActionCompleted(:final result)) {
        return result;
      }
    }
    return const UpdateActionResult.failure(
      code: UpdateErrorCode.packageDownloadFailed,
      message: 'Package download ended without a result.',
    );
  }

  @override
  Stream<UpdateActionEvent> performStream(
    UpdateAction action, {
    UpdateActionCancelToken? cancelToken,
  }) {
    final effectiveCancelToken = cancelToken ?? UpdateActionCancelToken();
    final controller = StreamController<UpdateActionEvent>();
    var operationActive = true;
    controller.onCancel = () {
      if (operationActive) {
        effectiveCancelToken.cancel();
      }
    };
    () async {
      controller.add(UpdateActionStarted(action));
      UpdateActionResult result;
      try {
        result = await _perform(
          action,
          cancelToken: effectiveCancelToken,
          onProgress: (progress) {
            controller.add(
              UpdateActionProgress(
                action: action,
                downloadedBytes: progress.downloadedBytes,
                totalBytes: progress.totalBytes,
              ),
            );
          },
        );
      } catch (error) {
        result = UpdateActionResult.failure(
          code: UpdateErrorCode.packageDownloadFailed,
          message: 'Package download failed: $error',
        );
      }
      operationActive = false;
      controller.add(UpdateActionCompleted(result));
      await controller.close();
    }();
    return controller.stream;
  }

  Future<UpdateActionResult> _perform(
    UpdateAction action, {
    void Function(PackageDownloadProgress progress)? onProgress,
    UpdateActionCancelToken? cancelToken,
  }) async {
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
    if (!_isAllowedArtifactUrl(action.packageUrl)) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.manifestInvalid,
        message: 'packageUrl must use HTTPS outside localhost.',
      );
    }

    final result = await downloader.download(
      action: action,
      savePath: _savePath(action),
      onProgress: onProgress,
      cancelToken: cancelToken,
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
    final safeFileName = safeArtifactFilename(
      action.packageUrl,
      expectedExtension: action.packageType.name,
    );
    if (safeFileName != null) {
      return safeFileName;
    }

    final sha256 = action.sha256?.trim().toLowerCase();
    final prefix = sha256 == null || sha256.isEmpty
        ? 'download'
        : sha256.length >= 12
            ? sha256.substring(0, 12)
            : sha256;
    return 'package-$prefix.${action.packageType.name}';
  }

  bool _isAllowedArtifactUrl(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') {
      return uri.hasAuthority;
    }
    if (scheme != 'http' || !uri.hasAuthority) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }
}
