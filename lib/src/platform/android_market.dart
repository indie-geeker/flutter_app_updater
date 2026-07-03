import '../actions/update_action.dart';

class AndroidMarketDescriptor {
  final AndroidMarketKind market;
  final String marketPackageName;
  final String uriTemplate;
  final Uri? fallbackUrl;

  const AndroidMarketDescriptor({
    required this.market,
    required this.marketPackageName,
    required this.uriTemplate,
    this.fallbackUrl,
  });

  Uri marketUriFor(String targetPackageName) {
    return Uri.parse(
      uriTemplate.replaceAll(
        '{targetPackageName}',
        Uri.encodeComponent(targetPackageName),
      ),
    );
  }
}
