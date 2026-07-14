import 'package:flutter/foundation.dart';

import '../actions/update_action.dart';
import '../models/update_candidate.dart';
import '../models/update_error_code.dart';
import '../models/update_policy.dart';
import 'manifest_validator.dart';
import 'update_manifest.dart';

export 'manifest_validator.dart' show ManifestParseException;
export 'update_manifest.dart' show UpdateManifest;

class ManifestParser {
  final ManifestValidator validator;

  const ManifestParser({
    this.validator = const ManifestValidator(),
  });

  UpdateManifest parse(Map<String, Object?> json) {
    validator.validate(json);

    final channel = _requiredString(json, 'channel');
    return UpdateManifest(
      schemaVersion: _requiredInt(json, 'schemaVersion'),
      appId: _requiredString(json, 'appId'),
      channel: channel,
      releases: _requiredList(json, 'releases')
          .map((release) => _parseRelease(_asMap(release, 'release'), channel))
          .toList(growable: false),
    );
  }

  UpdateCandidate _parseRelease(
    Map<String, Object?> release,
    String defaultChannel,
  ) {
    return UpdateCandidate(
      version: _requiredString(release, 'version'),
      buildNumber: _optionalString(release, 'buildNumber'),
      channel: _optionalString(release, 'channel') ?? defaultChannel,
      platform: _parsePlatform(_requiredString(release, 'platform')),
      architecture: _optionalString(release, 'architecture'),
      releaseNotes: _requiredString(release, 'releaseNotes'),
      releasedAt: _parseOptionalDateTime(release['releasedAt']),
      policy: _parsePolicy(_optionalMap(release, 'policy')),
      actions: _requiredList(release, 'actions')
          .map((action) => _parseAction(_asMap(action, 'action')))
          .toList(growable: false),
    );
  }

  UpdatePolicy _parsePolicy(Map<String, Object?>? policy) {
    if (policy == null) {
      return const UpdatePolicy();
    }

    return UpdatePolicy(
      level: _parsePolicyLevel(
        _optionalString(policy, 'level') ?? UpdatePolicyLevel.optional.name,
      ),
      minSupportedVersion: _optionalString(policy, 'minSupportedVersion'),
    );
  }

  UpdateAction _parseAction(Map<String, Object?> action) {
    final type = _requiredString(action, 'type');
    return switch (type) {
      'openStore' => OpenStoreAction(
          store: _parseStoreKind(_requiredString(action, 'store')),
          storeUrl: _requiredAbsoluteUri(action, 'storeUrl'),
        ),
      'openAndroidMarket' => OpenAndroidMarketAction(
          market: _parseAndroidMarketKind(_requiredString(action, 'market')),
          targetPackageName: _requiredString(action, 'targetPackageName'),
          fallbackUrl: _optionalAbsoluteUri(action, 'fallbackUrl'),
        ),
      'downloadPackage' => DownloadPackageAction(
          packageUrl: _requiredAbsoluteUri(action, 'packageUrl'),
          packageType:
              _parsePackageType(_requiredString(action, 'packageType')),
          packageSizeBytes: _optionalInt(action, 'packageSizeBytes'),
          sha256: _optionalString(action, 'sha256'),
        ),
      'installPackage' => InstallPackageAction(
          packagePath: _requiredString(action, 'packagePath'),
          packageType: _parsePackageType(
            _optionalString(action, 'packageType') ?? PackageType.apk.name,
          ),
        ),
      'downloadAndInstallPackage' => DownloadAndInstallPackageAction(
          packageUrl: _requiredAbsoluteUri(action, 'packageUrl'),
          packageType:
              _parsePackageType(_requiredString(action, 'packageType')),
          packageSizeBytes: _optionalInt(action, 'packageSizeBytes'),
          sha256: _optionalString(action, 'sha256'),
        ),
      'openInstaller' => OpenInstallerAction(
          installerUrl: _requiredAbsoluteUri(action, 'installerUrl'),
          installerType: _parseInstallerType(
            _requiredString(action, 'installerType'),
          ),
          installerSizeBytes: _optionalInt(action, 'installerSizeBytes'),
          sha256: _optionalString(action, 'sha256'),
        ),
      _ => throw ManifestParseException(
          code: UpdateErrorCode.unsupportedActionType,
          message: 'Unsupported action type: $type.',
        ),
    };
  }

  TargetPlatform _parsePlatform(String value) {
    return switch (value) {
      'android' => TargetPlatform.android,
      'ios' => TargetPlatform.iOS,
      'macos' => TargetPlatform.macOS,
      'windows' => TargetPlatform.windows,
      'linux' => TargetPlatform.linux,
      'fuchsia' => TargetPlatform.fuchsia,
      _ => throw ManifestParseException(
          code: UpdateErrorCode.manifestInvalid,
          message: 'Unsupported platform: $value.',
        ),
    };
  }

  UpdatePolicyLevel _parsePolicyLevel(String value) {
    return switch (value) {
      'optional' => UpdatePolicyLevel.optional,
      'recommended' => UpdatePolicyLevel.recommended,
      'required' => UpdatePolicyLevel.required,
      _ => throw ManifestParseException(
          code: UpdateErrorCode.manifestInvalid,
          message: 'Unsupported policy level: $value.',
        ),
    };
  }

  StoreKind _parseStoreKind(String value) {
    return switch (value) {
      'appStore' => StoreKind.appStore,
      'macAppStore' => StoreKind.macAppStore,
      'googlePlay' => StoreKind.googlePlay,
      _ => throw ManifestParseException(
          code: UpdateErrorCode.manifestInvalid,
          message: 'Unsupported store: $value.',
        ),
    };
  }

  AndroidMarketKind _parseAndroidMarketKind(String value) {
    return switch (value) {
      'huawei' => AndroidMarketKind.huawei,
      'honor' => AndroidMarketKind.honor,
      'xiaomi' => AndroidMarketKind.xiaomi,
      'oppo' => AndroidMarketKind.oppo,
      'vivo' => AndroidMarketKind.vivo,
      'meizu' => AndroidMarketKind.meizu,
      'tencentMyApp' => AndroidMarketKind.tencentMyApp,
      'generic' => AndroidMarketKind.generic,
      _ => throw ManifestParseException(
          code: UpdateErrorCode.manifestInvalid,
          message: 'Unsupported Android market: $value.',
        ),
    };
  }

  PackageType _parsePackageType(String value) {
    return switch (value) {
      'apk' => PackageType.apk,
      'aab' => PackageType.aab,
      _ => throw ManifestParseException(
          code: UpdateErrorCode.manifestInvalid,
          message: 'Unsupported package type: $value.',
        ),
    };
  }

  InstallerType _parseInstallerType(String value) {
    return switch (value) {
      'msix' => InstallerType.msix,
      'msi' => InstallerType.msi,
      'exe' => InstallerType.exe,
      'dmg' => InstallerType.dmg,
      'zip' => InstallerType.zip,
      'appImage' => InstallerType.appImage,
      'deb' => InstallerType.deb,
      'rpm' => InstallerType.rpm,
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

  int? _optionalInt(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    throw ManifestParseException(
      code: UpdateErrorCode.manifestInvalid,
      message: '$field must be an integer.',
    );
  }
}
