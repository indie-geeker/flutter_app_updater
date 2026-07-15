import 'dart:convert';
import 'dart:io';

import '../manifest/manifest_document_parser.dart';
import '../manifest/remote_action_policy.dart';
import '../manifest/manifest_signature.dart';
import 'cli_command_result.dart';

/// Generates, validates, and signs v3 update manifests.
class ManifestCommand {
  static const _privateKeyEnvironment =
      'FLUTTER_APP_UPDATER_ED25519_PRIVATE_KEY_BASE64';

  /// Environment used to read the private signing seed.
  final Map<String, String>? environment;

  /// Injectable clock used to issue deterministic envelope timestamps.
  final DateTime Function()? clock;

  /// Creates a manifest command with injectable release boundaries.
  const ManifestCommand({
    this.environment,
    this.clock,
  });

  /// Returns an indented example v3 manifest.
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
              'type': 'downloadAndInstallPackage',
              'packageUrl': 'https://example.com/app.apk',
              'packageType': 'apk',
              'packageSizeBytes': 25600000,
              'sha256': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
                  'aaaaaaaaaaaaaaaa',
            },
          ],
        },
      ],
    });
  }

  /// Validates the manifest at [path] with runtime schema and remote policy.
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
      final document =
          const ManifestDocumentParser().parse(_asStringMap(decoded));
      const RemoteActionPolicy().validateDocument(document);

      return const CliCommandResult(
        exitCode: 0,
        stdout: 'Manifest valid\n',
      );
    } on ManifestParseException catch (error) {
      return CliCommandResult(
        exitCode: 1,
        stderr: '${error.code.value}: ${error.message}\n',
      );
    } on RemoteManifestPolicyException catch (error) {
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

  /// Dispatches generate, verify, or sign subcommands.
  Future<CliCommandResult> run(List<String> args) async {
    if (args.isEmpty || args.first == 'help') {
      return const CliCommandResult(
        exitCode: 0,
        stdout: 'Usage: flutter_app_updater manifest <generate|verify|sign>\n',
      );
    }

    return switch (args.first) {
      'generate' => CliCommandResult(exitCode: 0, stdout: '${generate()}\n'),
      'verify' when args.length >= 2 => verify(args[1]),
      'verify' => const CliCommandResult(
          exitCode: 1,
          stderr: 'Usage: flutter_app_updater manifest verify <path>\n',
        ),
      'sign' => _sign(args.skip(1).toList()),
      _ => CliCommandResult(
          exitCode: 1,
          stderr: 'Unknown manifest command: ${args.first}\n',
        ),
    };
  }

  Future<CliCommandResult> _sign(List<String> args) async {
    const usage = 'Usage: flutter_app_updater manifest sign <path> '
        '--key-id <id> --expires-in <hours>h --output <path>\n';
    if (args.isEmpty) {
      return const CliCommandResult(exitCode: 1, stderr: usage);
    }

    final inputPath = args.first;
    String? keyId;
    String? expiresIn;
    String? outputPath;
    for (var index = 1; index < args.length; index += 1) {
      final option = args[index];
      if (index + 1 >= args.length) {
        return const CliCommandResult(exitCode: 1, stderr: usage);
      }
      final value = args[++index];
      switch (option) {
        case '--key-id':
          keyId = value;
        case '--expires-in':
          expiresIn = value;
        case '--output':
          outputPath = value;
        default:
          return CliCommandResult(
            exitCode: 1,
            stderr: 'Unknown manifest sign option: $option\n',
          );
      }
    }
    if (keyId == null ||
        keyId.trim().isEmpty ||
        expiresIn == null ||
        outputPath == null ||
        outputPath.trim().isEmpty) {
      return const CliCommandResult(exitCode: 1, stderr: usage);
    }

    final durationMatch = RegExp(r'^([1-9][0-9]*)h$').firstMatch(expiresIn);
    final hours = durationMatch == null
        ? null
        : int.tryParse(durationMatch.group(1) ?? '');
    if (hours == null || hours > 24 * 7) {
      return const CliCommandResult(
        exitCode: 1,
        stderr: '--expires-in must be between 1h and 168h.\n',
      );
    }

    final privateKey =
        (environment ?? Platform.environment)[_privateKeyEnvironment];
    if (privateKey == null || privateKey.trim().isEmpty) {
      return const CliCommandResult(
        exitCode: 1,
        stderr: 'Missing $_privateKeyEnvironment.\n',
      );
    }

    try {
      final input = File(inputPath);
      if (!await input.exists()) {
        return CliCommandResult(
          exitCode: 1,
          stderr: 'Manifest file not found: $inputPath\n',
        );
      }
      final issuedAt = (clock ?? DateTime.now)().toUtc();
      final envelope = await ManifestSignatureSigner().sign(
        payloadBytes: await input.readAsBytes(),
        keyId: keyId,
        issuedAt: issuedAt.toIso8601String(),
        expiresAt: issuedAt.add(Duration(hours: hours)).toIso8601String(),
        privateKeyBase64: privateKey,
      );
      await File(outputPath).writeAsBytes(envelope, flush: true);
      return CliCommandResult(
        exitCode: 0,
        stdout: 'Signed manifest written to $outputPath\n',
      );
    } on FormatException catch (error) {
      return CliCommandResult(
        exitCode: 1,
        stderr: 'MANIFEST_SIGNATURE_INVALID: ${error.message}\n',
      );
    } on FileSystemException catch (error) {
      return CliCommandResult(
        exitCode: 1,
        stderr: 'Failed to sign manifest: ${error.message}\n',
      );
    }
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
