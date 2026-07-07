import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../actions/update_action.dart';
import '../channel/flutter_app_updater_platform_interface.dart';
import '../manifest/manifest_fetcher.dart';
import '../manifest/manifest_parser.dart';
import '../platform/android_market_executor.dart';
import '../models/update_candidate.dart';
import '../models/update_error_code.dart';
import '../platform/desktop_installer_executor.dart';
import '../platform/download_and_install_package_executor.dart';
import '../platform/download_package_executor.dart';
import '../platform/install_package_executor.dart';
import '../platform/streaming_update_action_executor.dart';
import '../platform/store_update_executor.dart';
import '../platform/update_action_cancel_token.dart';
import '../platform/update_action_executor.dart';
import '../platform/update_action_event.dart';
import 'update_selector.dart';
import 'update_source.dart';

class AppUpdater {
  final UpdateSource source;
  final UpdateSelector? selector;
  final ManifestFetcher manifestFetcher;
  final List<UpdateActionExecutor>? executors;
  final String? downloadDirectory;
  final TargetPlatform? platform;
  final String? expectedAppId;

  const AppUpdater({
    required this.source,
    this.selector,
    this.manifestFetcher = const IoManifestFetcher(),
    this.executors,
    this.downloadDirectory,
    this.platform,
    this.expectedAppId,
  });

  factory AppUpdater.manifest({
    required Uri manifestUrl,
    Map<String, String>? headers,
    required String installedVersion,
    String? installedBuildNumber,
    required TargetPlatform platform,
    String? architecture,
    required String channel,
    String? downloadDirectory,
    ManifestFetcher manifestFetcher = const IoManifestFetcher(),
    List<UpdateActionExecutor>? executors,
    String? expectedAppId,
  }) {
    return AppUpdater(
      source: UpdateSource.manifest(
        manifestUrl: manifestUrl,
        headers: headers,
      ),
      selector: UpdateSelector(
        installedVersion: installedVersion,
        installedBuildNumber: installedBuildNumber,
        platform: platform,
        architecture: architecture,
        channel: channel,
      ),
      manifestFetcher: manifestFetcher,
      executors: executors,
      downloadDirectory: downloadDirectory,
      platform: platform,
      expectedAppId: expectedAppId,
    );
  }

  Future<UpdateCheckResult> check({
    UpdateSelector? selector,
  }) async {
    final effectiveSelector = selector ?? this.selector;
    if (effectiveSelector == null) {
      return const UpdateCheckFailed(
        code: UpdateErrorCode.manifestInvalid,
        message: 'UpdateSelector is required before checking updates.',
      );
    }

    return switch (source) {
      StaticManifestUpdateSource(:final manifest) =>
        _selectManifest(manifest, effectiveSelector),
      ManifestUpdateSource manifestSource =>
        _checkRemoteManifest(manifestSource, effectiveSelector),
    };
  }

  Future<UpdateFlowResult> checkAndPrepare({
    UpdateSelector? selector,
  }) async {
    final result = await check(selector: selector);
    return switch (result) {
      UpdateAvailable(
        :final candidate,
        :final recommendedAction,
        :final isRequired,
      ) =>
        PreparedUpdateAvailable(
          candidate: candidate,
          recommendedAction: recommendedAction,
          actions: candidate.actions,
          isRequired: isRequired,
        ),
      UpdateNotAvailable() => const PreparedUpdateNotAvailable(),
      UpdateCheckFailed(:final code, :final message) =>
        PreparedUpdateCheckFailed(code: code, message: message),
    };
  }

  Future<UpdateCheckResult> _checkRemoteManifest(
    ManifestUpdateSource manifestSource,
    UpdateSelector effectiveSelector,
  ) async {
    try {
      final json = await manifestFetcher.fetch(manifestSource);
      final manifest = const ManifestParser().parse(json);
      return _selectManifest(manifest, effectiveSelector);
    } on FormatException catch (error) {
      return UpdateCheckFailed(
        code: UpdateErrorCode.manifestInvalid,
        message: error.message,
      );
    } on ManifestParseException catch (error) {
      return UpdateCheckFailed(
        code: error.code,
        message: error.message,
      );
    } on ManifestFetchException catch (error) {
      return UpdateCheckFailed(
        code: UpdateErrorCode.manifestFetchFailed,
        message: error.message,
      );
    } catch (error) {
      return UpdateCheckFailed(
        code: UpdateErrorCode.manifestFetchFailed,
        message: 'Failed to fetch update manifest: $error',
      );
    }
  }

  UpdateCheckResult _selectManifest(
    UpdateManifest manifest,
    UpdateSelector effectiveSelector,
  ) {
    final expected = expectedAppId?.trim();
    if (expected != null && expected.isNotEmpty && manifest.appId != expected) {
      return UpdateCheckFailed(
        code: UpdateErrorCode.manifestInvalid,
        message:
            'Manifest appId ${manifest.appId} does not match expected appId $expected.',
      );
    }

    return effectiveSelector.select(manifest.releases);
  }

  Future<UpdateActionResult> perform(UpdateAction action) async {
    for (final executor in executors ?? _defaultExecutors()) {
      if (executor.supports(action)) {
        return executor.perform(action);
      }
    }

    return const UpdateActionResult.failure(
      code: UpdateErrorCode.noSupportedAction,
      message: 'No executor supports this update action.',
    );
  }

  Stream<UpdateActionEvent> performStream(
    UpdateAction action, {
    UpdateActionCancelToken? cancelToken,
  }) async* {
    for (final executor in executors ?? _defaultExecutors()) {
      if (!executor.supports(action)) {
        continue;
      }

      if (executor is StreamingUpdateActionExecutor) {
        yield* executor.performStream(action, cancelToken: cancelToken);
        return;
      }

      yield UpdateActionStarted(action);
      final result = await executor.perform(action);
      yield UpdateActionCompleted(result);
      return;
    }

    yield UpdateActionStarted(action);
    yield const UpdateActionCompleted(
      UpdateActionResult.failure(
        code: UpdateErrorCode.noSupportedAction,
        message: 'No executor supports this update action.',
      ),
    );
  }

  Future<UpdateActionResult> performRecommended(
    PreparedUpdateAvailable update,
  ) {
    return perform(update.recommendedAction);
  }

  Future<UpdateActionResult> openInstallPermissionSettings() async {
    try {
      await FlutterAppUpdaterPlatform.instance.openInstallPermissionSettings();
      return const UpdateActionResult.success();
    } on PlatformException catch (error) {
      return UpdateActionResult.failure(
        code: _mapInstallPermissionSettingsCode(error.code),
        message: error.message ?? error.code,
      );
    } on MissingPluginException catch (error) {
      return UpdateActionResult.failure(
        code: UpdateErrorCode.platformNotSupported,
        message: error.message ??
            'Install permission settings are not supported on this platform.',
      );
    } on UnimplementedError catch (error) {
      return UpdateActionResult.failure(
        code: UpdateErrorCode.platformNotSupported,
        message: error.message ??
            'Install permission settings are not supported on this platform.',
      );
    }
  }

  List<UpdateActionExecutor> _defaultExecutors() {
    final effectiveDownloadDirectory =
        downloadDirectory ?? Directory.systemTemp.path;
    final effectivePlatform =
        platform ?? selector?.platform ?? defaultTargetPlatform;
    return [
      StoreUpdateExecutor(),
      AndroidMarketExecutor(),
      DownloadPackageExecutor(
        downloadDirectory: effectiveDownloadDirectory,
      ),
      InstallPackageExecutor(),
      DownloadAndInstallPackageExecutor(
        downloadDirectory: effectiveDownloadDirectory,
      ),
      DesktopInstallerExecutor(
        platform: effectivePlatform,
        downloadDirectory: Directory(effectiveDownloadDirectory),
      ),
    ];
  }

  UpdateErrorCode _mapInstallPermissionSettingsCode(String code) {
    return switch (code) {
      'PLATFORM_NOT_SUPPORTED' => UpdateErrorCode.platformNotSupported,
      _ => UpdateErrorCode.packageInstallFailed,
    };
  }
}

sealed class UpdateFlowResult {
  const UpdateFlowResult();
}

class PreparedUpdateAvailable extends UpdateFlowResult {
  final UpdateCandidate candidate;
  final UpdateAction recommendedAction;
  final List<UpdateAction> actions;
  final bool isRequired;

  const PreparedUpdateAvailable({
    required this.candidate,
    required this.recommendedAction,
    required this.actions,
    required this.isRequired,
  });
}

class PreparedUpdateNotAvailable extends UpdateFlowResult {
  const PreparedUpdateNotAvailable();
}

class PreparedUpdateCheckFailed extends UpdateFlowResult {
  final UpdateErrorCode code;
  final String message;

  const PreparedUpdateCheckFailed({
    required this.code,
    required this.message,
  });
}
