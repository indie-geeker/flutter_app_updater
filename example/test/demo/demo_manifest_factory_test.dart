import 'package:flutter/foundation.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';
import 'package:flutter_app_updater_example/demo/demo_manifest_factory.dart';
import 'package:flutter_app_updater_example/demo/demo_scenario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DemoManifestFactory', () {
    test('preserves primary then fallback action order', () {
      final scenario = DemoScenario.defaults().copyWith(
        policyLevel: UpdatePolicyLevel.required,
        delivery: DemoDelivery.androidDownloadAndInstall,
        fallbackDelivery: DemoDelivery.officialStore,
      );

      final release =
          const DemoManifestFactory().build(scenario).releases.single;

      expect(release.policy.level, UpdatePolicyLevel.required);
      expect(
        release.actions,
        [
          isA<DownloadAndInstallPackageAction>(),
          isA<OpenStoreAction>(),
        ],
      );
    });

    test('keeps runtime and release targets independent', () async {
      final scenario = DemoScenario.defaults().copyWith(
        runtimeArchitecture: 'arm64',
        runtimeChannel: 'stable',
        releaseArchitecture: 'x64',
        releaseChannel: 'beta',
      );

      final manifest = const DemoManifestFactory().build(scenario);
      final release = manifest.releases.single;

      expect(manifest.channel, 'beta');
      expect(release.architecture, 'x64');
      expect(release.channel, 'beta');
      expect(scenario.toSelector().architecture, 'arm64');
      expect(scenario.toSelector().channel, 'stable');
    });

    test('maps separate Android download install and combined actions', () {
      final cases = <DemoDelivery, Type>{
        DemoDelivery.androidDownload: DownloadPackageAction,
        DemoDelivery.androidInstall: InstallPackageAction,
        DemoDelivery.androidDownloadAndInstall: DownloadAndInstallPackageAction,
      };

      for (final MapEntry(key: delivery, value: type) in cases.entries) {
        final scenario = DemoScenario.defaults().copyWith(
          delivery: delivery,
          fallbackDelivery: null,
        );

        final action = const DemoManifestFactory()
            .build(scenario)
            .releases
            .single
            .actions
            .single;

        expect(action.runtimeType, type, reason: delivery.name);
      }
    });

    test('no-update scenario still exercises selector comparison', () async {
      final scenario = DemoScenario.defaults().copyWith(updateAvailable: false);
      final manifest = const DemoManifestFactory().build(scenario);
      final updater = AppUpdater(
        source: UpdateSource.staticManifest(manifest: manifest),
        selector: scenario.toSelector(),
        executors: const [],
      );

      expect(
        await updater.checkAndPrepare(),
        isA<PreparedUpdateNotAvailable>(),
      );
    });

    test('maps official stores for supported mobile and Apple platforms', () {
      final cases = <TargetPlatform, StoreKind>{
        TargetPlatform.android: StoreKind.googlePlay,
        TargetPlatform.iOS: StoreKind.appStore,
        TargetPlatform.macOS: StoreKind.macAppStore,
      };

      for (final MapEntry(key: platform, value: store) in cases.entries) {
        final scenario = DemoScenario.defaults().copyWith(
          platform: platform,
          runtimeArchitecture:
              platform == TargetPlatform.android ? 'arm64' : 'x64',
          releaseArchitecture:
              platform == TargetPlatform.android ? 'arm64' : 'x64',
          delivery: DemoDelivery.officialStore,
          fallbackDelivery: null,
        );

        final action = const DemoManifestFactory()
            .build(scenario)
            .releases
            .single
            .actions
            .single as OpenStoreAction;

        expect(action.store, store);
      }
    });

    test('maps a Chinese Android market action', () {
      final scenario = DemoScenario.defaults().copyWith(
        delivery: DemoDelivery.androidMarket,
        fallbackDelivery: null,
      );

      final action = const DemoManifestFactory()
          .build(scenario)
          .releases
          .single
          .actions
          .single as OpenAndroidMarketAction;

      expect(action.market, AndroidMarketKind.xiaomi);
    });

    test('maps platform-specific desktop installers', () {
      final macScenario = DemoScenario.defaults().copyWith(
        platform: TargetPlatform.macOS,
        runtimeArchitecture: 'arm64',
        releaseArchitecture: 'arm64',
        delivery: DemoDelivery.desktopInstaller,
        fallbackDelivery: null,
      );
      final windowsScenario = macScenario.copyWith(
        platform: TargetPlatform.windows,
        runtimeArchitecture: 'x64',
        releaseArchitecture: 'x64',
      );

      final macAction = const DemoManifestFactory()
          .build(macScenario)
          .releases
          .single
          .actions
          .single as OpenInstallerAction;
      final windowsAction = const DemoManifestFactory()
          .build(windowsScenario)
          .releases
          .single
          .actions
          .single as OpenInstallerAction;

      expect(macAction.installerType, InstallerType.dmg);
      expect(windowsAction.installerType, InstallerType.msix);
    });

    test('rejects a primary or fallback that contradicts the platform', () {
      final invalidPrimary = DemoScenario.defaults().copyWith(
        platform: TargetPlatform.iOS,
        delivery: DemoDelivery.androidDownload,
        fallbackDelivery: null,
      );
      final invalidFallback = DemoScenario.defaults().copyWith(
        fallbackDelivery: DemoDelivery.desktopInstaller,
      );

      expect(
        () => const DemoManifestFactory().build(invalidPrimary),
        throwsArgumentError,
      );
      expect(
        () => const DemoManifestFactory().build(invalidFallback),
        throwsArgumentError,
      );
    });
  });

  group('DemoScenario', () {
    test('reports all split Android delivery types', () {
      expect(
        DemoScenario.allowedDeliveries(TargetPlatform.android),
        containsAll([
          DemoDelivery.officialStore,
          DemoDelivery.androidMarket,
          DemoDelivery.androidDownload,
          DemoDelivery.androidInstall,
          DemoDelivery.androidDownloadAndInstall,
        ]),
      );
      expect(
        DemoScenario.allowedDeliveries(TargetPlatform.iOS),
        [DemoDelivery.officialStore],
      );
      expect(
        DemoScenario.allowedDeliveries(TargetPlatform.windows),
        [DemoDelivery.desktopInstaller],
      );
    });
  });
}
