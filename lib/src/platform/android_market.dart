import '../actions/update_action.dart';

/// Native package and URI template for one Android market.
class AndroidMarketDescriptor {
  /// Logical market identifier used by manifest actions.
  final AndroidMarketKind market;

  /// Android package name of the market application.
  final String marketPackageName;

  /// Deep-link template containing `{targetPackageName}`.
  final String uriTemplate;

  /// Trusted HTTPS fallback when the native market is unavailable.
  final Uri? fallbackUrl;

  /// Creates an Android market descriptor.
  const AndroidMarketDescriptor({
    required this.market,
    required this.marketPackageName,
    required this.uriTemplate,
    this.fallbackUrl,
  });

  /// Builds a percent-encoded deep link for [targetPackageName].
  Uri marketUriFor(String targetPackageName) {
    return Uri.parse(
      uriTemplate.replaceAll(
        '{targetPackageName}',
        Uri.encodeComponent(targetPackageName),
      ),
    );
  }
}
