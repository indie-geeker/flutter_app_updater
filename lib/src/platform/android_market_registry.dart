import '../actions/update_action.dart';
import 'android_market.dart';

class AndroidMarketRegistry {
  static final descriptors = <AndroidMarketDescriptor>[
    AndroidMarketDescriptor(
      market: AndroidMarketKind.huawei,
      marketPackageName: 'com.huawei.appmarket',
      uriTemplate: 'appmarket://details?id={targetPackageName}',
      fallbackUrl: Uri.https('appgallery.huawei.com', '/'),
    ),
    AndroidMarketDescriptor(
      market: AndroidMarketKind.honor,
      marketPackageName: 'com.hihonor.appmarket',
      uriTemplate: 'market://details?id={targetPackageName}',
      fallbackUrl: Uri.https('www.hihonor.com', '/global/club/hihonor-apps/'),
    ),
    AndroidMarketDescriptor(
      market: AndroidMarketKind.xiaomi,
      marketPackageName: 'com.xiaomi.market',
      uriTemplate: 'market://details?id={targetPackageName}',
      fallbackUrl: Uri.https('app.mi.com', '/'),
    ),
    AndroidMarketDescriptor(
      market: AndroidMarketKind.oppo,
      marketPackageName: 'com.oppo.market',
      uriTemplate: 'market://details?id={targetPackageName}',
      fallbackUrl: Uri.https('store.oppomobile.com', '/'),
    ),
    AndroidMarketDescriptor(
      market: AndroidMarketKind.vivo,
      marketPackageName: 'com.bbk.appstore',
      uriTemplate: 'market://details?id={targetPackageName}',
      fallbackUrl: Uri.https('info.appstore.vivo.com.cn', '/'),
    ),
    AndroidMarketDescriptor(
      market: AndroidMarketKind.meizu,
      marketPackageName: 'com.meizu.mstore',
      uriTemplate: 'market://details?id={targetPackageName}',
      fallbackUrl: Uri.https('app.meizu.com', '/'),
    ),
    AndroidMarketDescriptor(
      market: AndroidMarketKind.tencentMyApp,
      marketPackageName: 'com.tencent.android.qqdownloader',
      uriTemplate: 'market://details?id={targetPackageName}',
      fallbackUrl: Uri.https('sj.qq.com', '/appdetail/{targetPackageName}'),
    ),
    const AndroidMarketDescriptor(
      market: AndroidMarketKind.generic,
      marketPackageName: '',
      uriTemplate: 'market://details?id={targetPackageName}',
    ),
  ];

  const AndroidMarketRegistry._();

  static AndroidMarketDescriptor? descriptorFor(AndroidMarketKind market) {
    for (final descriptor in descriptors) {
      if (descriptor.market == market) {
        return descriptor;
      }
    }
    return null;
  }

  static AndroidMarketDescriptor requireDescriptor(AndroidMarketKind market) {
    final descriptor = descriptorFor(market);
    if (descriptor == null) {
      throw ArgumentError.value(market, 'market', 'Unsupported Android market');
    }
    return descriptor;
  }

  static Uri? fallbackUrlFor(OpenAndroidMarketAction action) {
    if (action.fallbackUrl != null) {
      return action.fallbackUrl;
    }

    return switch (action.market) {
      AndroidMarketKind.xiaomi => Uri.https(
          'app.mi.com',
          '/details',
          {'id': action.targetPackageName},
        ),
      AndroidMarketKind.tencentMyApp => Uri.https(
          'sj.qq.com',
          '/appdetail/${action.targetPackageName}',
        ),
      _ => requireDescriptor(action.market).fallbackUrl,
    };
  }
}
