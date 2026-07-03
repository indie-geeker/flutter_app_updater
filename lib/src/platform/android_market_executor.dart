import 'package:flutter/services.dart';

import '../actions/update_action.dart';
import '../channel/flutter_app_updater_platform_interface.dart';
import '../models/update_error_code.dart';
import 'android_market_registry.dart';
import 'update_action_executor.dart';

class AndroidMarketExecutor implements UpdateActionExecutor {
  final FlutterAppUpdaterPlatform platform;

  AndroidMarketExecutor({
    FlutterAppUpdaterPlatform? platform,
  }) : platform = platform ?? FlutterAppUpdaterPlatform.instance;

  @override
  bool supports(UpdateAction action) => action is OpenAndroidMarketAction;

  @override
  Future<UpdateActionResult> perform(UpdateAction action) async {
    if (action is! OpenAndroidMarketAction) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.noSupportedAction,
        message: 'AndroidMarketExecutor only supports Android market actions.',
      );
    }

    final targetPackageName = action.targetPackageName.trim();
    if (targetPackageName.isEmpty) {
      return const UpdateActionResult.failure(
        code: UpdateErrorCode.missingRequiredField,
        message: 'targetPackageName is required for Android market actions.',
      );
    }

    final descriptor = AndroidMarketRegistry.requireDescriptor(action.market);
    final fallbackUrl = AndroidMarketRegistry.fallbackUrlFor(action);

    try {
      await platform.openAndroidMarket(
        marketPackageName: descriptor.marketPackageName,
        marketUri: descriptor.marketUriFor(targetPackageName).toString(),
        targetPackageName: targetPackageName,
        fallbackUrl: fallbackUrl?.toString(),
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
        message: error.message ?? 'Android market actions are not supported.',
      );
    }
  }

  UpdateErrorCode _mapPlatformCode(String code) {
    return switch (code) {
      'MARKET_NOT_AVAILABLE' => UpdateErrorCode.marketNotAvailable,
      'PLATFORM_NOT_SUPPORTED' => UpdateErrorCode.platformNotSupported,
      'INVALID_ARGUMENT' => UpdateErrorCode.manifestInvalid,
      _ => UpdateErrorCode.marketNotAvailable,
    };
  }
}
