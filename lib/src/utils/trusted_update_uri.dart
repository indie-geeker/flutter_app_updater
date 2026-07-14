import 'dart:io';

/// Whether [host] names a loopback address or `localhost`.
bool isLoopbackHost(String host) {
  final normalizedHost = host.toLowerCase();
  if (normalizedHost == 'localhost') {
    return true;
  }
  return InternetAddress.tryParse(normalizedHost)?.isLoopback ?? false;
}

/// Requires an absolute HTTPS URI without embedded user information.
///
/// Plain HTTP is accepted only for loopback hosts when
/// [allowInsecureLoopback] is explicitly enabled. Throws [ArgumentError] with
/// [field] as the invalid argument name when the URI is untrusted.
void requireTrustedHttpsUri(
  Uri uri, {
  required bool allowInsecureLoopback,
  required String field,
}) {
  if (!uri.hasAuthority || uri.host.isEmpty) {
    throw ArgumentError.value(uri, field, 'must be an absolute URL');
  }
  if (uri.userInfo.isNotEmpty) {
    throw ArgumentError.value(uri, field, 'must not contain user information');
  }
  if (uri.scheme.toLowerCase() == 'https') {
    return;
  }
  if (uri.scheme.toLowerCase() == 'http' &&
      allowInsecureLoopback &&
      isLoopbackHost(uri.host)) {
    return;
  }
  throw ArgumentError.value(
    uri,
    field,
    'must use HTTPS; insecure HTTP is allowed only for explicitly enabled '
    'loopback development URLs',
  );
}

/// Whether two URIs have equal scheme, host, and effective port.
bool isSameOrigin(Uri left, Uri right) {
  return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
      left.host.toLowerCase() == right.host.toLowerCase() &&
      _effectivePort(left) == _effectivePort(right);
}

int _effectivePort(Uri uri) {
  if (uri.hasPort) {
    return uri.port;
  }
  return switch (uri.scheme.toLowerCase()) {
    'https' => 443,
    'http' => 80,
    _ => 0,
  };
}
