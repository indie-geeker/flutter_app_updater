# Migrating from v2 to v3

Version 3 is a deliberate redesign. It replaces dialog-driven update helpers
and loosely shaped server responses with a UI-free decision engine, typed
delivery actions, and an authenticated remote trust chain. There is no
compatibility facade: migrate the host integration and manifest together.

## Concept mapping

| v2 responsibility | v3 replacement |
| --- | --- |
| Legacy updater entry points such as `UpdateChecker` | `AppUpdater` |
| A single legacy update-information object | `UpdateCandidate`, `UpdatePolicy`, and ordered `UpdateAction` values |
| Package-owned update dialogs | Host UI driven by `checkAndPrepare()` |
| Implicit download or install methods | Explicit action selection followed by `performRecommended()`, `perform()`, or their streaming variants |
| A force-update boolean | `UpdatePolicyLevel.required` and optional `minSupportedVersion` |
| MD5 or an optional digest | Exact size plus required SHA-256 for every remote package or installer |
| Arbitrary server response fields | A host adapter that produces typed models, or the manifest v3 schema |
| Exceptions as normal control flow | Sealed check/preparation results and `UpdateActionResult` |

## Replace the entry point and move UI to the host

Before, an updater helper commonly fetched data, decided whether an update was
needed, and presented a dialog in one call. In v3, checking is inert:

```dart
final updater = AppUpdater.manifest(
  manifestUrl: Uri.parse('https://updates.example.com/manifest.json'),
  expectedAppId: 'com.example.app',
  installedVersion: installedVersion,
  installedBuildNumber: installedBuildNumber,
  platform: defaultTargetPlatform,
  architecture: runtimeArchitecture,
  channel: 'stable',
  signaturePolicy: ManifestSignaturePolicy.required(
    trustedPublicKeys: trustedManifestKeys,
  ),
);

final prepared = await updater.checkAndPrepare();
```

Render `PreparedUpdateAvailable`, `PreparedUpdateNotAvailable`, or
`PreparedUpdateCheckFailed` in your own dialog, sheet, page, or background
policy. A successful check does not open a store, download a file, or launch an
installer.

After the user or host policy confirms the selected delivery method:

```dart
if (prepared case PreparedUpdateAvailable()) {
  final result = await updater.performRecommended(prepared);
  if (!result.isSuccess) {
    reportUpdateFailure(result.code, result.message);
  }
}
```

Use `performRecommendedStream()` when the UI needs progress and cooperative
cancellation. Use `perform(action)` only for an action already present in the
prepared result; do not reconstruct untrusted actions from UI strings.

## Replace the legacy model

Each release is now an `UpdateCandidate` containing:

- semantic version and optional build number;
- channel, platform, and optional architecture;
- release notes and timestamp;
- an `UpdatePolicy`;
- one or more ordered `UpdateAction` delivery alternatives.

Action order is meaningful. After the host's distribution policy and executor
capabilities are applied, the first remaining action is recommended. Put the
preferred delivery path first and a fallback later.

A legacy force-update flag maps to:

```dart
const UpdatePolicy(level: UpdatePolicyLevel.required)
```

Alternatively, set `minSupportedVersion`. An installed version below that
floor is treated as required even when the general level is optional or
recommended. The package reports this decision through `isRequired`; the host
still owns blocking UI, accessibility, and recovery behavior.

## Migrate downloads and installation

Remote package and installer actions must provide all of:

- a trusted HTTPS URL;
- a positive exact byte size;
- a 64-character SHA-256 digest;
- a valid Ed25519-signed manifest envelope.

The migration is not a rename from MD5. Recompute release metadata from the
final published artifact, publish the exact size and SHA-256 together, then
sign the manifest envelope. If the artifact changes, regenerate both metadata
values and the signature.

Choose an explicit action:

- `DownloadPackageAction` downloads and verifies but does not install;
- `InstallPackageAction` is only for a trusted local path created by host
  code, never remote JSON;
- `DownloadAndInstallPackageAction` downloads a verified Android APK and
  requests installation;
- `OpenInstallerAction` downloads, verifies, and opens a supported desktop
  installer;
- `OpenStoreAction` and `OpenAndroidMarketAction` leave distribution to an
  official store or configured Android market.

Android installer handoff rechecks the file and verifies package identity and
signing lineage against the installed host. Installation permission remains an
explicit host opt-in.

## Adapt custom server responses

If the existing backend cannot emit manifest v3 immediately, keep its response
outside the package and write a host-owned adapter:

1. Fetch and authenticate the legacy response using host policy.
2. Validate every required field.
3. Convert it into `UpdateManifest`, `UpdateCandidate`, `UpdatePolicy`,
   and ordered `UpdateAction` values.
4. Pass it through `UpdateSource.staticManifest`.

A static source is a trusted typed boundary. It does not apply the remote
transport, application-identity, or envelope checks on your behalf, so the host
adapter owns equivalent authentication and validation. Prefer moving the
backend to the signed v3 format rather than keeping this bridge indefinitely.

## Choose a distribution path

For official-store delivery, publish store or Android-market actions and use
`UpdateDistributionPolicy.storeOnly` when the host must never self-update.
Store-only bare manifests may be allowed over HTTPS unless the host explicitly
requires signatures.

For self-hosted packages and installers, configure trusted Ed25519 public keys
and use a signed envelope. `UpdateDistributionPolicy.selfHostedOnly` can
exclude store actions; it does not relax signature, size, digest, URL, APK
identity, or signing-lineage checks.

## Handle structured outcomes

Do not wrap the normal v3 flow in a broad exception handler. Branch on
`UpdateCheckResult`, `UpdateFlowResult`, and `UpdateActionResult`. Their
`UpdateErrorCode` values are stable enough for analytics and recovery policy;
the accompanying message is for diagnostics or host UI.

Constructor misuse such as a blank `expectedAppId` throws `ArgumentError`.
Remote transport, signature, identity, manifest, selection, capability, and
action failures return structured results. This separation makes configuration
bugs visible during development without turning expected runtime failure into
unhandled exceptions.
