/// Captured process result returned by package CLI commands.
class CliCommandResult {
  /// Conventional process exit code.
  final int exitCode;

  /// Text intended for standard output.
  final String stdout;

  /// Text intended for standard error.
  final String stderr;

  /// Creates a captured CLI result.
  const CliCommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });
}
