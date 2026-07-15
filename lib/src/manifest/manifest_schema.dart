import 'dart:convert';

import '../models/update_error_code.dart';
import '../utils/version_comparator.dart';

/// Structured schema or manifest parsing failure.
class ManifestParseException implements Exception {
  /// Stable failure category.
  final UpdateErrorCode code;

  /// Human-readable field or schema diagnostic.
  final String message;

  /// Creates a manifest parse failure.
  const ManifestParseException({
    required this.code,
    required this.message,
  });

  @override
  String toString() => '${code.value}: $message';
}

/// Strict structural validator for remote manifest schema version 3.
///
/// It rejects removed legacy fields and requires exact size and SHA-256
/// metadata for every remotely downloadable artifact.
class ManifestSchema {
  static const _legacyFields = {
    'downloadUrl',
    'md5',
    'artifactUri',
  };
  static const _rootFields = {
    'schemaVersion',
    'appId',
    'channel',
    'releases',
  };
  static const _releaseFields = {
    'version',
    'buildNumber',
    'channel',
    'platform',
    'architecture',
    'releaseNotes',
    'releasedAt',
    'policy',
    'actions',
  };
  static const _policyFields = {
    'level',
    'minSupportedVersion',
  };
  static const _actionFields = <String, Set<String>>{
    'openStore': {
      'type',
      'store',
      'storeUrl',
    },
    'openAndroidMarket': {
      'type',
      'market',
      'targetPackageName',
      'fallbackUrl',
    },
    'downloadPackage': {
      'type',
      'packageUrl',
      'packageType',
      'packageSizeBytes',
      'sha256',
    },
    'installPackage': {
      'type',
      'packagePath',
      'packageType',
    },
    'downloadAndInstallPackage': {
      'type',
      'packageUrl',
      'packageType',
      'packageSizeBytes',
      'sha256',
    },
    'openInstaller': {
      'type',
      'installerUrl',
      'installerType',
      'installerSizeBytes',
      'sha256',
    },
  };

  /// Creates a stateless v3 schema validator.
  const ManifestSchema();

  /// Validates [manifest] or throws [ManifestParseException].
  void validate(Map<String, Object?> manifest) {
    _rejectLegacyFields(manifest);
    _validateRoot(manifest);
    final releases = _requiredList(manifest, 'releases');
    for (var index = 0; index < releases.length; index += 1) {
      _validateRelease(
        _asMap(releases[index], 'release'),
        '\$.releases[$index]',
      );
    }
  }

  void _validateRoot(Map<String, Object?> manifest) {
    _rejectUnknownFields(manifest, _rootFields, r'$');

    final schemaVersion = manifest['schemaVersion'];
    if (schemaVersion == null) {
      throw const ManifestParseException(
        code: UpdateErrorCode.missingRequiredField,
        message: 'schemaVersion is required.',
      );
    }
    if (schemaVersion != 3) {
      throw const ManifestParseException(
        code: UpdateErrorCode.unsupportedSchemaVersion,
        message: 'Unsupported schemaVersion.',
      );
    }

    _requiredString(manifest, 'appId');
    _requiredString(manifest, 'channel');
  }

  void _validateRelease(Map<String, Object?> release, String path) {
    _rejectUnknownFields(release, _releaseFields, path);

    final version = _requiredString(release, 'version');
    _validateVersion(version, 'version');
    final buildNumber = _optionalString(release, 'buildNumber');
    if (buildNumber != null) {
      _validateBuildNumber(buildNumber);
    }
    _requiredString(release, 'platform');
    _requiredString(release, 'releaseNotes');

    final policy = release['policy'];
    if (policy != null) {
      final policyMap = _asMap(policy, 'policy');
      _rejectUnknownFields(policyMap, _policyFields, '$path.policy');
      final minSupportedVersion =
          _optionalString(policyMap, 'minSupportedVersion');
      if (minSupportedVersion != null) {
        _validateVersion(
          minSupportedVersion,
          'minSupportedVersion',
          code: UpdateErrorCode.configurationInvalid,
        );
        if (VersionComparator.compare(minSupportedVersion, version) > 0) {
          throw const ManifestParseException(
            code: UpdateErrorCode.configurationInvalid,
            message: 'minSupportedVersion must not exceed version.',
          );
        }
      }
    }

    final actions = _requiredList(release, 'actions');
    if (actions.isEmpty) {
      throw const ManifestParseException(
        code: UpdateErrorCode.missingRequiredField,
        message: 'actions is required.',
      );
    }

    for (var index = 0; index < actions.length; index += 1) {
      _validateAction(
        _asMap(actions[index], 'action'),
        '$path.actions[$index]',
      );
    }
  }

  void _validateBuildNumber(String value) {
    final parsed = int.tryParse(value);
    if (!RegExp(r'^[0-9]+$').hasMatch(value) || parsed == null || parsed < 0) {
      throw const ManifestParseException(
        code: UpdateErrorCode.manifestInvalid,
        message: 'buildNumber must be a non-negative integer string.',
      );
    }
  }

  void _validateVersion(
    String value,
    String field, {
    UpdateErrorCode code = UpdateErrorCode.manifestInvalid,
  }) {
    if (!VersionComparator.isValidVersion(value)) {
      throw ManifestParseException(
        code: code,
        message: '$field must be a valid semantic version.',
      );
    }
  }

  void _validateAction(Map<String, Object?> action, String path) {
    final type = _requiredString(action, 'type');
    final allowedFields = _actionFields[type];
    if (allowedFields == null) {
      throw const ManifestParseException(
        code: UpdateErrorCode.unsupportedActionType,
        message: 'Unsupported action type.',
      );
    }
    _rejectUnknownFields(action, allowedFields, path);

    switch (type) {
      case 'openStore':
        _requiredString(action, 'store');
        _requiredAbsoluteUrl(action, 'storeUrl');
      case 'openAndroidMarket':
        _requiredString(action, 'market');
        _requiredString(action, 'targetPackageName');
        _optionalAbsoluteUrl(action, 'fallbackUrl');
      case 'downloadPackage':
        _requiredAbsoluteUrl(action, 'packageUrl');
        _requiredString(action, 'packageType');
        _requiredPositiveInt(action, 'packageSizeBytes');
        _requiredSha256(action);
      case 'installPackage':
        _requiredString(action, 'packagePath');
        _optionalString(action, 'packageType');
      case 'downloadAndInstallPackage':
        _requiredAbsoluteUrl(action, 'packageUrl');
        _requiredString(action, 'packageType');
        _requiredPositiveInt(action, 'packageSizeBytes');
        _requiredSha256(action);
      case 'openInstaller':
        _requiredAbsoluteUrl(action, 'installerUrl');
        _requiredString(action, 'installerType');
        _requiredPositiveInt(action, 'installerSizeBytes');
        _requiredSha256(action);
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

  void _rejectUnknownFields(
    Map<String, Object?> map,
    Set<String> allowedFields,
    String path,
  ) {
    for (final field in map.keys) {
      if (!allowedFields.contains(field)) {
        throw ManifestParseException(
          code: UpdateErrorCode.manifestInvalid,
          message: 'Unknown field ${jsonEncode(field)} at $path.',
        );
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

  int _requiredPositiveInt(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value is int && value > 0) {
      return value;
    }
    throw ManifestParseException(
      code: value == null
          ? UpdateErrorCode.missingRequiredField
          : UpdateErrorCode.manifestInvalid,
      message: '$field is required and must be a positive integer.',
    );
  }

  void _requiredSha256(Map<String, Object?> map) {
    final value = _requiredString(map, 'sha256');
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
      throw const ManifestParseException(
        code: UpdateErrorCode.manifestInvalid,
        message: 'sha256 must contain exactly 64 hexadecimal characters.',
      );
    }
  }
}
