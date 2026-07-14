import 'dart:typed_data';

final class FetchedManifest {
  final Uint8List bodyBytes;
  final Uri finalUri;
  final Map<String, String> responseHeaders;

  const FetchedManifest({
    required this.bodyBytes,
    required this.finalUri,
    required this.responseHeaders,
  });
}
