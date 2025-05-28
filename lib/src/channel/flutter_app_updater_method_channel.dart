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
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
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
}
