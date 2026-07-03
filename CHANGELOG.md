## Unreleased

* **Breaking**: Redesign the public API around `AppUpdater`, `UpdateSource`, `UpdateCandidate`, `UpdatePolicy`, and `UpdateAction`.
* **Feature**: Add manifest v3 parsing, validation, and release selection.
* **Feature**: Add official store actions for App Store, Mac App Store, Google Play fallback URLs, and a Play in-app update entry point.
* **Feature**: Add Chinese Android market descriptors and Android market opening support.
* **Feature**: Add SHA-256 verified package downloads with resume safety metadata.
* **Feature**: Add desktop installer actions for verified Windows and macOS installers.
* **Documentation**: Rewrite README and example around the v3 action model.

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
