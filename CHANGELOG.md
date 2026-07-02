## Unreleased

* **Fix**: Removed Android plugin build dependency on a hard-coded Flutter engine jar path.
* **Fix**: Use app version name/code for automatic current-version detection instead of platform OS version.
* **Fix**: Distinguish update-check failures from "no update" with `UpdateCheckResult`.
* **Fix**: Validate required update response fields and unsupported version formats.
* **Fix**: Prevent retryable download failures from completing the download future too early.
* **Improvement**: Stream MD5 verification to avoid loading large APK files fully into memory.
* **Improvement**: Export documented public integration types from the main library.
* **Improvement**: Add Android install permission error reporting for Android 8.0+.
* **Documentation**: Reworked README with platform support, error codes, and copyable examples.

## 2.1.0

* **Feature**: Added configurable retry strategy for downloads with exponential backoff
  * New `RetryStrategy` class with presets: `fast`, `standard`, `patient`, and `disabled`
  * Support for custom retry configuration (max attempts, delays, backoff factor, jitter)
* **Feature**: Added comprehensive logging system with `UpdateLogger`
  * Configurable log levels: `none`, `error`, `warning`, `info`, `debug`
  * Tagged logging for better debugging experience
* **Improvement**: Enhanced HTTP client with better error handling and retry logic
* **Improvement**: Improved download robustness with automatic retry on network failures
* **Test**: Added extensive unit test coverage for core components
  * Tests for `UpdateChecker`, `UpdateInfo`, `RetryStrategy`, and `VersionComparator`
  * Mock HTTP client for reliable testing
* **Improvement**: Enhanced Android plugin implementation
* **Documentation**: Updated README with retry strategy and logging configuration examples

## 2.0.0

* **Breaking**: Complete rebuild of the plugin architecture
* **Feature**: Added OpenHarmony (OHOS) platform support
* **Feature**: Zero third-party dependencies - uses Flutter native HTTP only
* **Feature**: Fully customizable update dialogs and API response formats
* **Feature**: Support for forced and optional updates with download progress
* **Improvement**: Modular architecture with clear separation of concerns
* **Improvement**: Enhanced example app with better demonstration of features
* **Documentation**: Comprehensive README with usage examples and customization guide
