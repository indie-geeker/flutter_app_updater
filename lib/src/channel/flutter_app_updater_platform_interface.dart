import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_app_updater_method_channel.dart';


abstract class FlutterAppUpdaterPlatform extends PlatformInterface {
  /// Constructs a FlutterAppUpdaterPlatform.
  FlutterAppUpdaterPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterAppUpdaterPlatform _instance = MethodChannelFlutterAppUpdater();

  /// The default instance of [FlutterAppUpdaterPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterAppUpdater].
  static FlutterAppUpdaterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterAppUpdaterPlatform] when
  /// they register themselves.
  static set instance(FlutterAppUpdaterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<String?> getAppVersion() {
    throw UnimplementedError('appVersion() has not been implemented.');
  }

  Future<void> installApp({required String path}) {
    throw UnimplementedError('installApp() has not been implemented.');
  }

}
