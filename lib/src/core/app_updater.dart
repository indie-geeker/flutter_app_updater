import 'dart:io';

import 'package:flutter/foundation.dart';

import '../actions/update_action.dart';
import '../manifest/manifest_fetcher.dart';
import '../manifest/manifest_parser.dart';
import '../platform/android_market_executor.dart';
import '../models/update_candidate.dart';
import '../models/update_error_code.dart';
import '../platform/desktop_installer_executor.dart';
import '../platform/download_and_install_package_executor.dart';
import '../platform/download_package_executor.dart';
import '../platform/install_package_executor.dart';
import '../platform/store_update_executor.dart';
import '../platform/update_action_executor.dart';
import 'update_selector.dart';
import 'update_source.dart';

class AppUpdater {
  final UpdateSource source;
  final UpdateSelector? selector;
  final ManifestFetcher manifestFetcher;
  final List<UpdateActionExecutor>? executors;
  final String? downloadDirectory;
  final TargetPlatform? platform;

  const AppUpdater({
    required this.source,
    this.selector,
    this.manifestFetcher = const IoManifestFetcher(),
    this.executors,
    this.downloadDirectory,
    this.platform,
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
        effectiveSelector.select(manifest.releases),
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
      return effectiveSelector.select(manifest.releases);
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

  Future<UpdateActionResult> performRecommended(
    PreparedUpdateAvailable update,
  ) {
    return perform(update.recommendedAction);
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
