import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_app_updater_platform_interface.dart';

/// An implementation of [FlutterAppUpdaterPlatform] that uses method channels.
class MethodChannelFlutterAppUpdater extends FlutterAppUpdaterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_app_updater');

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<void> installApp({required String path}) async {
    return await methodChannel.invokeMethod('installApp', path);
  }

  @override
  Future<String?> getAppVersionCode() async {
    return await methodChannel.invokeMethod("getAppVersionCode");
  }

  @override
  Future<String?> getAppVersionName() async {
    return await methodChannel.invokeMethod<String>("getAppVersionName");
  }

  @override
  Future<String?> getDownloadPath() async {
    return await methodChannel.invokeMethod<String>("getDownloadPath");
  }

  @override
  Future<void> openStore({
    required String store,
    required String storeUrl,
  }) async {
    await methodChannel.invokeMethod<void>('openStore', {
      'store': store,
      'storeUrl': storeUrl,
    });
  }

  @override
  Future<void> startPlayInAppUpdate({
    required String mode,
  }) async {
    await methodChannel.invokeMethod<void>('startPlayInAppUpdate', {
      'mode': mode,
    });
  }

  @override
  Future<void> openAndroidMarket({
    required String marketPackageName,
    required String marketUri,
    required String targetPackageName,
    String? fallbackUrl,
  }) async {
    await methodChannel.invokeMethod<void>('openAndroidMarket', {
      'marketPackageName': marketPackageName,
      'marketUri': marketUri,
      'targetPackageName': targetPackageName,
      if (fallbackUrl != null) 'fallbackUrl': fallbackUrl,
    });
  }

  @override
  Future<void> openInstaller({
    required String installerPath,
  }) async {
    await methodChannel.invokeMethod<void>('openInstaller', {
      'installerPath': installerPath,
    });
  }
}
