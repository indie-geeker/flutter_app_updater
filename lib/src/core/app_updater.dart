import '../actions/update_action.dart';
import '../models/update_error_code.dart';
import '../manifest/manifest_fetcher.dart';
import '../manifest/manifest_parser.dart';
import '../platform/android_market_executor.dart';
import '../platform/store_update_executor.dart';
import '../platform/update_action_executor.dart';
import 'update_selector.dart';
import 'update_source.dart';

class AppUpdater {
  final UpdateSource source;
  final UpdateSelector? selector;
  final ManifestFetcher manifestFetcher;
  final List<UpdateActionExecutor>? executors;

  const AppUpdater({
    required this.source,
    this.selector,
    this.manifestFetcher = const IoManifestFetcher(),
    this.executors,
  });

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

  List<UpdateActionExecutor> _defaultExecutors() {
    return [
      StoreUpdateExecutor(),
      AndroidMarketExecutor(),
    ];
  }
}
