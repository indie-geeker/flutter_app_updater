enum UpdatePolicyLevel {
  optional,
  recommended,
  required,
}

class UpdatePolicy {
  final UpdatePolicyLevel level;
  final String? minSupportedVersion;

  const UpdatePolicy({
    this.level = UpdatePolicyLevel.optional,
    this.minSupportedVersion,
  });
}
