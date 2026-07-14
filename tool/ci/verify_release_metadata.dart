import 'dart:io';

import 'release_metadata.dart';

void main(List<String> arguments) {
  try {
    final tag = _requiredOption(arguments, '--tag');
    final pubspecPath = _option(arguments, '--pubspec') ?? 'pubspec.yaml';
    final changelogPath = _option(arguments, '--changelog') ?? 'CHANGELOG.md';
    final metadata = ReleaseMetadata.fromContents(
      tag: tag,
      pubspec: File(pubspecPath).readAsStringSync(),
      changelog: File(changelogPath).readAsStringSync(),
    );
    stdout.writeln(
      'Verified ${metadata.tag} for package version ${metadata.version}.',
    );
  } on ReleaseMetadataException catch (error) {
    stderr.writeln('Release metadata verification failed: ${error.message}');
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln('Release metadata file error: ${error.message}');
    exitCode = 66;
  } on ArgumentError catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  }
}

String _requiredOption(List<String> arguments, String name) {
  final value = _option(arguments, name);
  if (value == null || value.trim().isEmpty) {
    throw ArgumentError('Usage: dart run tool/ci/verify_release_metadata.dart '
        '--tag <release-tag> [--pubspec <path>] [--changelog <path>]');
  }
  return value;
}

String? _option(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index == -1) {
    return null;
  }
  if (index + 1 >= arguments.length || arguments[index + 1].startsWith('--')) {
    throw ArgumentError('Missing value for $name.');
  }
  return arguments[index + 1];
}
