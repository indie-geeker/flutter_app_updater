import 'package:flutter/services.dart';

import '../actions/update_action.dart';
import '../channel/flutter_app_updater_platform_interface.dart';
import '../models/update_error_code.dart';
import 'update_action_executor.dart';

class InstallPackageExecutor implements UpdateActionExecutor {
  final FlutterAppUpdaterPlatform platform;

  InstallPackageExecutor({
    FlutterAppUpdaterPlatform? platform,
  }) : platform = platform ?? FlutterAppUpdaterPlatform.instance;

  @override
  bool supports(UpdateAction action) => action is InstallPackageAction;

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    if (action is! InstallPackageAction) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.noSupportedAction,
        message: 'InstallPackageExecutor only supports package installs.',
      );
    }

    final packagePath = action.packagePath.trim();
    if (packagePath.isEmpty) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.missingRequiredField,
        message: 'packagePath is required for package installs.',
      );
    }

    try {
      await platform.installApp(path: packagePath);
      return const UpdateActionResult.success();
    } on PlatformException catch (error) {
      return UpdateActionResult.failure(
        code: _mapPlatformCode(error.code),
        message: error.message ?? error.code,
      );
    } on MissingPluginException catch (error) {
      return UpdateActionResult.failure(
        code: UpdateErrorCode.platformNotSupported,
        message: error.message ?? 'Package installs are not supported.',
      );
    }
  }

  UpdateErrorCode _mapPlatformCode(String code) {
    return switch (code) {
      'INSTALL_PERMISSION_REQUIRED' =>
        UpdateErrorCode.packageInstallPermissionRequired,
      'FILE_NOT_FOUND' => UpdateErrorCode.packageFileNotFound,
      'PLATFORM_NOT_SUPPORTED' => UpdateErrorCode.platformNotSupported,
      'INVALID_ARGUMENT' => UpdateErrorCode.manifestInvalid,
      _ => UpdateErrorCode.packageInstallFailed,
    };
  }
}
