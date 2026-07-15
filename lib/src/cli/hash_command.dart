import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'cli_command_result.dart';

/// Computes release-compatible SHA-256 artifact digests.
class HashCommand {
  /// Creates a stateless hash command.
  const HashCommand();

  /// Streams the file at [path] and returns its lowercase SHA-256 digest.
  Future<String> compute(String path) async {
    final file = File(path);
    return crypto.sha256.bind(file.openRead()).first.then((digest) {
      return digest.toString();
    });
  }

  /// Runs the CLI command and returns captured output and an exit code.
  Future<CliCommandResult> run(List<String> args) async {
    if (args.isEmpty) {
      return const CliCommandResult(
        exitCode: 1,
        stderr: 'Usage: flutter_app_updater hash <path>\n',
      );
    }

    try {
      final hash = await compute(args.first);
      return CliCommandResult(exitCode: 0, stdout: '$hash\n');
    } on FileSystemException catch (error) {
      return CliCommandResult(
        exitCode: 1,
        stderr: 'HASH_FAILED: ${error.message}\n',
      );
    }
  }
}
