import 'manifest_schema.dart';

export 'manifest_schema.dart' show ManifestParseException;

class ManifestValidator {
  final ManifestSchema schema;

  const ManifestValidator({
    this.schema = const ManifestSchema(),
  });

  void validate(Map<String, Object?> manifest) {
    schema.validate(manifest);
  }
}
