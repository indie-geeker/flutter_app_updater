import 'dart:async';
import 'dart:io';

import '../actions/update_action.dart';
import '../download/package_downloader.dart';
import '../models/update_error_code.dart';
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
    return _perform(action);
  }

  @override
  Stream<UpdateActionEvent> performStream(
    UpdateAction action, {
    UpdateActionCancelToken? cancelToken,
  }) {
    final controller = StreamController<UpdateActionEvent>();
    () async {
      controller.add(UpdateActionStarted(action));
      final result = await _perform(
        action,
        cancelToken: cancelToken,
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

    if (!_isAllowedSelfHostedArtifactUrl(action.packageUrl)) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.manifestInvalid,
        message: 'packageUrl must use HTTPS outside localhost.',
      );
    }

    final packageSizeBytes = action.packageSizeBytes;
    if (packageSizeBytes != null && packageSizeBytes <= 0) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.manifestInvalid,
        message: 'packageSizeBytes must be a positive integer.',
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
    final lastSegment = action.packageUrl.pathSegments.isEmpty
        ? ''
        : action.packageUrl.pathSegments.last;
    if (_isSafeFilename(lastSegment)) {
      return lastSegment;
    }

    final sha256 = action.sha256?.trim().toLowerCase();
    final prefix = sha256 == null || sha256.isEmpty
        ? 'download'
        : sha256.length >= 12
            ? sha256.substring(0, 12)
            : sha256;
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

  bool _isAllowedSelfHostedArtifactUrl(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') {
      return true;
    }
    if (scheme != 'http') {
      return false;
    }

    final host = uri.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }
}
