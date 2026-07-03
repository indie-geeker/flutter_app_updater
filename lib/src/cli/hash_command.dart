import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'manifest_command.dart';

class HashCommand {
  const HashCommand();

  Future<String> compute(String path) async {
    final file = File(path);
    return crypto.sha256.bind(file.openRead()).first.then((digest) {
      return digest.toString();
    });
  }

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
