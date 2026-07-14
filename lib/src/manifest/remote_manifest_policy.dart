import '../actions/update_action.dart';
import '../models/update_error_code.dart';
import '../utils/trusted_update_uri.dart';
import 'update_manifest.dart';

/// Structured cross-field or trust-policy failure for remote manifests.
class RemoteManifestPolicyException implements Exception {
  /// Stable trust or validation failure category.
  final UpdateErrorCode code;

  /// Human-readable policy diagnostic.
  final String message;

  /// Creates a remote-policy failure.
  const RemoteManifestPolicyException({
    required this.code,
    required this.message,
  });

  @override
  String toString() => '${code.value}: $message';
}

/// Enforces security rules that require typed cross-field context.
///
/// Self-hosted artifacts require a signed envelope, trusted HTTPS, a positive
/// exact size, and SHA-256. Remote local-path installs are prohibited. Store
/// and market destinations are restricted, and Android market package identity
/// must equal the manifest application identifier.
class RemoteManifestPolicy {
  static const _appleStoreHosts = {'apps.apple.com', 'itunes.apple.com'};

  /// Creates a stateless remote manifest policy.
  const RemoteManifestPolicy();

  /// Validates every action in [manifest].
  ///
  /// Set [isSigned] only after successful envelope verification.
  void validate(
    UpdateManifest manifest, {
    bool isSigned = true,
  }) {
    for (final release in manifest.releases) {
      for (final action in release.actions) {
        _validateAction(
          action,
          appId: manifest.appId,
          isSigned: isSigned,
        );
      }
    }
  }

  void _validateAction(
    UpdateAction action, {
    required String appId,
    required bool isSigned,
  }) {
    switch (action) {
      case DownloadPackageAction():
        _requireSignature(isSigned);
        _validateArtifact(
          url: action.packageUrl,
          size: action.packageSizeBytes,
          sha256: action.sha256,
          field: 'packageUrl',
        );
      case DownloadAndInstallPackageAction():
        _requireSignature(isSigned);
        _validateArtifact(
          url: action.packageUrl,
          size: action.packageSizeBytes,
          sha256: action.sha256,
          field: 'packageUrl',
        );
      case OpenInstallerAction():
        _requireSignature(isSigned);
        _validateArtifact(
          url: action.installerUrl,
          size: action.installerSizeBytes,
          sha256: action.sha256,
          field: 'installerUrl',
        );
      case InstallPackageAction():
        throw const RemoteManifestPolicyException(
          code: UpdateErrorCode.unsupportedActionType,
          message: 'installPackage is allowed only for trusted local code.',
        );
      case OpenAndroidMarketAction():
        if (action.targetPackageName != appId) {
          throw RemoteManifestPolicyException(
            code: UpdateErrorCode.appIdMismatch,
            message: 'Android market targetPackageName must equal $appId.',
          );
        }
        final fallbackUrl = action.fallbackUrl;
        if (fallbackUrl != null) {
          _requireTrustedUri(fallbackUrl, field: 'fallbackUrl');
        }
      case OpenStoreAction():
        _validateStore(action);
    }
  }

  void _requireSignature(bool isSigned) {
    if (!isSigned) {
      throw const RemoteManifestPolicyException(
        code: UpdateErrorCode.manifestSignatureRequired,
        message: 'Self-hosted update actions require a signed manifest.',
      );
    }
  }

  void _validateArtifact({
    required Uri url,
    required int size,
    required String sha256,
    required String field,
  }) {
    _requireTrustedUri(url, field: field);
    if (size <= 0) {
      throw RemoteManifestPolicyException(
        code: UpdateErrorCode.missingRequiredField,
        message: '$field requires a positive exact size.',
      );
    }
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256)) {
      throw RemoteManifestPolicyException(
        code: UpdateErrorCode.missingRequiredField,
        message: '$field requires a 64-character SHA-256.',
      );
    }
  }

  void _validateStore(OpenStoreAction action) {
    _requireTrustedUri(action.storeUrl, field: 'storeUrl');
    final host = action.storeUrl.host.toLowerCase();
    final isAllowed = switch (action.store) {
      StoreKind.googlePlay => host == 'play.google.com',
      StoreKind.appStore ||
      StoreKind.macAppStore =>
        _appleStoreHosts.contains(host),
    };
    if (!isAllowed) {
      throw RemoteManifestPolicyException(
        code: UpdateErrorCode.manifestInvalid,
        message: 'storeUrl host is not allowed for ${action.store.name}.',
      );
    }
  }

  void _requireTrustedUri(Uri uri, {required String field}) {
    try {
      requireTrustedHttpsUri(
        uri,
        allowInsecureLoopback: false,
        field: field,
      );
    } on ArgumentError catch (error) {
      throw RemoteManifestPolicyException(
        code: UpdateErrorCode.manifestInvalid,
        message: error.message.toString(),
      );
    }
  }
}
