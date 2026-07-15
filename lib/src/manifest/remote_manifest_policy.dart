import '../actions/update_action.dart';
import 'remote_action_policy.dart';
import 'update_manifest.dart';

export 'remote_action_policy.dart' show RemoteManifestPolicyException;

/// Enforces remote security policy for the existing Flutter manifest models.
///
/// This adapter classifies typed actions and delegates every trust rule to the
/// pure Dart [RemoteActionPolicy].
class RemoteManifestPolicy {
  /// Creates a stateless remote manifest policy.
  const RemoteManifestPolicy();

  /// Validates every action in [manifest].
  ///
  /// Set [isSigned] only after successful envelope verification.
  void validate(
    UpdateManifest manifest, {
    bool isSigned = true,
  }) {
    const policy = RemoteActionPolicy();
    for (final release in manifest.releases) {
      for (final action in release.actions) {
        switch (action) {
          case DownloadPackageAction():
            policy.validateArtifact(
              url: action.packageUrl,
              size: action.packageSizeBytes,
              sha256: action.sha256,
              field: 'packageUrl',
              isSigned: isSigned,
            );
          case DownloadAndInstallPackageAction():
            policy.validateArtifact(
              url: action.packageUrl,
              size: action.packageSizeBytes,
              sha256: action.sha256,
              field: 'packageUrl',
              isSigned: isSigned,
            );
          case OpenInstallerAction():
            policy.validateArtifact(
              url: action.installerUrl,
              size: action.installerSizeBytes,
              sha256: action.sha256,
              field: 'installerUrl',
              isSigned: isSigned,
            );
          case InstallPackageAction():
            policy.rejectRemoteInstallPackage();
          case OpenAndroidMarketAction():
            policy.validateAndroidMarket(
              appId: manifest.appId,
              targetPackageName: action.targetPackageName,
              fallbackUrl: action.fallbackUrl,
            );
          case OpenStoreAction():
            policy.validateStore(
              store: action.store.name,
              storeUrl: action.storeUrl,
            );
        }
      }
    }
  }
}
