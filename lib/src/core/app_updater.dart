import '../models/update_error_code.dart';
import 'update_selector.dart';
import 'update_source.dart';

class AppUpdater {
  final UpdateSource source;
  final UpdateSelector? selector;

  const AppUpdater({
    required this.source,
    this.selector,
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
      ManifestUpdateSource() => const UpdateCheckFailed(
          code: UpdateErrorCode.manifestFetchFailed,
          message: 'Remote manifest fetching is not implemented yet.',
        ),
    };
  }
}
