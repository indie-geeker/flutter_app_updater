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
