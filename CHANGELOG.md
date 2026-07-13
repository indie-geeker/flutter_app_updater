## Unreleased

* **Feature**: Add an advanced Android-only API for one persistent, user-visible APK download with durable status, progress observation, explicit resume, cancel, and removal.
* **Reliability**: Add native checkpoint recovery, strict HTTP Range and strong-validator handling, byte/disk limits, SHA-256 verification, and process-start reconciliation.
* **Android**: Use a host-opted-in visible foreground service started through the API-appropriate service entry point on API 21-33, and user-initiated data transfer jobs on API 34+, with visible retry and cancel actions.
* **Safety**: Keep installation separate from download completion and revalidate file size, hash, package identity, and signing lineage before returning an install action.
* **Testing**: Add Android unit/lint/merged-manifest CI gates plus a controllable protocol harness and an evidence template for future real-device qualification.
* **Documentation**: Document host-owned manifest and notification setup, server requirements, Play policy implications, and force-stop, reboot, and OEM execution limits.

## 3.0.0 - 2026-07-10

* **Breaking**: Redesign the public API around `AppUpdater`, `UpdateSource`, `UpdateCandidate`, `UpdatePolicy`, and `UpdateAction`.
* **Breaking**: Make package and installer hashes optional; hashes are verified only when supplied.
* **Feature**: Add package install and download-then-install actions for Android self-hosted APK flows.
* **Feature**: Add `AppUpdater.manifest`, `checkAndPrepare`, and `performRecommended` as the default UI-free integration flow.
* **Feature**: Add manifest v3 parsing, validation, and release selection.
* **Feature**: Add official store actions for App Store, Mac App Store, Google Play fallback URLs, and a Play in-app update entry point.
* **Feature**: Add Chinese Android market descriptors and Android market opening support.
* **Feature**: Add SHA-256 verified package downloads with resume safety metadata.
* **Feature**: Add desktop installer actions for verified Windows and macOS installers.
* **Documentation**: Rewrite README and example around the v3 action model.
* **Safety**: Make Android package-install permission opt-in and exclude machine-local platform configuration from published archives.
* **Safety**: Bind manifests to an expected application ID and validate release versions, artifact sizes, URL schemes, response limits, and download limits.
* **Reliability**: Add bounded manifest retries/timeouts plus resumable download retries, request/idle timeouts, active cancellation, concurrent-target protection, progress events, and partial-file cleanup.
* **Example**: Add a network-free preview executor and an explicit remote mode covering policy, progress, cancellation, and structured failures.
* **Release**: Add pub.dev OIDC publishing, Android/iOS/macOS/Windows CI builds, enforced coverage floors, dependency updates, and open-source governance files.

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
