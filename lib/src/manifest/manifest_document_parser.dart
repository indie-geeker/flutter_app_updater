import '../models/update_error_code.dart';
import 'manifest_document.dart';
import 'manifest_validator.dart';

export 'manifest_validator.dart' show ManifestParseException;

/// Parses schema-valid manifest JSON without importing Flutter libraries.
class ManifestDocumentParser {
  /// Structural validator run before any field is interpreted.
  final ManifestValidator validator;

  /// Creates a document parser with an injectable validator.
  const ManifestDocumentParser({
    this.validator = const ManifestValidator(),
  });

  /// Validates and parses [json] into an immutable document.
  ManifestDocument parse(Map<String, Object?> json) {
    validator.validate(json);

    final channel = _requiredString(json, 'channel');
    return ManifestDocument(
      schemaVersion: _requiredInt(json, 'schemaVersion'),
      appId: _requiredString(json, 'appId'),
      channel: channel,
      releases: _requiredList(json, 'releases').map(
        (release) => _parseRelease(_asMap(release, 'release'), channel),
      ),
    );
  }

  ManifestReleaseDocument _parseRelease(
    Map<String, Object?> release,
    String defaultChannel,
  ) {
    return ManifestReleaseDocument(
      version: _requiredString(release, 'version'),
      buildNumber: _optionalString(release, 'buildNumber'),
      channel: _optionalString(release, 'channel') ?? defaultChannel,
      platform: _parsePlatform(_requiredString(release, 'platform')),
      architecture: _optionalString(release, 'architecture'),
      releaseNotes: _requiredString(release, 'releaseNotes'),
      releasedAt: _parseOptionalDateTime(release['releasedAt']),
      policy: _parsePolicy(_optionalMap(release, 'policy')),
      actions: _requiredList(release, 'actions').map(
        (action) => _parseAction(_asMap(action, 'action')),
      ),
    );
  }

  ManifestPolicyDocument _parsePolicy(Map<String, Object?>? policy) {
    if (policy == null) {
      return const ManifestPolicyDocument();
    }

    return ManifestPolicyDocument(
      level: _parsePolicyLevel(
        _optionalString(policy, 'level') ?? ManifestPolicyLevel.optional.name,
      ),
      minSupportedVersion: _optionalString(policy, 'minSupportedVersion'),
    );
  }

  ManifestAction _parseAction(Map<String, Object?> action) {
    final type = _requiredString(action, 'type');
    return switch (type) {
      'openStore' => ManifestOpenStoreAction(
          store: _parseStoreKind(_requiredString(action, 'store')),
          storeUrl: _requiredAbsoluteUri(action, 'storeUrl'),
        ),
      'openAndroidMarket' => ManifestOpenAndroidMarketAction(
          market: _parseAndroidMarketKind(_requiredString(action, 'market')),
          targetPackageName: _requiredString(action, 'targetPackageName'),
          fallbackUrl: _optionalAbsoluteUri(action, 'fallbackUrl'),
        ),
      'downloadPackage' => ManifestDownloadPackageAction(
          packageUrl: _requiredAbsoluteUri(action, 'packageUrl'),
          packageType:
              _parsePackageType(_requiredString(action, 'packageType')),
          packageSizeBytes: _requiredInt(action, 'packageSizeBytes'),
          sha256: _requiredString(action, 'sha256').toLowerCase(),
        ),
      'installPackage' => ManifestInstallPackageAction(
          packagePath: _requiredString(action, 'packagePath'),
          packageType: _parsePackageType(
            _optionalString(action, 'packageType') ??
                ManifestPackageType.apk.name,
          ),
        ),
      'downloadAndInstallPackage' => ManifestDownloadAndInstallPackageAction(
          packageUrl: _requiredAbsoluteUri(action, 'packageUrl'),
          packageType:
              _parsePackageType(_requiredString(action, 'packageType')),
          packageSizeBytes: _requiredInt(action, 'packageSizeBytes'),
          sha256: _requiredString(action, 'sha256').toLowerCase(),
        ),
      'openInstaller' => ManifestOpenInstallerAction(
          installerUrl: _requiredAbsoluteUri(action, 'installerUrl'),
          installerType:
              _parseInstallerType(_requiredString(action, 'installerType')),
          installerSizeBytes: _requiredInt(action, 'installerSizeBytes'),
          sha256: _requiredString(action, 'sha256').toLowerCase(),
        ),
      _ => throw ManifestParseException(
          code: UpdateErrorCode.unsupportedActionType,
          message: 'Unsupported action type: $type.',
        ),
    };
  }

  ManifestPlatform _parsePlatform(String value) {
    return switch (value) {
      'android' => ManifestPlatform.android,
      'ios' => ManifestPlatform.ios,
      'macos' => ManifestPlatform.macos,
      'windows' => ManifestPlatform.windows,
      'linux' => ManifestPlatform.linux,
      'fuchsia' => ManifestPlatform.fuchsia,
      _ => throw ManifestParseException(
          code: UpdateErrorCode.manifestInvalid,
          message: 'Unsupported platform: $value.',
        ),
    };
  }

  ManifestPolicyLevel _parsePolicyLevel(String value) {
    return switch (value) {
      'optional' => ManifestPolicyLevel.optional,
      'recommended' => ManifestPolicyLevel.recommended,
      'required' => ManifestPolicyLevel.required,
      _ => throw ManifestParseException(
          code: UpdateErrorCode.manifestInvalid,
          message: 'Unsupported policy level: $value.',
        ),
    };
  }

  ManifestStoreKind _parseStoreKind(String value) {
    return switch (value) {
      'appStore' => ManifestStoreKind.appStore,
      'macAppStore' => ManifestStoreKind.macAppStore,
      'googlePlay' => ManifestStoreKind.googlePlay,
      _ => throw ManifestParseException(
          code: UpdateErrorCode.manifestInvalid,
          message: 'Unsupported store: $value.',
        ),
    };
  }

  ManifestAndroidMarketKind _parseAndroidMarketKind(String value) {
    return switch (value) {
      'huawei' => ManifestAndroidMarketKind.huawei,
      'honor' => ManifestAndroidMarketKind.honor,
      'xiaomi' => ManifestAndroidMarketKind.xiaomi,
      'oppo' => ManifestAndroidMarketKind.oppo,
      'vivo' => ManifestAndroidMarketKind.vivo,
      'meizu' => ManifestAndroidMarketKind.meizu,
      'tencentMyApp' => ManifestAndroidMarketKind.tencentMyApp,
      'generic' => ManifestAndroidMarketKind.generic,
      _ => throw ManifestParseException(
          code: UpdateErrorCode.manifestInvalid,
          message: 'Unsupported Android market: $value.',
        ),
    };
  }

  ManifestPackageType _parsePackageType(String value) {
    return switch (value) {
      'apk' => ManifestPackageType.apk,
      'aab' => ManifestPackageType.aab,
      _ => throw ManifestParseException(
          code: UpdateErrorCode.manifestInvalid,
          message: 'Unsupported package type: $value.',
        ),
    };
  }

  ManifestInstallerType _parseInstallerType(String value) {
    return switch (value) {
      'msix' => ManifestInstallerType.msix,
      'msi' => ManifestInstallerType.msi,
      'exe' => ManifestInstallerType.exe,
      'dmg' => ManifestInstallerType.dmg,
      'zip' => ManifestInstallerType.zip,
      'appImage' => ManifestInstallerType.appImage,
      'deb' => ManifestInstallerType.deb,
      'rpm' => ManifestInstallerType.rpm,
      _ => throw ManifestParseException(
          code: UpdateErrorCode.manifestInvalid,
          message: 'Unsupported installer type: $value.',
        ),
    };
  }

  DateTime? _parseOptionalDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    throw const ManifestParseException(
      code: UpdateErrorCode.manifestInvalid,
      message: 'releasedAt must be an ISO-8601 string.',
    );
  }

  Uri _requiredAbsoluteUri(Map<String, Object?> map, String field) {
    return _parseAbsoluteUri(_requiredString(map, field), field);
  }

  Uri? _optionalAbsoluteUri(Map<String, Object?> map, String field) {
    final value = _optionalString(map, field);
    return value == null ? null : _parseAbsoluteUri(value, field);
  }

  Uri _parseAbsoluteUri(String value, String field) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw ManifestParseException(
        code: UpdateErrorCode.manifestInvalid,
        message: '$field must be an absolute URL.',
      );
    }
    return uri;
  }

  Map<String, Object?>? _optionalMap(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value == null) {
      return null;
    }
    return _asMap(value, field);
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

  int _requiredInt(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value is int) {
      return value;
    }
    throw ManifestParseException(
      code: UpdateErrorCode.missingRequiredField,
      message: '$field is required.',
    );
  }
}
