import 'dart:io';

bool isLoopbackHost(String host) {
  final normalizedHost = host.toLowerCase();
  if (normalizedHost == 'localhost') {
    return true;
  }
  return InternetAddress.tryParse(normalizedHost)?.isLoopback ?? false;
}

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
