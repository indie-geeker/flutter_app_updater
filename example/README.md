# Flutter App Updater Example

The example is a configurable **Update Simulator**. It models how an
application checks, presents, downloads, cancels, retries, and completes an
update without tying the package to a specific product UI.

Version selection, build-number comparison, minimum-supported-version policy,
recommended action selection, structured results, progress, and cancellation
use the real `flutter_app_updater` public contracts.

## No external side effects

The simulator builds an in-memory v3 manifest and injects a deterministic
streaming executor. Running it does not:

- request a remote manifest
- open an application store or Android market
- download or write a file
- request installation permission
- start an APK or desktop installer

Reserved `.invalid` URLs make accidental external execution fail closed.

## Configure a scenario

The page is divided into three sections:

1. **Installed application** — version, build number, platform, architecture,
   and channel.
2. **Available release** — whether an update exists, release metadata,
   required-update policy, minimum supported version, and delivery method.
3. **Simulation behavior** — transfer size, duration, and terminal outcome.

Delivery choices follow the selected platform. Android can simulate an
official store, a Chinese Android market, or APK download and installation.
iOS uses the App Store. macOS supports the Mac App Store or a desktop
installer, while Windows uses a desktop installer.

## Observe the flow

Select **Check for update** to run the scenario:

- an equal version/build produces an up-to-date result;
- a recommended update can be deferred;
- a required update blocks barrier and back-button dismissal;
- transfer events update progress and byte counts;
- cancellation returns `ACTION_CANCELED`;
- configured failures display their public `UpdateErrorCode` and recovery
  action;
- installation permission recovery is visibly simulated and changes no system
  setting.

The required-update dialog includes a clearly labeled **Reset simulation**
escape. That control exists only so the example cannot trap the person testing
it; a real host application decides its own required-update escape policy.

## Package and example boundary

The package remains UI-free. The form, dialogs, controller, generated data, and
simulated executor live entirely under `example/lib/`. Production applications
should provide their own presentation and use real manifest and platform
executors appropriate to their distribution channel.

## Run and verify

From the package root:

```bash
cd example
flutter pub get
flutter run
flutter analyze --no-pub
flutter test --no-pub
```

The integration test keeps a native method-channel smoke check and verifies
that the simulator launches. Run it on a configured device or simulator:

```bash
flutter test integration_test/plugin_integration_test.dart
```
