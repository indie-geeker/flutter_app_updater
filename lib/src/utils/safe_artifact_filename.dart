/// Returns a portable artifact filename from [uri], or `null` if unsafe.
///
/// The result excludes path separators, traversal syntax, Windows reserved
/// names, trailing spaces/dots, and extensions other than [expectedExtension].
String? safeArtifactFilename(
  Uri uri, {
  required String expectedExtension,
}) {
  final segments = uri.pathSegments;
  final fileName = segments.isEmpty ? '' : segments.last;
  if (fileName.isEmpty ||
      fileName.length > 255 ||
      fileName.endsWith('.') ||
      fileName.endsWith(' ') ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(fileName)) {
    return null;
  }

  final baseName = fileName.split('.').first.toUpperCase();
  if (_windowsReservedNames.contains(baseName) ||
      RegExp(r'^(COM|LPT)[1-9]$').hasMatch(baseName)) {
    return null;
  }

  final dot = fileName.lastIndexOf('.');
  if (dot < 0) {
    return '$fileName.$expectedExtension';
  }
  final actualExtension = fileName.substring(dot + 1);
  if (actualExtension.toLowerCase() != expectedExtension.toLowerCase()) {
    return null;
  }
  return fileName;
}

const _windowsReservedNames = <String>{
  'CON',
  'PRN',
  'AUX',
  'NUL',
};
