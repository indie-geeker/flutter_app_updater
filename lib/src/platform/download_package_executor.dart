import 'dart:async';
import 'dart:io';

import '../actions/update_action.dart';
import '../download/package_downloader.dart';
import '../models/update_error_code.dart';
import 'streaming_update_action_executor.dart';
import 'update_action_cancel_token.dart';
import 'update_action_event.dart';
import 'update_action_executor.dart';

class DownloadPackageExecutor
    implements UpdateActionExecutor, StreamingUpdateActionExecutor {
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

    return _performDownload(action);
  }

  @override
  Stream<UpdateActionEvent> performStream(UpdateAction action) {
    var isActive = true;
    final cancelToken = UpdateActionCancelToken();
    late final StreamController<UpdateActionEvent> controller;
    controller = StreamController<UpdateActionEvent>(
      onListen: () {
        unawaited(
          _performDownloadStream(
            action: action,
            controller: controller,
            cancelToken: cancelToken,
            isActive: () => isActive,
          ),
        );
      },
      onCancel: () {
        isActive = false;
        cancelToken.cancel();
      },
    );
    return controller.stream;
  }

  Future<void> _performDownloadStream({
    required UpdateAction action,
    required StreamController<UpdateActionEvent> controller,
    required UpdateActionCancelToken cancelToken,
    required bool Function() isActive,
  }) async {
    void add(UpdateActionEvent event) {
      if (isActive() && !controller.isClosed) {
        controller.add(event);
      }
    }

    try {
      add(UpdateActionStarted(action));

      if (action is! DownloadPackageAction) {
        add(
          const UpdateActionFailed(
            UpdateActionResult.failure(
              code: UpdateErrorCode.noSupportedAction,
              message: 'DownloadPackageExecutor only supports '
                  'package downloads.',
            ),
          ),
        );
        return;
      }

      final result = await _performDownload(
        action,
        onProgress: (progress) {
          add(
            UpdateDownloadProgress(
              receivedBytes: progress.receivedBytes,
              totalBytes: progress.totalBytes,
            ),
          );
        },
        cancelToken: cancelToken,
      );

      if (result.isSuccess) {
        add(UpdateDownloadCompleted(result));
        add(UpdateActionCompleted(result));
      } else {
        add(UpdateActionFailed(result));
      }
    } finally {
      if (!controller.isClosed) {
        await controller.close();
      }
    }
  }

  Future<UpdateActionResult> _performDownload(
    DownloadPackageAction action, {
    PackageDownloadProgressCallback? onProgress,
    UpdateActionCancelToken? cancelToken,
  }) async {
    if (downloadDirectory.trim().isEmpty) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.missingRequiredField,
        message: 'downloadDirectory is required for package downloads.',
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
}
