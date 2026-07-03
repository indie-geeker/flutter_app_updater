import 'dart:io' as io;

import 'package:flutter_app_updater/src/cli/hash_command.dart';
import 'package:flutter_app_updater/src/cli/manifest_command.dart';

Future<void> main(List<String> args) async {
  final result = await runFlutterAppUpdaterCli(args);

  if (result.stdout.isNotEmpty) {
    io.stdout.write(result.stdout);
  }
  if (result.stderr.isNotEmpty) {
    io.stderr.write(result.stderr);
  }

  io.exitCode = result.exitCode;
}

Future<CliCommandResult> runFlutterAppUpdaterCli(List<String> args) async {
  if (args.isEmpty || args.first == 'help' || args.first == '--help') {
    return const CliCommandResult(
      exitCode: 0,
      stdout: 'Usage: flutter_app_updater <manifest|hash>\n',
    );
  }

  return switch (args.first) {
    'manifest' => const ManifestCommand().run(args.skip(1).toList()),
    'hash' => const HashCommand().run(args.skip(1).toList()),
    _ => CliCommandResult(
        exitCode: 1,
        stderr: 'Unknown command: ${args.first}\n',
      ),
  };
}
