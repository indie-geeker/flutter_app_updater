/// Restricts which delivery families may be selected from a release.
///
/// The policy is applied after platform capability filtering while preserving
/// the manifest's action order. It is therefore both a security boundary and
/// a host-controlled distribution preference.
enum UpdateDistributionPolicy {
  /// Allows official-store, Android-market, and self-hosted actions.
  any,

  /// Allows only official-store and Android-market actions.
  storeOnly,

  /// Allows only package downloads, package installation, and installers.
  selfHostedOnly,
}
