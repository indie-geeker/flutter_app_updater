import '../models/update_error_code.dart';
import '../utils/trusted_update_uri.dart';
import 'manifest_document.dart';

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

/// Pure Dart security policy shared by document and Flutter model adapters.
class RemoteActionPolicy {
  static const _appleStoreHosts = {'apps.apple.com', 'itunes.apple.com'};

  /// Creates a stateless remote action policy.
  const RemoteActionPolicy();

  /// Validates every action in a parsed [manifest] document.
  void validateDocument(
    ManifestDocument manifest, {
    bool isSigned = true,
  }) {
    for (final release in manifest.releases) {
      for (final action in release.actions) {
        switch (action) {
          case ManifestDownloadPackageAction():
            validateArtifact(
              url: action.packageUrl,
              size: action.packageSizeBytes,
              sha256: action.sha256,
              field: 'packageUrl',
              isSigned: isSigned,
            );
          case ManifestDownloadAndInstallPackageAction():
            validateArtifact(
              url: action.packageUrl,
              size: action.packageSizeBytes,
              sha256: action.sha256,
              field: 'packageUrl',
              isSigned: isSigned,
            );
          case ManifestOpenInstallerAction():
            validateArtifact(
              url: action.installerUrl,
              size: action.installerSizeBytes,
              sha256: action.sha256,
              field: 'installerUrl',
              isSigned: isSigned,
            );
          case ManifestInstallPackageAction():
            rejectRemoteInstallPackage();
          case ManifestOpenAndroidMarketAction():
            validateAndroidMarket(
              appId: manifest.appId,
              targetPackageName: action.targetPackageName,
              fallbackUrl: action.fallbackUrl,
            );
          case ManifestOpenStoreAction():
            validateStore(
              store: action.store,
              storeUrl: action.storeUrl,
            );
        }
      }
    }
  }

  /// Validates one self-hosted artifact action.
  void validateArtifact({
    required Uri url,
    required int size,
    required String sha256,
    required String field,
    required bool isSigned,
  }) {
    if (!isSigned) {
      throw const RemoteManifestPolicyException(
        code: UpdateErrorCode.manifestSignatureRequired,
        message: 'Self-hosted update actions require a signed manifest.',
      );
    }
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

  /// Rejects local package installation instructions from remote input.
  Never rejectRemoteInstallPackage() {
    throw const RemoteManifestPolicyException(
      code: UpdateErrorCode.unsupportedActionType,
      message: 'installPackage is allowed only for trusted local code.',
    );
  }

  /// Validates Android package binding and an optional market fallback URL.
  void validateAndroidMarket({
    required String appId,
    required String targetPackageName,
    required Uri? fallbackUrl,
  }) {
    if (targetPackageName != appId) {
      throw const RemoteManifestPolicyException(
        code: UpdateErrorCode.appIdMismatch,
        message: 'Android market targetPackageName must equal manifest appId.',
      );
    }
    if (fallbackUrl != null) {
      _requireTrustedUri(fallbackUrl, field: 'fallbackUrl');
    }
  }

  /// Validates an official-store URL against its declared [store].
  void validateStore({
    required ManifestStoreKind store,
    required Uri storeUrl,
  }) {
    _requireTrustedUri(storeUrl, field: 'storeUrl');
    final host = storeUrl.host.toLowerCase();
    final isAllowed = switch (store) {
      ManifestStoreKind.googlePlay => host == 'play.google.com',
      ManifestStoreKind.appStore ||
      ManifestStoreKind.macAppStore =>
        _appleStoreHosts.contains(host),
    };
    if (!isAllowed) {
      throw RemoteManifestPolicyException(
        code: UpdateErrorCode.manifestInvalid,
        message: 'storeUrl host is not allowed for ${store.name}.',
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
