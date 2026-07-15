import 'dart:io';

Future<void> main() async {
  final tempDirectory =
      await Directory.systemTemp.createTemp('flutter_app_updater_cli_');
  try {
    final help = await _run(['dart', 'run', 'flutter_app_updater', '--help']);
    _expect(
      help,
      exitCode: 0,
      stdout: (value) => value.contains('Usage: flutter_app_updater'),
      expectation: 'help output containing "Usage: flutter_app_updater"',
    );

    final generated = await _run([
      'dart',
      'run',
      'flutter_app_updater',
      'manifest',
      'generate',
    ]);
    _expect(
      generated,
      exitCode: 0,
      stdout: (value) => value.trim().isNotEmpty,
      expectation: 'a generated manifest on stdout',
    );

    final manifestFile = File('${tempDirectory.path}/manifest.json');
    await manifestFile.writeAsString(generated.stdout);

    final verified = await _run([
      'dart',
      'run',
      'flutter_app_updater',
      'manifest',
      'verify',
      manifestFile.path,
    ]);
    _expect(
      verified,
      exitCode: 0,
      stdout: (value) => value.contains('Manifest valid'),
      expectation: 'verify output containing "Manifest valid"',
    );

    final hashed = await _run([
      'dart',
      'run',
      'flutter_app_updater',
      'hash',
      'pubspec.yaml',
    ]);
    _expect(
      hashed,
      exitCode: 0,
      stdout: (value) => RegExp(r'^[0-9a-f]{64}\n?$').hasMatch(value),
      expectation: 'a lowercase 64-character SHA-256 digest',
    );
  } finally {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  }
}

Future<_CommandResult> _run(List<String> command) async {
  final result = await Process.run(command.first, command.skip(1).toList());
  return _CommandResult(
    command: command,
    exitCode: result.exitCode,
    stdout: result.stdout as String,
    stderr: result.stderr as String,
  );
}

void _expect(
  _CommandResult result, {
  required int exitCode,
  required bool Function(String) stdout,
  required String expectation,
}) {
  if (result.exitCode == exitCode && stdout(result.stdout)) {
    return;
  }

  throw StateError(
    'CLI executable check failed.\n'
    'Command: ${result.command.join(' ')}\n'
    'Expected: exit $exitCode and $expectation\n'
    'Actual exit: ${result.exitCode}\n'
    'stdout:\n${result.stdout}\n'
    'stderr:\n${result.stderr}',
  );
}

class _CommandResult {
  final List<String> command;
  final int exitCode;
  final String stdout;
  final String stderr;

  const _CommandResult({
    required this.command,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });
}
