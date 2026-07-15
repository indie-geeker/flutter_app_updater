package com.indiegeeker.flutter_app_updater.background

import org.json.JSONObject

internal object BackgroundDownloadContract {
  const val SCHEMA_VERSION = 1
  const val MAX_DOWNLOAD_BYTES_CEILING = 1_073_741_824L
  const val DEFAULT_MAX_DOWNLOAD_BYTES = MAX_DOWNLOAD_BYTES_CEILING
  const val DEFAULT_SCHEDULER_JOB_ID = 0x465541
  const val DEFAULT_NOTIFICATION_ID = 0x465542

  private val idPattern = Regex("[A-Za-z0-9_-]{1,80}")
  private val sha256Pattern = Regex("[0-9a-f]{64}")

  fun isValidId(id: String): Boolean = idPattern.matches(id)

  fun requireValidId(id: String): String {
    require(isValidId(id)) { "Invalid background download task id" }
    return id
  }

  fun requireValidSha256(hash: String): String {
    require(sha256Pattern.matches(hash)) { "expectedSha256 must be lowercase 64-hex" }
    return hash
  }
}

internal enum class BackgroundDownloadStatus {
  queued,
  running,
  waitingForNetwork,
  waitingForStorage,
  pausedBySystem,
  verifying,
  completed,
  failed,
  canceled;

  val isTerminal: Boolean
    get() = this == completed || this == failed || this == canceled
}

internal data class BackgroundDownloadRecord(
  val schemaVersion: Int = BackgroundDownloadContract.SCHEMA_VERSION,
  val revision: Long,
  val id: String,
  val packageUrl: String,
  val status: BackgroundDownloadStatus,
  val downloadedBytes: Long,
  val totalBytes: Long?,
  val expectedSizeBytes: Long,
  val expectedSha256: String,
  val maxDownloadBytes: Long = BackgroundDownloadContract.DEFAULT_MAX_DOWNLOAD_BYTES,
  val strongEtag: String? = null,
  val schedulerJobId: Int = BackgroundDownloadContract.DEFAULT_SCHEDULER_JOB_ID,
  val notificationId: Int = BackgroundDownloadContract.DEFAULT_NOTIFICATION_ID,
  val lastStopReason: Int? = null,
  val errorCode: String? = null,
  val errorMessage: String? = null,
  val nativeErrorCode: String? = null,
  val createdAtEpochMs: Long,
  val updatedAtEpochMs: Long,
) {
  init {
    require(schemaVersion == BackgroundDownloadContract.SCHEMA_VERSION) {
      "Unsupported background download schema version: $schemaVersion"
    }
    require(revision > 0) { "revision must be positive" }
    BackgroundDownloadContract.requireValidId(id)
    require(packageUrl.isNotBlank()) { "packageUrl must not be blank" }
    require(downloadedBytes >= 0) { "downloadedBytes must not be negative" }
    require(expectedSizeBytes > 0) { "expectedSizeBytes must be positive" }
    BackgroundDownloadContract.requireValidSha256(expectedSha256)
    require(maxDownloadBytes > 0) { "maxDownloadBytes must be positive" }
    require(expectedSizeBytes <= maxDownloadBytes) {
      "expectedSizeBytes must not exceed maxDownloadBytes"
    }
    require(maxDownloadBytes <= BackgroundDownloadContract.MAX_DOWNLOAD_BYTES_CEILING) {
      "maxDownloadBytes exceeds the native MVP ceiling"
    }
    require(downloadedBytes <= expectedSizeBytes) {
      "downloadedBytes must not exceed expectedSizeBytes"
    }
    if (totalBytes != null) {
      require(totalBytes > 0) { "totalBytes must be positive" }
      require(totalBytes == expectedSizeBytes) { "totalBytes must equal expectedSizeBytes" }
      require(totalBytes <= maxDownloadBytes) { "totalBytes must not exceed maxDownloadBytes" }
      require(totalBytes >= downloadedBytes) { "totalBytes must not be less than downloadedBytes" }
    }
    require(schedulerJobId > 0) { "schedulerJobId must be positive" }
    require(notificationId > 0) { "notificationId must be positive" }
    require(createdAtEpochMs >= 0) { "createdAtEpochMs must not be negative" }
    require(updatedAtEpochMs >= createdAtEpochMs) {
      "updatedAtEpochMs must not precede createdAtEpochMs"
    }
  }

  fun hasSameArtifactIdentity(other: BackgroundDownloadRecord): Boolean =
    expectedSha256 == other.expectedSha256 && expectedSizeBytes == other.expectedSizeBytes

  fun hasSameImmutableConfiguration(other: BackgroundDownloadRecord): Boolean =
    schemaVersion == other.schemaVersion &&
      packageUrl == other.packageUrl &&
      maxDownloadBytes == other.maxDownloadBytes &&
      schedulerJobId == other.schedulerJobId &&
      notificationId == other.notificationId &&
      createdAtEpochMs == other.createdAtEpochMs

  fun toJson(): JSONObject = JSONObject()
    .put("schemaVersion", schemaVersion)
    .put("revision", revision)
    .put("id", id)
    .put("packageUrl", packageUrl)
    .put("status", status.name)
    .put("downloadedBytes", downloadedBytes)
    .put("totalBytes", totalBytes ?: JSONObject.NULL)
    .put("expectedSizeBytes", expectedSizeBytes)
    .put("expectedSha256", expectedSha256)
    .put("maxDownloadBytes", maxDownloadBytes)
    .put("strongEtag", strongEtag ?: JSONObject.NULL)
    .put("schedulerJobId", schedulerJobId)
    .put("notificationId", notificationId)
    .put("lastStopReason", lastStopReason ?: JSONObject.NULL)
    .put("errorCode", errorCode ?: JSONObject.NULL)
    .put("errorMessage", errorMessage ?: JSONObject.NULL)
    .put("nativeErrorCode", nativeErrorCode ?: JSONObject.NULL)
    .put("createdAtEpochMs", createdAtEpochMs)
    .put("updatedAtEpochMs", updatedAtEpochMs)

  fun toMap(filePath: String? = null): Map<String, Any?> = linkedMapOf(
    "id" to id,
    "revision" to revision,
    "status" to status.name,
    "downloadedBytes" to downloadedBytes,
    "totalBytes" to totalBytes,
    "filePath" to filePath,
    "errorCode" to errorCode,
    "errorMessage" to errorMessage,
    "nativeErrorCode" to nativeErrorCode,
    "createdAtEpochMs" to createdAtEpochMs,
    "updatedAtEpochMs" to updatedAtEpochMs,
  )

  companion object {
    fun fromJson(json: JSONObject): BackgroundDownloadRecord {
      val keys = json.keys().asSequence().toSet()
      require(keys == SCHEMA_V1_KEYS) { "Background download schema v1 keys do not match" }
      val schemaVersion = json.requiredInt("schemaVersion")
      require(schemaVersion == BackgroundDownloadContract.SCHEMA_VERSION) {
        "Unsupported background download schema version: $schemaVersion"
      }
      val statusName = json.requiredString("status")
      val status = BackgroundDownloadStatus.entries.firstOrNull { it.name == statusName }
        ?: throw IllegalArgumentException("Unknown background download status: $statusName")

      return BackgroundDownloadRecord(
        schemaVersion = schemaVersion,
        revision = json.requiredLong("revision"),
        id = json.requiredString("id"),
        packageUrl = BackgroundDownloadUrlPolicy.requirePersistentEntry(
          json.requiredString("packageUrl"),
        ),
        status = status,
        downloadedBytes = json.requiredLong("downloadedBytes"),
        totalBytes = json.nullableLong("totalBytes"),
        expectedSizeBytes = json.requiredLong("expectedSizeBytes"),
        expectedSha256 = json.requiredString("expectedSha256"),
        maxDownloadBytes = json.requiredLong("maxDownloadBytes"),
        strongEtag = json.nullableString("strongEtag"),
        schedulerJobId = json.requiredInt("schedulerJobId"),
        notificationId = json.requiredInt("notificationId"),
        lastStopReason = json.nullableInt("lastStopReason"),
        errorCode = json.nullableString("errorCode"),
        errorMessage = json.nullableString("errorMessage"),
        nativeErrorCode = json.nullableString("nativeErrorCode"),
        createdAtEpochMs = json.requiredLong("createdAtEpochMs"),
        updatedAtEpochMs = json.requiredLong("updatedAtEpochMs"),
      )
    }

    private val SCHEMA_V1_KEYS = setOf(
      "schemaVersion",
      "revision",
      "id",
      "packageUrl",
      "status",
      "downloadedBytes",
      "totalBytes",
      "expectedSizeBytes",
      "expectedSha256",
      "maxDownloadBytes",
      "strongEtag",
      "schedulerJobId",
      "notificationId",
      "lastStopReason",
      "errorCode",
      "errorMessage",
      "nativeErrorCode",
      "createdAtEpochMs",
      "updatedAtEpochMs",
    )
  }
}

internal open class BackgroundDownloadStateException(message: String) : IllegalStateException(message)

internal class BackgroundDownloadRevisionException(message: String) :
  BackgroundDownloadStateException(message)

internal class BackgroundDownloadStartRejectedException(
  val code: String,
  message: String,
) : BackgroundDownloadStateException(message)

private fun JSONObject.requiredValue(key: String): Any {
  require(has(key) && !isNull(key)) { "Missing required field: $key" }
  return get(key)
}

private fun JSONObject.requiredString(key: String): String {
  val value = requiredValue(key)
  require(value is String) { "$key must be a string" }
  return value
}

private fun JSONObject.requiredLong(key: String): Long {
  val value = requiredValue(key)
  require(value is Byte || value is Short || value is Int || value is Long) {
    "$key must be an integer"
  }
  return (value as Number).toLong()
}

private fun JSONObject.requiredInt(key: String): Int {
  val value = requiredLong(key)
  require(value in Int.MIN_VALUE..Int.MAX_VALUE) { "$key is outside Int range" }
  return value.toInt()
}

private fun JSONObject.nullableString(key: String): String? {
  require(has(key)) { "Missing required field: $key" }
  if (isNull(key)) return null
  return requiredString(key)
}

private fun JSONObject.nullableLong(key: String): Long? {
  require(has(key)) { "Missing required field: $key" }
  if (isNull(key)) return null
  return requiredLong(key)
}

private fun JSONObject.nullableInt(key: String): Int? {
  require(has(key)) { "Missing required field: $key" }
  if (isNull(key)) return null
  return requiredInt(key)
}
