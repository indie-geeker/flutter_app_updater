import '../models/update_error_code.dart';

class ManifestParseException implements Exception {
  final UpdateErrorCode code;
  final String message;

  const ManifestParseException({
    required this.code,
    required this.message,
  });

  @override
  String toString() => '${code.value}: $message';
}

class ManifestValidator {
  static const _legacyFields = {
    'downloadUrl',
    'md5',
    'artifactUri',
  };

  const ManifestValidator();

  void validate(Map<String, Object?> manifest) {
    _rejectLegacyFields(manifest);

    final schemaVersion = manifest['schemaVersion'];
    if (schemaVersion == null) {
      throw const ManifestParseException(
        code: UpdateErrorCode.missingRequiredField,
        message: 'schemaVersion is required.',
      );
    }
    if (schemaVersion != 3) {
      throw ManifestParseException(
        code: UpdateErrorCode.unsupportedSchemaVersion,
        message: 'Unsupported schemaVersion: $schemaVersion.',
      );
    }

    _requireString(manifest, 'appId');
    _requireString(manifest, 'channel');

    final releases = manifest['releases'];
    if (releases is! List) {
      throw const ManifestParseException(
        code: UpdateErrorCode.missingRequiredField,
        message: 'releases is required.',
      );
    }
  }

  static void _rejectLegacyFields(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is String && _legacyFields.contains(key)) {
          throw ManifestParseException(
            code: UpdateErrorCode.legacyFieldNotSupported,
            message: '$key is not supported in manifest v3.',
          );
        }
        _rejectLegacyFields(entry.value);
      }
      return;
    }

    if (value is Iterable) {
      for (final item in value) {
        _rejectLegacyFields(item);
      }
    }
  }

  static String _requireString(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw ManifestParseException(
      code: UpdateErrorCode.missingRequiredField,
      message: '$field is required.',
    );
  }
}
