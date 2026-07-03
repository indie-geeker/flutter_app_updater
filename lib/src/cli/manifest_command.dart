import 'dart:convert';
import 'dart:io';

import '../manifest/manifest_schema.dart';

class CliCommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const CliCommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });
}

class ManifestCommand {
  const ManifestCommand();

  String generate() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'schemaVersion': 3,
      'appId': 'com.example.app',
      'channel': 'stable',
      'releases': [
        {
          'version': '2.0.0',
          'buildNumber': '42',
          'platform': 'android',
          'architecture': 'arm64',
          'releaseNotes': 'Bug fixes',
          'releasedAt': '2026-07-03T10:00:00Z',
          'policy': {
            'level': 'recommended',
            'minSupportedVersion': '1.5.0',
          },
          'actions': [
            {
              'type': 'downloadPackage',
              'packageUrl': 'https://example.com/app.apk',
              'packageType': 'apk',
              'packageSizeBytes': 25600000,
              'sha256': 'a' * 64,
            },
          ],
        },
      ],
    });
  }

  Future<CliCommandResult> verify(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return CliCommandResult(
          exitCode: 1,
          stderr: 'Manifest file not found: $path\n',
        );
      }

      final decoded = jsonDecode(await file.readAsString());
      const ManifestSchema().validate(_asStringMap(decoded));

      return const CliCommandResult(
        exitCode: 0,
        stdout: 'Manifest valid\n',
      );
    } on ManifestParseException catch (error) {
      return CliCommandResult(
        exitCode: 1,
        stderr: '${error.code.value}: ${error.message}\n',
      );
    } on FormatException catch (error) {
      return CliCommandResult(
        exitCode: 1,
        stderr: 'MANIFEST_INVALID: ${error.message}\n',
      );
    }
  }

  Future<CliCommandResult> run(List<String> args) async {
    if (args.isEmpty || args.first == 'help') {
      return const CliCommandResult(
        exitCode: 0,
        stdout: 'Usage: flutter_app_updater manifest <generate|verify>\n',
      );
    }

    return switch (args.first) {
      'generate' => CliCommandResult(exitCode: 0, stdout: '${generate()}\n'),
      'verify' when args.length >= 2 => verify(args[1]),
      'verify' => const CliCommandResult(
          exitCode: 1,
          stderr: 'Usage: flutter_app_updater manifest verify <path>\n',
        ),
      _ => CliCommandResult(
          exitCode: 1,
          stderr: 'Unknown manifest command: ${args.first}\n',
        ),
    };
  }

  Map<String, Object?> _asStringMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Manifest root must be an object.');
    }

    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FormatException('Manifest keys must be strings.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }
}
