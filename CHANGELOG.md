## 3.0.0 - 2026-07-15

* **Breaking**: Redesign the public API around `AppUpdater`, `UpdateSource`, `UpdateCandidate`, `UpdatePolicy`, and `UpdateAction`.
* **Breaking**: Raise the minimum supported Flutter SDK to 3.29.0.
* **Breaking**: Remove unfinished platform surfaces and require strict architecture matching for architecture-specific releases.
* **Breaking**: Require positive exact sizes and SHA-256 digests for remote packages and installers; forbid remote local-path installation actions.
* **Breaking / Security**: Require Android durable downloads to start from a credential-free stable entry URL without userinfo, query, or fragment; short-lived signed URLs are accepted only as in-memory HTTPS redirect targets and are never persisted.
* **Breaking / Storage**: Reset pre-release single-root background tasks and artifacts while separating durable state into `noBackupFilesDir` and FileProvider-backed APK data into `filesDir`.
* **Feature**: Add package install and download-then-install actions for Android self-hosted APK flows.
* **Feature**: Add `AppUpdater.manifest`, `checkAndPrepare`, and `performRecommended` as the default UI-free integration flow.
* **Feature**: Add manifest v3 parsing, application identity binding, validation, ordered release selection, host distribution policy, and executor capability filtering.
* **Feature**: Add official store actions for App Store, Mac App Store, and Google Play URLs.
* **Feature**: Add Chinese Android market descriptors and Android market opening support.
* **Security**: Require trusted HTTPS transport and bounded redirects, authenticate self-hosted manifests with versioned Ed25519 envelopes, and support two-key rotation through `keyId`.
* **Security**: Enforce strict manifest and signed-envelope allowlists, reject unknown fields, validate non-negative decimal `buildNumber` values, and require `minSupportedVersion` not to exceed its release version.
* **Security**: Add native APK identity and signing-lineage verification before every Android installer handoff.
* **Feature**: Add SHA-256 verified downloads with private URL-fingerprint checkpoint metadata and cross-process writer ownership.
* **Feature**: Add desktop installer actions for verified Windows and macOS installers.
* **Feature**: Add an advanced Android-only API for one persistent, user-visible APK download with durable status, progress observation, explicit resume, cancel, and removal.
* **Reliability**: Add native checkpoint recovery, strict HTTP Range and strong-validator handling, byte/disk limits, bounded retries, and process-start reconciliation.
* **Android**: Use a host-opted-in visible foreground service on API 21-33 and user-initiated data transfer jobs on API 34+, with visible retry and cancel actions.
* **Example**: Add a network-free simulator with ordered actions, cancellation, failure recovery, and a separately enabled production integration using the signed-manifest path.
* **Documentation**: Add complete public Dartdoc, a v2-to-v3 migration guide, and a remote update security model.
* **Safety**: Make Android package-install permission opt-in and exclude machine-local platform configuration from published archives.
* **Release**: Unify CI and publishing behind one full quality gate covering minimum/stable Flutter, root/example checks, coverage, docs, clean archive validation, native tests, and platform builds.
* **Release**: Add tag/version/CHANGELOG/main-ancestry release provenance checks, immutable workflow action pins, download checksums, Dependabot coverage, and pub.dev OIDC publishing.
* **Tooling**: Repair the pure-Dart manifest CLI so `verify` uses the production parser and remote-action policy, and add a Flutter-engine-free executable smoke gate.

## 2.1.0

* **Feature**: Added configurable retry strategy for downloads with exponential backoff.
* **Feature**: Added comprehensive logging system with `UpdateLogger`.
* **Improvement**: Enhanced HTTP client with better error handling and retry logic.
* **Improvement**: Improved download robustness with automatic retry on network failures.
* **Test**: Added unit coverage for `UpdateChecker`, `UpdateInfo`, `RetryStrategy`, and `VersionComparator`.
* **Improvement**: Enhanced Android plugin implementation.
* **Documentation**: Updated README with retry strategy and logging configuration examples.

## 2.0.0

* **Breaking**: Complete rebuild of the plugin architecture.
* **Feature**: Added OpenHarmony platform support.
* **Feature**: Zero third-party dependencies using Flutter native HTTP only.
* **Feature**: Fully customizable update dialogs and API response formats.
* **Feature**: Support for forced and optional updates with download progress.
* **Improvement**: Modular architecture with clear separation of concerns.
* **Improvement**: Enhanced example app with better demonstration of features.
* **Documentation**: Comprehensive README with usage examples and customization guide.
