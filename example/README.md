# Flutter App Updater Example

The example is a configurable **Update Simulator**. It models how an
application checks, presents, downloads, cancels, retries, and completes an
update without tying the package to a specific product UI.

Version selection, build-number comparison, target matching,
minimum-supported-version policy, ordered action recommendation, structured
results, progress, cancellation, and retry reuse the real
`flutter_app_updater` public contracts.

## No external side effects

The simulator builds an in-memory v3 manifest and injects a deterministic
streaming executor. Running it does not:

- request a remote manifest
- open an application store or Android market
- download or write a file
- request installation permission
- start an APK or desktop installer

Reserved `.invalid` URLs make accidental external execution fail closed.
The simulator does not imitate process death, JobScheduler, foreground-service
lifecycle, force-stop, reboot, or OEM background restrictions.

## Configure a scenario

The page is divided into three sections:

1. **Installed application** — version, build number, platform, runtime
   architecture, and runtime channel.
2. **Available release** — whether an update exists, independent release
   architecture/channel, required-update policy, minimum supported version,
   primary delivery, and optional fallback delivery.
3. **Simulation behavior** — transfer size, duration, action-specific terminal
   outcome, and whether retry succeeds.

Delivery choices follow the selected platform. Android exposes independent
download-only, trusted-local-install-only, and download-then-install actions in
addition to official stores and Chinese Android markets. iOS uses the App
Store. macOS supports the Mac App Store or a desktop installer, while Windows
uses a desktop installer.

The generated manifest preserves primary-then-fallback order. The update
decision displays that order and marks the first supported action as the
recommendation. Runtime and release channel/architecture fields are separate so
the real selector's fail-closed mismatch behavior is visible.

## Observe the flow

Select **Check for update** to run the scenario:

- an equal version/build produces an up-to-date result;
- channel and architecture mismatches explain why no release was selected;
- a recommended update can be deferred;
- a required update blocks barrier and back-button dismissal;
- transfer events update progress and byte counts;
- cancellation returns `ACTION_CANCELED`;
- configured failures display their public `UpdateErrorCode` and recovery
  action; hash mismatch is offered only for download-related actions, and
  install permission only for installation actions;
- **Retry succeeds** deliberately fails the first attempt and proves that the
  same executor instance recovers on the second attempt;
- installation permission recovery is visibly simulated and changes no system
  setting.

The required-update dialog includes a clearly labeled **Reset simulation**
escape. That control exists only so the example cannot trap the person testing
it; a real host application decides its own required-update escape policy.

## Opt-in production integration

The **Production** tab is disabled by default. When explicitly enabled, it uses
runtime package metadata and the package's real signed-manifest path: fetch,
Ed25519 verification, parse, application-identity binding, release selection,
and preparation. A check never executes an action. A separate confirmation
shows the action type, destination host, package or installer type, exact size,
SHA-256 digest, and distribution policy before it can call the recommended
executor.

Supply configuration at build time. Public verification keys are safe to embed;
never put a signing seed or private key in `--dart-define`, source control, or the
application binary.

```bash
cd example
flutter run \
  --dart-define=ENABLE_PRODUCTION_UPDATE_EXAMPLE=true \
  --dart-define=UPDATE_MANIFEST_URL=https://updates.example.com/manifest.json \
  --dart-define=UPDATE_EXPECTED_APP_ID=com.example.app \
  --dart-define=UPDATE_CHANNEL=stable \
  --dart-define=UPDATE_ARCHITECTURE=arm64 \
  --dart-define='UPDATE_MANIFEST_PUBLIC_KEYS={"release-2026-01":"<base64-public-key>"}'
```

All enabled configurations require an absolute HTTPS manifest URL, an exact
runtime application ID, and at least one raw 32-byte Ed25519 public key encoded
as Base64. Invalid configuration is rendered as a structured
`CONFIGURATION_INVALID` result instead of escaping the widget tree.

## Package and example boundary

The package remains UI-free. Both example presentations, their controllers,
generated data, and the simulated executor live entirely under `example/lib/`.
Production applications should provide their own presentation and choose
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

The example Android manifest opts into the permissions, services, and receiver
required by the advanced Android-only background API. This is test-host setup,
not a permission or component automatically added by the plugin.

Run the native plugin automation from `example/android`:

```bash
../../android/gradlew :flutter_app_updater:testDebugUnitTest :flutter_app_updater:lintDebug :app:processDebugMainManifest
```
