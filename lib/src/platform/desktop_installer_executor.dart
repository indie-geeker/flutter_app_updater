import 'dart:io';

import 'package:flutter/services.dart';

import '../actions/update_action.dart';
import '../channel/flutter_app_updater_platform_interface.dart';
import '../download/package_downloader.dart';
import '../models/update_error_code.dart';
import 'update_action_executor.dart';

class DesktopInstallerExecutor implements UpdateActionExecutor {
  final TargetPlatform platform;
  final FlutterAppUpdaterPlatform platformChannel;
  final PackageDownloadClient client;
  final Directory downloadDirectory;

  DesktopInstallerExecutor({
    required this.platform,
    FlutterAppUpdaterPlatform? platformChannel,
    PackageDownloadClient? client,
    Directory? downloadDirectory,
  })  : platformChannel = platformChannel ?? FlutterAppUpdaterPlatform.instance,
        client = client ?? IoPackageDownloadClient(),
        downloadDirectory = downloadDirectory ?? Directory.systemTemp;

  @override
  bool supports(UpdateAction action) => action is OpenInstallerAction;

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    if (action is! OpenInstallerAction) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.noSupportedAction,
        message: 'DesktopInstallerExecutor only supports installer actions.',
      );
    }

    if (action.sha256.trim().isEmpty) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.missingRequiredField,
        message: 'sha256 is required before opening installers.',
      );
    }

    if (!_supportsPlatform(platform) ||
        !_supportsInstallerType(platform, action.installerType)) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.platformNotSupported,
        message: 'Installer type is not supported on this platform.',
      );
    }

    final downloadResult = await PackageDownloader(client: client).download(
      action: DownloadPackageAction(
        packageUrl: action.installerUrl,
        packageType: PackageType.apk,
        packageSizeBytes: action.installerSizeBytes,
        sha256: action.sha256,
        signature: action.signature,
      ),
      savePath: _installerPath(action),
    );

    if (!downloadResult.isSuccess || downloadResult.file == null) {
      return UpdateActionResult.failure(
        code: downloadResult.code ?? UpdateErrorCode.packageDownloadFailed,
        message: downloadResult.message ?? 'Installer download failed.',
      );
    }

    try {
      await platformChannel.openInstaller(
        installerPath: downloadResult.file!.path,
      );
      return const UpdateActionResult.success();
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
          InstallerType.exe
        }.contains(installerType),
      TargetPlatform.macOS =>
        {InstallerType.dmg, InstallerType.zip}.contains(installerType),
      _ => false,
    };
  }

  String _installerPath(OpenInstallerAction action) {
    final extension = _extensionFor(action.installerType);
    final fileName = action.installerUrl.pathSegments.isNotEmpty
        ? action.installerUrl.pathSegments.last
        : 'installer.$extension';
    final normalizedFileName =
        fileName.contains('.') ? fileName : '$fileName.$extension';
    return '${downloadDirectory.path}/$normalizedFileName';
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
