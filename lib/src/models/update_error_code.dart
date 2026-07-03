enum UpdateErrorCode {
  manifestFetchFailed('MANIFEST_FETCH_FAILED'),
  manifestInvalid('MANIFEST_INVALID'),
  unsupportedSchemaVersion('UNSUPPORTED_SCHEMA_VERSION'),
  unsupportedActionType('UNSUPPORTED_ACTION_TYPE'),
  missingRequiredField('MISSING_REQUIRED_FIELD'),
  legacyFieldNotSupported('LEGACY_FIELD_NOT_SUPPORTED'),
  noMatchingRelease('NO_MATCHING_RELEASE'),
  noSupportedAction('NO_SUPPORTED_ACTION'),
  storeNotAvailable('STORE_NOT_AVAILABLE'),
  marketNotAvailable('MARKET_NOT_AVAILABLE'),
  playInAppUpdateUnavailable('PLAY_IN_APP_UPDATE_UNAVAILABLE'),
  packageDownloadFailed('PACKAGE_DOWNLOAD_FAILED'),
  packageHashMismatch('PACKAGE_HASH_MISMATCH'),
  packageSignatureInvalid('PACKAGE_SIGNATURE_INVALID'),
  installerOpenFailed('INSTALLER_OPEN_FAILED'),
  platformNotSupported('PLATFORM_NOT_SUPPORTED');

  final String value;

  const UpdateErrorCode(this.value);

  @override
  String toString() => value;
}
