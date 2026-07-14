/// Stable machine-readable codes for update checks and action failures.
enum UpdateErrorCode {
  /// Host updater or selector configuration is invalid.
  configurationInvalid('CONFIGURATION_INVALID'),

  /// Remote manifest transport failed.
  manifestFetchFailed('MANIFEST_FETCH_FAILED'),

  /// Trust policy requires a signed envelope but received a bare manifest.
  manifestSignatureRequired('MANIFEST_SIGNATURE_REQUIRED'),

  /// Signed envelope authentication or validity checks failed.
  manifestSignatureInvalid('MANIFEST_SIGNATURE_INVALID'),

  /// Manifest syntax or cross-field policy is invalid.
  manifestInvalid('MANIFEST_INVALID'),

  /// Manifest application identity differs from the expected host identity.
  appIdMismatch('APP_ID_MISMATCH'),

  /// Manifest uses an unsupported schema version.
  unsupportedSchemaVersion('UNSUPPORTED_SCHEMA_VERSION'),

  /// Manifest declares an unknown or prohibited action type.
  unsupportedActionType('UNSUPPORTED_ACTION_TYPE'),

  /// A required manifest or action field is absent or malformed.
  missingRequiredField('MISSING_REQUIRED_FIELD'),

  /// Manifest contains a removed legacy field.
  legacyFieldNotSupported('LEGACY_FIELD_NOT_SUPPORTED'),

  /// Newer releases exist but none match runtime target constraints.
  noMatchingRelease('NO_MATCHING_RELEASE'),

  /// No action survives distribution policy and executor capability filtering.
  noSupportedAction('NO_SUPPORTED_ACTION'),

  /// Official store could not be opened.
  storeNotAvailable('STORE_NOT_AVAILABLE'),

  /// Requested Android market could not be opened.
  marketNotAvailable('MARKET_NOT_AVAILABLE'),

  /// Package transfer failed for a retryable or terminal transport reason.
  packageDownloadFailed('PACKAGE_DOWNLOAD_FAILED'),

  /// Declared or received package exceeds the configured size limit.
  packageTooLarge('PACKAGE_TOO_LARGE'),

  /// Artifact byte count or SHA-256 differs from signed metadata.
  packageHashMismatch('PACKAGE_HASH_MISMATCH'),

  /// Android APK identity or signing lineage verification failed.
  packageSignatureInvalid('PACKAGE_SIGNATURE_INVALID'),

  /// Android requires user authorization to install unknown applications.
  packageInstallPermissionRequired('PACKAGE_INSTALL_PERMISSION_REQUIRED'),

  /// Requested local package no longer exists.
  packageFileNotFound('PACKAGE_FILE_NOT_FOUND'),

  /// Native package installer handoff failed.
  packageInstallFailed('PACKAGE_INSTALL_FAILED'),

  /// Desktop installer could not be opened.
  installerOpenFailed('INSTALLER_OPEN_FAILED'),

  /// Current platform cannot perform the requested action.
  platformNotSupported('PLATFORM_NOT_SUPPORTED'),

  /// Durable Android download service is unavailable.
  backgroundDownloadUnavailable('BACKGROUND_DOWNLOAD_UNAVAILABLE'),

  /// Durable task identifier does not exist.
  backgroundDownloadNotFound('BACKGROUND_DOWNLOAD_NOT_FOUND'),

  /// Native service rejected creation of a durable task.
  backgroundDownloadStartRejected('BACKGROUND_DOWNLOAD_START_REJECTED'),

  /// Durable task cannot perform the requested lifecycle transition.
  backgroundDownloadInvalidState('BACKGROUND_DOWNLOAD_INVALID_STATE'),

  /// Required persistent storage is unavailable.
  backgroundStorageUnavailable('BACKGROUND_STORAGE_UNAVAILABLE'),

  /// Another writer already owns the same artifact download.
  downloadInProgress('DOWNLOAD_IN_PROGRESS'),

  /// Executor failed without a more specific code.
  actionFailed('ACTION_FAILED'),

  /// Host requested cooperative action cancellation.
  actionCanceled('ACTION_CANCELED');

  /// Stable uppercase wire and logging representation.
  final String value;

  const UpdateErrorCode(this.value);

  @override
  String toString() => value;
}
