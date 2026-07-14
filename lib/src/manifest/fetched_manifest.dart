import 'dart:typed_data';

/// Exact response data returned by the manifest transport boundary.
///
/// Keeping bytes undecoded is required because signed envelopes authenticate
/// the precise payload received from the network.
final class FetchedManifest {
  /// Exact response body bytes.
  final Uint8List bodyBytes;

  /// Final trusted URI after validated redirects.
  final Uri finalUri;

  /// Response headers normalized by the fetcher.
  final Map<String, String> responseHeaders;

  /// Creates an immutable fetched-manifest response.
  const FetchedManifest({
    required this.bodyBytes,
    required this.finalUri,
    required this.responseHeaders,
  });
}
