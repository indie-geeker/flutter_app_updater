import 'dart:convert';
import 'dart:io';

import '../models/update_error_code.dart';

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
      _verifyManifest(_asStringMap(decoded));

      return const CliCommandResult(
        exitCode: 0,
        stdout: 'Manifest valid\n',
      );
    } on _ManifestCliException catch (error) {
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

  void _verifyManifest(Map<String, Object?> manifest) {
    _rejectLegacyFields(manifest);

    if (manifest['schemaVersion'] != 3) {
      throw const _ManifestCliException(
        UpdateErrorCode.unsupportedSchemaVersion,
        'Only schemaVersion 3 is supported.',
      );
    }

    _requireString(manifest, 'appId');
    _requireString(manifest, 'channel');

    final releases = manifest['releases'];
    if (releases is! List) {
      throw const _ManifestCliException(
        UpdateErrorCode.missingRequiredField,
        'releases is required.',
      );
    }

    for (final release in releases) {
      final releaseMap = _asStringMap(release);
      _requireString(releaseMap, 'version');
      _requireString(releaseMap, 'platform');
      _requireString(releaseMap, 'releaseNotes');
      final actions = releaseMap['actions'];
      if (actions is! List || actions.isEmpty) {
        throw const _ManifestCliException(
          UpdateErrorCode.missingRequiredField,
          'actions is required.',
        );
      }

      for (final action in actions) {
        _verifyAction(_asStringMap(action));
      }
    }
  }

  void _verifyAction(Map<String, Object?> action) {
    final type = _requireString(action, 'type');
    switch (type) {
      case 'openStore':
        _requireString(action, 'storeUrl');
      case 'openAndroidMarket':
        _requireString(action, 'targetPackageName');
      case 'playInAppUpdate':
        _requireString(action, 'mode');
      case 'downloadPackage':
        _requireString(action, 'packageUrl');
        _requireString(action, 'packageType');
        _requireString(action, 'sha256');
      case 'openInstaller':
        _requireString(action, 'installerUrl');
        _requireString(action, 'installerType');
        _requireString(action, 'sha256');
      default:
        throw _ManifestCliException(
          UpdateErrorCode.unsupportedActionType,
          'Unsupported action type: $type.',
        );
    }
  }

  void _rejectLegacyFields(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key == 'downloadUrl' ||
            entry.key == 'artifactUri' ||
            entry.key == 'md5') {
          throw _ManifestCliException(
            UpdateErrorCode.legacyFieldNotSupported,
            '${entry.key} is not supported.',
          );
        }
        _rejectLegacyFields(entry.value);
      }
    } else if (value is Iterable) {
      for (final item in value) {
        _rejectLegacyFields(item);
      }
    }
  }

  String _requireString(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw _ManifestCliException(
      UpdateErrorCode.missingRequiredField,
      '$field is required.',
    );
  }
}

class _ManifestCliException implements Exception {
  final UpdateErrorCode code;
  final String message;

  const _ManifestCliException(this.code, this.message);
}
