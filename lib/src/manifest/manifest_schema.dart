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

class ManifestSchema {
  static const _legacyFields = {
    'downloadUrl',
    'md5',
    'artifactUri',
  };

  const ManifestSchema();

  void validate(Map<String, Object?> manifest) {
    _rejectLegacyFields(manifest);
    _validateRoot(manifest);
    for (final release in _requiredList(manifest, 'releases')) {
      _validateRelease(_asMap(release, 'release'));
    }
  }

  void _validateRoot(Map<String, Object?> manifest) {
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

    _requiredString(manifest, 'appId');
    _requiredString(manifest, 'channel');
  }

  void _validateRelease(Map<String, Object?> release) {
    _requiredString(release, 'version');
    _requiredString(release, 'platform');
    _requiredString(release, 'releaseNotes');

    final actions = _requiredList(release, 'actions');
    if (actions.isEmpty) {
      throw const ManifestParseException(
        code: UpdateErrorCode.missingRequiredField,
        message: 'actions is required.',
      );
    }

    for (final action in actions) {
      _validateAction(_asMap(action, 'action'));
    }
  }

  void _validateAction(Map<String, Object?> action) {
    final type = _requiredString(action, 'type');
    switch (type) {
      case 'openStore':
        _requiredString(action, 'store');
        _requiredAbsoluteUrl(action, 'storeUrl');
      case 'openAndroidMarket':
        _requiredString(action, 'market');
        _requiredString(action, 'targetPackageName');
        _optionalAbsoluteUrl(action, 'fallbackUrl');
      case 'playInAppUpdate':
        _requiredString(action, 'mode');
      case 'downloadPackage':
        _requiredAbsoluteUrl(action, 'packageUrl');
        _requiredString(action, 'packageType');
      case 'openInstaller':
        _requiredAbsoluteUrl(action, 'installerUrl');
        _requiredString(action, 'installerType');
      default:
        throw ManifestParseException(
          code: UpdateErrorCode.unsupportedActionType,
          message: 'Unsupported action type: $type.',
        );
    }
  }

  void _requiredAbsoluteUrl(Map<String, Object?> map, String field) {
    _parseAbsoluteUrl(_requiredString(map, field), field);
  }

  void _optionalAbsoluteUrl(Map<String, Object?> map, String field) {
    final value = _optionalString(map, field);
    if (value != null) {
      _parseAbsoluteUrl(value, field);
    }
  }

  Uri _parseAbsoluteUrl(String value, String field) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw ManifestParseException(
        code: UpdateErrorCode.manifestInvalid,
        message: '$field must be an absolute URL.',
      );
    }
    return uri;
  }

  void _rejectLegacyFields(Object? value) {
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

  Map<String, Object?> _asMap(Object? value, String field) {
    if (value is! Map) {
      throw ManifestParseException(
        code: UpdateErrorCode.manifestInvalid,
        message: '$field must be an object.',
      );
    }

    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw ManifestParseException(
          code: UpdateErrorCode.manifestInvalid,
          message: '$field contains a non-string key.',
        );
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  List<Object?> _requiredList(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value is List) {
      return value.cast<Object?>();
    }
    throw ManifestParseException(
      code: UpdateErrorCode.missingRequiredField,
      message: '$field is required.',
    );
  }

  String _requiredString(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw ManifestParseException(
      code: UpdateErrorCode.missingRequiredField,
      message: '$field is required.',
    );
  }

  String? _optionalString(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value == null) {
      return null;
    }
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw ManifestParseException(
      code: UpdateErrorCode.manifestInvalid,
      message: '$field must be a string.',
    );
  }
}
