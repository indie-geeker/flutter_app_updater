import 'package:pub_semver/pub_semver.dart';

/// Validated package metadata associated with one release tag.
final class ReleaseMetadata {
  /// The exact Git tag, including its leading `v`.
  final String tag;

  /// The package version shared by the tag and pubspec.
  final Version version;

  const ReleaseMetadata._({required this.tag, required this.version});

  /// Whether this release uses a SemVer prerelease suffix.
  bool get isPrerelease => version.isPreRelease;

  /// Validates an exact tag, pubspec version, and CHANGELOG heading.
  factory ReleaseMetadata.fromContents({
    required String tag,
    required String pubspec,
    required String changelog,
  }) {
    final tagPattern = RegExp(
      r'^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
      r'(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
    );
    final tagMatch = tagPattern.firstMatch(tag);
    if (tagMatch == null) {
      throw ReleaseMetadataException(
        'Release tag must be v<SemVer> without build metadata: $tag.',
      );
    }

    final versionMatch = RegExp(
      r'^version:\s*([^\s#]+)\s*(?:#.*)?$',
      multiLine: true,
    ).firstMatch(pubspec);
    if (versionMatch == null) {
      throw const ReleaseMetadataException(
        'pubspec.yaml must contain exactly one parseable version field.',
      );
    }
    final versionText = versionMatch.group(1)!;
    if (versionText.contains('+')) {
      throw const ReleaseMetadataException(
        'Release versions with build metadata are not supported.',
      );
    }

    final Version version;
    final Version tagVersion;
    try {
      version = Version.parse(versionText);
      tagVersion = Version.parse(tag.substring(1));
    } on FormatException catch (error) {
      throw ReleaseMetadataException('Invalid release version: $error');
    }
    if (tagVersion != version || tag != 'v$version') {
      throw ReleaseMetadataException(
        'Tag $tag does not match pubspec version $version.',
      );
    }

    final heading = RegExp(
      '^##\\s+\\[?${RegExp.escape(version.toString())}\\]?'
      r'(?:\s+-[^\n]*)?\s*$',
      multiLine: true,
    );
    if (!heading.hasMatch(changelog)) {
      throw ReleaseMetadataException(
        'CHANGELOG.md requires a heading for version $version.',
      );
    }

    return ReleaseMetadata._(tag: tag, version: version);
  }
}

/// A release tag, package version, or changelog provenance failure.
final class ReleaseMetadataException implements Exception {
  /// A human-readable explanation of the invalid release metadata.
  final String message;

  /// Creates a release metadata validation failure.
  const ReleaseMetadataException(this.message);

  @override
  String toString() => message;
}
