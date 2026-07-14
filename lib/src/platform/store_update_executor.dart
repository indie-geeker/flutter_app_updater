import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../actions/update_action.dart';
import '../channel/flutter_app_updater_platform_interface.dart';
import '../models/update_error_code.dart';
import 'update_action_executor.dart';

class StoreUpdateExecutor implements UpdateActionExecutor {
  final FlutterAppUpdaterPlatform platform;
  final TargetPlatform targetPlatform;

  StoreUpdateExecutor({
    FlutterAppUpdaterPlatform? platform,
    TargetPlatform? targetPlatform,
  })  : platform = platform ?? FlutterAppUpdaterPlatform.instance,
        targetPlatform = targetPlatform ?? defaultTargetPlatform;

  @override
  bool supports(UpdateAction action) {
    if (action is! OpenStoreAction) {
      return false;
    }
    return switch (targetPlatform) {
      TargetPlatform.android => action.store == StoreKind.googlePlay,
      TargetPlatform.iOS => action.store == StoreKind.appStore,
      TargetPlatform.macOS => action.store == StoreKind.macAppStore,
      _ => false,
    };
  }

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    if (action is! OpenStoreAction) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.noSupportedAction,
        message: 'StoreUpdateExecutor only supports store update actions.',
      );
    }
    if (!supports(action)) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.platformNotSupported,
        message: 'This store is not supported on the current platform.',
      );
    }

    try {
      return await _openStore(action);
    } on PlatformException catch (error) {
      return UpdateActionResult.failure(
        code: _mapPlatformCode(error.code),
        message: error.message ?? error.code,
      );
    } on MissingPluginException catch (error) {
      return UpdateActionResult.failure(
        code: UpdateErrorCode.platformNotSupported,
        message: error.message ?? 'Store update actions are not supported.',
      );
    }
  }

  Future<UpdateActionResult> _openStore(OpenStoreAction action) async {
    if (!action.storeUrl.hasScheme || !action.storeUrl.hasAuthority) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.manifestInvalid,
        message: 'storeUrl must be an absolute URL.',
      );
    }

    await platform.openStore(
      store: action.store.name,
      storeUrl: action.storeUrl.toString(),
    );
    return const UpdateActionResult.success();
  }

  UpdateErrorCode _mapPlatformCode(String code) {
    return switch (code) {
      'STORE_NOT_AVAILABLE' => UpdateErrorCode.storeNotAvailable,
      'PLATFORM_NOT_SUPPORTED' => UpdateErrorCode.platformNotSupported,
      _ => UpdateErrorCode.storeNotAvailable,
    };
  }
}
