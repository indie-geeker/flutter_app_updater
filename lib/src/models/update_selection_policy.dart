/// Determines whether selection may skip a newer non-executable release.
enum UpdateSelectionPolicy {
  /// Select the newest release even when none of its actions can execute.
  latestRelease,

  /// Select the newest executable release without bypassing required updates.
  latestExecutable,
}
