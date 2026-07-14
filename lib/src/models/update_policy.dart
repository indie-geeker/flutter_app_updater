/// Describes how strongly the publisher asks the host application to update.
enum UpdatePolicyLevel {
  /// The update may be ignored without an additional warning.
  optional,

  /// The update should be encouraged but remains dismissible.
  recommended,

  /// The host should block unsupported application use until updated.
  required,
}

/// Publisher policy attached to one update release.
///
/// The package reports policy through structured results; it never presents
/// dialogs or terminates the host application. A candidate is also considered
/// required when the installed version is below [minSupportedVersion].
class UpdatePolicy {
  /// The publisher's explicit recommendation level.
  final UpdatePolicyLevel level;

  /// The oldest application version that remains supported, if constrained.
  final String? minSupportedVersion;

  /// Creates release policy with an optional minimum supported version.
  const UpdatePolicy({
    this.level = UpdatePolicyLevel.optional,
    this.minSupportedVersion,
  });
}
