import 'package:flutter/services.dart';

import '../actions/update_action.dart';
import '../channel/flutter_app_updater_platform_interface.dart';
import '../models/update_error_code.dart';
import 'streaming_update_action_executor.dart';
import 'update_action_event.dart';
import 'update_action_executor.dart';

class InstallPackageExecutor
    implements UpdateActionExecutor, StreamingUpdateActionExecutor {
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

    return _performInstall(action);
  }

  @override
  Stream<UpdateActionEvent> performStream(UpdateAction action) async* {
    yield UpdateActionStarted(action);

    if (action is! InstallPackageAction) {
      yield const UpdateActionFailed(
        UpdateActionResult.failure(
          code: UpdateErrorCode.noSupportedAction,
          message: 'InstallPackageExecutor only supports package installs.',
        ),
      );
      return;
    }

    final packagePath = action.packagePath.trim();
    if (packagePath.isEmpty) {
      yield const UpdateActionFailed(
        UpdateActionResult.failure(
          code: UpdateErrorCode.missingRequiredField,
          message: 'packagePath is required for package installs.',
        ),
      );
      return;
    }

    if (action.packageType != PackageType.apk) {
      yield UpdateActionFailed(_notInstallablePackageType());
      return;
    }

    yield UpdateInstallStarted(packagePath: packagePath);

    final result = await _performInstall(action);
    if (result.isSuccess) {
      yield UpdateActionCompleted(result);
      return;
    }

    if (result.code == UpdateErrorCode.packageInstallPermissionRequired) {
      yield UpdateInstallPermissionRequired(packagePath: packagePath);
    }
    yield UpdateActionFailed(result);
  }

  Future<UpdateActionResult> _performInstall(
      InstallPackageAction action) async {
    final packagePath = action.packagePath.trim();
    if (packagePath.isEmpty) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.missingRequiredField,
        message: 'packagePath is required for package installs.',
      );
    }

    if (action.packageType != PackageType.apk) {
      return _notInstallablePackageType();
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

  UpdateActionResult _notInstallablePackageType() {
    return const UpdateActionResult.failure(
      code: UpdateErrorCode.packageTypeNotInstallable,
      message: 'Only APK files can be installed locally.',
    );
  }
}
