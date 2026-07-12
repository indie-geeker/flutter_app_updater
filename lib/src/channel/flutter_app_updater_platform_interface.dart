import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../actions/update_action.dart';
import '../background/background_download_task.dart';
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

  Future<String?> getAppVersionCode() {
    throw UnimplementedError('appVersion() has not been implemented.');
  }

  Future<String?> getAppVersionName() {
    throw UnimplementedError('appVersion() has not been implemented.');
  }

  Future<void> installApp({required String path}) {
    throw UnimplementedError('installApp() has not been implemented.');
  }

  Future<String?> getDownloadPath() {
    throw UnimplementedError('getDownloadPath() has not been implemented.');
  }

  Future<void> openStore({
    required String store,
    required String storeUrl,
  }) {
    throw UnimplementedError('openStore() has not been implemented.');
  }

  Future<void> startPlayInAppUpdate({
    required String mode,
  }) {
    throw UnimplementedError(
      'startPlayInAppUpdate() has not been implemented.',
    );
  }

  Future<void> openAndroidMarket({
    required String marketPackageName,
    required String marketUri,
    required String targetPackageName,
    String? fallbackUrl,
  }) {
    throw UnimplementedError('openAndroidMarket() has not been implemented.');
  }

  Future<void> openInstaller({
    required String installerPath,
  }) {
    throw UnimplementedError('openInstaller() has not been implemented.');
  }

  Future<BackgroundDownloadTask> startBackgroundDownload({
    required Uri packageUrl,
    required PackageType packageType,
    required int packageSizeBytes,
    required String sha256,
  }) {
    throw UnimplementedError(
      'startBackgroundDownload() has not been implemented.',
    );
  }

  Future<BackgroundDownloadTask> getBackgroundDownload(String taskId) {
    throw UnimplementedError(
      'getBackgroundDownload() has not been implemented.',
    );
  }

  Future<List<BackgroundDownloadTask>> listBackgroundDownloads() {
    throw UnimplementedError(
      'listBackgroundDownloads() has not been implemented.',
    );
  }

  Future<BackgroundDownloadTask> resumeBackgroundDownload(String taskId) {
    throw UnimplementedError(
      'resumeBackgroundDownload() has not been implemented.',
    );
  }

  Future<BackgroundDownloadTask> cancelBackgroundDownload(String taskId) {
    throw UnimplementedError(
      'cancelBackgroundDownload() has not been implemented.',
    );
  }

  Future<void> removeBackgroundDownload(String taskId) {
    throw UnimplementedError(
      'removeBackgroundDownload() has not been implemented.',
    );
  }

  Future<String> prepareBackgroundDownloadInstall(String taskId) {
    throw UnimplementedError(
      'prepareBackgroundDownloadInstall() has not been implemented.',
    );
  }

  Stream<BackgroundDownloadTask> watchBackgroundDownloads() {
    throw UnimplementedError(
      'watchBackgroundDownloads() has not been implemented.',
    );
  }
}
