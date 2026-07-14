import 'manifest_schema.dart';

export 'manifest_schema.dart' show ManifestParseException;

/// Facade for validating decoded manifest objects before model construction.
class ManifestValidator {
  /// Schema implementation used by this validator.
  final ManifestSchema schema;

  /// Creates a validator with an injectable schema.
  const ManifestValidator({
    this.schema = const ManifestSchema(),
  });

  /// Validates [manifest] or throws [ManifestParseException].
  void validate(Map<String, Object?> manifest) {
    schema.validate(manifest);
  }
}
