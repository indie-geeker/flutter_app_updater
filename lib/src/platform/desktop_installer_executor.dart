import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../actions/update_action.dart';
import '../channel/flutter_app_updater_platform_interface.dart';
import '../download/package_downloader.dart';
import '../models/update_error_code.dart';
import '../utils/safe_artifact_filename.dart';
import 'streaming_update_action_executor.dart';
import 'update_action_cancel_token.dart';
import 'update_action_executor.dart';
import 'update_action_event.dart';

class DesktopInstallerExecutor implements StreamingUpdateActionExecutor {
  final TargetPlatform platform;
  final FlutterAppUpdaterPlatform platformChannel;
  final PackageDownloader downloader;
  final Directory downloadDirectory;

  DesktopInstallerExecutor({
    required this.platform,
    FlutterAppUpdaterPlatform? platformChannel,
    PackageDownloadClient? client,
    PackageDownloader? downloader,
    Directory? downloadDirectory,
  })  : platformChannel = platformChannel ?? FlutterAppUpdaterPlatform.instance,
        downloader = downloader ?? PackageDownloader(client: client),
        downloadDirectory = downloadDirectory ?? Directory.systemTemp;

  @override
  bool supports(UpdateAction action) => action is OpenInstallerAction;

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    await for (final event in performStream(action)) {
      if (event case UpdateActionCompleted(:final result)) {
        return result;
      }
    }
    return const UpdateActionResult.failure(
      code: UpdateErrorCode.packageDownloadFailed,
      message: 'Installer action ended without a result.',
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
          message: 'Installer action failed: $error',
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
    if (action is! OpenInstallerAction) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.noSupportedAction,
        message: 'DesktopInstallerExecutor only supports installer actions.',
      );
    }
    if (!_supportsPlatform(platform) ||
        !_supportsInstallerType(platform, action.installerType)) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.platformNotSupported,
        message: 'Installer type is not supported on this platform.',
      );
    }
    if (!_isAllowedArtifactUrl(action.installerUrl)) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.manifestInvalid,
        message: 'installerUrl must use HTTPS outside localhost.',
      );
    }

    final downloadResult = await downloader.download(
      action: DownloadPackageAction(
        packageUrl: action.installerUrl,
        packageType: PackageType.apk,
        packageSizeBytes: action.installerSizeBytes,
        sha256: action.sha256,
      ),
      savePath: _installerPath(action),
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
    if (!downloadResult.isSuccess || downloadResult.file == null) {
      return UpdateActionResult.failure(
        code: downloadResult.code ?? UpdateErrorCode.packageDownloadFailed,
        message: downloadResult.message ?? 'Installer download failed.',
      );
    }
    if (cancelToken?.isCanceled ?? false) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.actionCanceled,
        message: 'Installer action canceled.',
      );
    }

    try {
      await platformChannel.openInstaller(
        installerPath: downloadResult.file!.path,
      );
      return UpdateActionResult.success(
        file: downloadResult.file,
        downloadedBytes: downloadResult.downloadedBytes,
        sha256: downloadResult.sha256,
      );
    } on MissingPluginException {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.platformNotSupported,
        message: 'Desktop installer support is not available on this platform.',
      );
    } on PlatformException catch (error) {
      return UpdateActionResult.failure(
        code: _mapPlatformCode(error.code),
        message: error.message ?? error.code,
      );
    }
  }

  bool _supportsPlatform(TargetPlatform platform) {
    return platform == TargetPlatform.windows ||
        platform == TargetPlatform.macOS;
  }

  bool _supportsInstallerType(
    TargetPlatform platform,
    InstallerType installerType,
  ) {
    return switch (platform) {
      TargetPlatform.windows => {
          InstallerType.msix,
          InstallerType.msi,
          InstallerType.exe,
        }.contains(installerType),
      TargetPlatform.macOS => {
          InstallerType.dmg,
          InstallerType.zip,
        }.contains(installerType),
      _ => false,
    };
  }

  String _installerPath(OpenInstallerAction action) {
    final extension = _extensionFor(action.installerType);
    final fileName = _safeInstallerFileName(action, extension);
    final separator = Platform.pathSeparator;
    final directory = downloadDirectory.path.endsWith(separator)
        ? downloadDirectory.path.substring(
            0,
            downloadDirectory.path.length - 1,
          )
        : downloadDirectory.path;
    return '$directory$separator$fileName';
  }

  String _safeInstallerFileName(
    OpenInstallerAction action,
    String extension,
  ) {
    final safeFileName = safeArtifactFilename(
      action.installerUrl,
      expectedExtension: extension,
    );
    if (safeFileName != null) {
      return safeFileName;
    }

    final normalizedSha256 = action.sha256?.toLowerCase().trim();
    final prefix = normalizedSha256 == null || normalizedSha256.isEmpty
        ? 'download'
        : normalizedSha256.length >= 12
            ? normalizedSha256.substring(0, 12)
            : normalizedSha256;
    return 'installer-$prefix.$extension';
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

  String _extensionFor(InstallerType installerType) {
    return switch (installerType) {
      InstallerType.msix => 'msix',
      InstallerType.msi => 'msi',
      InstallerType.exe => 'exe',
      InstallerType.dmg => 'dmg',
      InstallerType.zip => 'zip',
      InstallerType.appImage => 'AppImage',
      InstallerType.deb => 'deb',
      InstallerType.rpm => 'rpm',
    };
  }

  UpdateErrorCode _mapPlatformCode(String code) {
    return switch (code) {
      'INSTALLER_OPEN_FAILED' => UpdateErrorCode.installerOpenFailed,
      'PLATFORM_NOT_SUPPORTED' => UpdateErrorCode.platformNotSupported,
      _ => UpdateErrorCode.installerOpenFailed,
    };
  }
}
