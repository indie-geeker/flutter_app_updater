import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../actions/update_action.dart';
import '../channel/flutter_app_updater_platform_interface.dart';
import '../models/update_error_code.dart';
import 'update_action_executor.dart';

/// Verifies and opens a trusted local Android APK for installation.
///
/// When size and SHA-256 metadata are supplied, they must be supplied together.
/// Native verification checks the current host package identity and compatible
/// signing lineage immediately before launching the installer.
class InstallPackageExecutor implements UpdateActionExecutor {
  /// Injectable platform boundary.
  final FlutterAppUpdaterPlatform platform;

  /// Runtime platform used for capability checks.
  final TargetPlatform targetPlatform;

  /// Creates an Android APK install executor.
  InstallPackageExecutor({
    FlutterAppUpdaterPlatform? platform,
    TargetPlatform? targetPlatform,
  })  : platform = platform ?? FlutterAppUpdaterPlatform.instance,
        targetPlatform = targetPlatform ?? defaultTargetPlatform;

  @override
  bool supports(UpdateAction action) =>
      targetPlatform == TargetPlatform.android &&
      action is InstallPackageAction &&
      action.packageType == PackageType.apk;

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    if (action is! InstallPackageAction) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.noSupportedAction,
        message: 'InstallPackageExecutor only supports package installs.',
      );
    }
    if (!supports(action)) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.platformNotSupported,
        message: 'Only Android APK packages can be installed locally.',
      );
    }

    final packagePath = action.packagePath.trim();
    if (packagePath.isEmpty) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.missingRequiredField,
        message: 'packagePath is required for package installs.',
      );
    }
    final packageSizeBytes = action.packageSizeBytes;
    final sha256 = action.sha256;
    if ((packageSizeBytes == null) != (sha256 == null) ||
        (packageSizeBytes != null && packageSizeBytes <= 0) ||
        (sha256 != null && !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256))) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.missingRequiredField,
        message: 'packageSizeBytes and a 64-character SHA-256 must be '
            'provided together.',
      );
    }

    try {
      await platform.installApp(
        path: packagePath,
        packageSizeBytes: packageSizeBytes,
        sha256: sha256,
      );
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
      'PACKAGE_FILE_NOT_FOUND' => UpdateErrorCode.packageFileNotFound,
      'PACKAGE_HASH_MISMATCH' => UpdateErrorCode.packageHashMismatch,
      'PACKAGE_SIGNATURE_INVALID' => UpdateErrorCode.packageSignatureInvalid,
      'PLATFORM_NOT_SUPPORTED' => UpdateErrorCode.platformNotSupported,
      'INVALID_ARGUMENT' => UpdateErrorCode.manifestInvalid,
      _ => UpdateErrorCode.packageInstallFailed,
    };
  }
}
