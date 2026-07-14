import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../actions/update_action.dart';
import '../background/background_download_task.dart';
import 'flutter_app_updater_method_channel.dart';

/// Native boundary used by action executors and Android durable downloads.
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

  /// Returns the operating-system version reported by the plugin.
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  /// Returns the installed application build number.
  Future<String?> getAppVersionCode() {
    throw UnimplementedError('appVersion() has not been implemented.');
  }

  /// Returns the installed application version name.
  Future<String?> getAppVersionName() {
    throw UnimplementedError('appVersion() has not been implemented.');
  }

  /// Revalidates and hands a local APK to the Android installer.
  ///
  /// [packageSizeBytes] and [sha256] are paired integrity metadata.
  Future<void> installApp({
    required String path,
    int? packageSizeBytes,
    String? sha256,
  }) {
    throw UnimplementedError('installApp() has not been implemented.');
  }

  /// Returns the platform's preferred download directory.
  Future<String?> getDownloadPath() {
    throw UnimplementedError('getDownloadPath() has not been implemented.');
  }

  /// Opens a validated official-store URL.
  Future<void> openStore({
    required String store,
    required String storeUrl,
  }) {
    throw UnimplementedError('openStore() has not been implemented.');
  }

  /// Opens an Android market app, falling back to a validated HTTPS URL.
  Future<void> openAndroidMarket({
    required String marketPackageName,
    required String marketUri,
    required String targetPackageName,
    String? fallbackUrl,
  }) {
    throw UnimplementedError('openAndroidMarket() has not been implemented.');
  }

  /// Opens a verified desktop installer at [installerPath].
  Future<void> openInstaller({
    required String installerPath,
  }) {
    throw UnimplementedError('openInstaller() has not been implemented.');
  }

  /// Creates a durable Android download with exact integrity metadata.
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

  /// Returns the latest snapshot for [taskId].
  Future<BackgroundDownloadTask> getBackgroundDownload(String taskId) {
    throw UnimplementedError(
      'getBackgroundDownload() has not been implemented.',
    );
  }

  /// Lists all retained durable task snapshots.
  Future<List<BackgroundDownloadTask>> listBackgroundDownloads() {
    throw UnimplementedError(
      'listBackgroundDownloads() has not been implemented.',
    );
  }

  /// Requests that [taskId] resume.
  Future<BackgroundDownloadTask> resumeBackgroundDownload(String taskId) {
    throw UnimplementedError(
      'resumeBackgroundDownload() has not been implemented.',
    );
  }

  /// Requests cancellation of [taskId].
  Future<BackgroundDownloadTask> cancelBackgroundDownload(String taskId) {
    throw UnimplementedError(
      'cancelBackgroundDownload() has not been implemented.',
    );
  }

  /// Removes persisted state for [taskId].
  Future<void> removeBackgroundDownload(String taskId) {
    throw UnimplementedError(
      'removeBackgroundDownload() has not been implemented.',
    );
  }

  /// Revalidates a completed task and returns its installable APK path.
  Future<String> prepareBackgroundDownloadInstall(String taskId) {
    throw UnimplementedError(
      'prepareBackgroundDownloadInstall() has not been implemented.',
    );
  }

  /// Streams native snapshots for all durable tasks.
  Stream<BackgroundDownloadTask> watchBackgroundDownloads() {
    throw UnimplementedError(
      'watchBackgroundDownloads() has not been implemented.',
    );
  }
}
