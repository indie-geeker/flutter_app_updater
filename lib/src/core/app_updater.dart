import '../models/update_error_code.dart';
import '../manifest/manifest_fetcher.dart';
import '../manifest/manifest_parser.dart';
import 'update_selector.dart';
import 'update_source.dart';

class AppUpdater {
  final UpdateSource source;
  final UpdateSelector? selector;
  final ManifestFetcher manifestFetcher;

  const AppUpdater({
    required this.source,
    this.selector,
    this.manifestFetcher = const IoManifestFetcher(),
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
}
