import 'package:flutter/services.dart';

import '../actions/update_action.dart';
import '../channel/flutter_app_updater_platform_interface.dart';
import '../models/update_error_code.dart';
import 'update_action_executor.dart';

class StoreUpdateExecutor implements UpdateActionExecutor {
  final FlutterAppUpdaterPlatform platform;

  StoreUpdateExecutor({
    FlutterAppUpdaterPlatform? platform,
  }) : platform = platform ?? FlutterAppUpdaterPlatform.instance;

  @override
  bool supports(UpdateAction action) {
    return action is OpenStoreAction;
  }

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    if (!supports(action)) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.noSupportedAction,
        message: 'StoreUpdateExecutor only supports store update actions.',
      );
    }

    try {
      if (action is OpenStoreAction) {
        return await _openStore(action);
      }
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.noSupportedAction,
        message: 'Unsupported store action.',
      );
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
