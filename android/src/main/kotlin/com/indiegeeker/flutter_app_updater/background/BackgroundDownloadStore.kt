package com.indiegeeker.flutter_app_updater.background

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.charset.StandardCharsets
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import org.json.JSONObject
import org.json.JSONException

internal interface BackgroundRecordFile {
  fun exists(): Boolean
  fun readText(): String
  fun writeText(contents: String)
  fun delete()
}

internal fun interface BackgroundRecordFileFactory {
  fun create(file: File): BackgroundRecordFile
}

private object AndroidAtomicRecordFileFactory : BackgroundRecordFileFactory {
  override fun create(file: File): BackgroundRecordFile = AndroidAtomicRecordFile(file)
}

private class AndroidAtomicRecordFile(file: File) : BackgroundRecordFile {
  private val atomicFile = AtomicFile(file)

  override fun exists(): Boolean = atomicFile.baseFile.isFile

  override fun readText(): String =
    atomicFile.readFully().toString(StandardCharsets.UTF_8)

  override fun writeText(contents: String) {
    var output: FileOutputStream? = null
    try {
      output = atomicFile.startWrite()
      output.write(contents.toByteArray(StandardCharsets.UTF_8))
      atomicFile.finishWrite(output)
    } catch (error: Throwable) {
      if (output != null) atomicFile.failWrite(output)
      throw error
    }
  }

  override fun delete() {
    atomicFile.delete()
  }
}

internal class BackgroundDownloadStore(
  root: File,
  private val recordFileFactory: BackgroundRecordFileFactory = AndroidAtomicRecordFileFactory,
  private val artifactVerifier: (File, BackgroundDownloadRecord) -> Boolean = { _, _ -> false },
  private val nowEpochMs: () -> Long = System::currentTimeMillis,
) {
  private val rootDirectory = root.canonicalFile
  private val taskLocks = Array(LOCK_STRIPE_COUNT) { ReentrantLock() }

  constructor(
    context: Context,
    artifactVerifier: (File, BackgroundDownloadRecord) -> Boolean,
    nowEpochMs: () -> Long = System::currentTimeMillis,
  ) : this(
    File(context.filesDir, "flutter_app_updater/background"),
    AndroidAtomicRecordFileFactory,
    artifactVerifier,
    nowEpochMs,
  )

  init {
    require(rootDirectory.mkdirs() || rootDirectory.isDirectory) {
      "Unable to create background download storage root"
    }
  }

  fun create(record: BackgroundDownloadRecord): BackgroundDownloadRecord =
    withTaskLock(record.id) {
      val directory = taskDirectory(record.id)
      require(directory.mkdirs() || directory.isDirectory) {
        "Unable to create background download task directory"
      }
      val recordFile = recordFile(record.id)
      if (recordFile.exists()) {
        throw BackgroundDownloadStateException("Background download task already exists")
      }
      recordFile.writeText(record.toJson().toString())
      record
    }

  fun write(
    record: BackgroundDownloadRecord,
    expectedRevision: Long,
  ): BackgroundDownloadRecord = withTaskLock(record.id) {
    writeUnlocked(record, expectedRevision)
  }

  fun read(id: String): BackgroundDownloadRecord = withTaskLock(id) {
    readUnlocked(id)
  }

  fun list(): List<BackgroundDownloadRecord> {
    val directories = rootDirectory.listFiles()
      ?.asSequence()
      ?.filter { it.isDirectory && BackgroundDownloadContract.isValidId(it.name) }
      ?.sortedBy { it.name }
      ?.toList()
      .orEmpty()

    return directories.mapNotNull { directory ->
      val id = directory.name
      try {
        withTaskLock(id) {
          val file = recordFile(id)
          if (!file.exists()) return@withTaskLock null
          readUnlocked(id)
        }
      } catch (_: InvalidBackgroundDownloadPathException) {
        null
      }
    }.sortedWith(
      compareByDescending<BackgroundDownloadRecord> { it.updatedAtEpochMs }
        .thenBy { it.id },
    )
  }

  fun taskDirectory(id: String): File = checkedTaskDirectory(id)

  fun partialFile(id: String): File = checkedTaskFile(id, PARTIAL_FILE_NAME)

  fun apkFile(id: String): File = checkedTaskFile(id, APK_FILE_NAME)

  fun reconcileArtifacts(id: String): BackgroundDownloadRecord {
    val verification = withTaskLock(id) {
      if (hasUnsupportedBackingSchema(id)) return readUnlocked(id)
      val record = readUnlocked(id)
      val apk = apkFile(id)
      if (record.status == BackgroundDownloadStatus.canceled) {
        deleteArtifact(partialFile(id))
        deleteArtifact(apk)
        return record
      }
      if (apk.isFile &&
        (record.status == BackgroundDownloadStatus.verifying ||
          record.status == BackgroundDownloadStatus.completed)
      ) {
        ArtifactVerificationCandidate(record, apk)
      } else {
        return reconcileWithoutArtifactVerificationUnlocked(record)
      }
    }

    // Hashing a 1 GiB APK must not hold either the coordinator-wide lock or a
    // task lock. Revalidate the durable revision/status before committing.
    val valid = verifyArtifact(verification.apk, verification.record)
    return withTaskLock(id) {
      val current = readUnlocked(id)
      if (current.revision != verification.record.revision ||
        current.status != verification.record.status ||
        !current.hasSameArtifactIdentity(verification.record) ||
        !current.hasSameImmutableConfiguration(verification.record)
      ) {
        return@withTaskLock current
      }
      val apk = apkFile(id)
      when (current.status) {
        BackgroundDownloadStatus.canceled -> {
          deleteArtifact(partialFile(id))
          deleteArtifact(apk)
          current
        }
        BackgroundDownloadStatus.verifying -> if (valid && apk.isFile) {
          writeUnlocked(
            current.copy(
              revision = current.revision + 1,
              status = BackgroundDownloadStatus.completed,
              errorCode = null,
              errorMessage = null,
              nativeErrorCode = null,
              updatedAtEpochMs = nextUpdatedAt(current),
            ),
            current.revision,
          )
        } else {
          deleteArtifact(apk)
          failRecord(current, "artifact_verification_failed")
        }
        BackgroundDownloadStatus.completed -> if (valid && apk.isFile) {
          current
        } else {
          deleteArtifact(apk)
          failRecord(current, "completed_artifact_invalid")
        }
        else -> current
      }
    }
  }

  private fun reconcileWithoutArtifactVerificationUnlocked(
    initial: BackgroundDownloadRecord,
  ): BackgroundDownloadRecord {
    var record = initial
    val apk = apkFile(record.id)
    if (record.status == BackgroundDownloadStatus.completed) {
      deleteArtifact(apk)
      return failRecord(record, "completed_artifact_missing")
    }
    val partial = partialFile(record.id)
    if (record.status == BackgroundDownloadStatus.verifying) {
      if (!partial.isFile) {
        return failRecord(record, "PACKAGE_DOWNLOAD_FAILED")
      }
      if (partial.length() > record.downloadedBytes) {
        RandomAccessFile(partial, "rw").use { it.setLength(record.downloadedBytes) }
      }
      if (partial.length() < record.downloadedBytes) {
        deleteArtifact(partial)
        return writeUnlocked(
          record.copy(
            revision = record.revision + 1,
            status = BackgroundDownloadStatus.pausedBySystem,
            downloadedBytes = 0,
            strongEtag = null,
            updatedAtEpochMs = nextUpdatedAt(record),
          ),
          record.revision,
        )
      }
      return writeUnlocked(
        record.copy(
          revision = record.revision + 1,
          status = BackgroundDownloadStatus.pausedBySystem,
          updatedAtEpochMs = nextUpdatedAt(record),
        ),
        record.revision,
      )
    }

    if (partial.isFile && partial.length() > record.downloadedBytes) {
      RandomAccessFile(partial, "rw").use { it.setLength(record.downloadedBytes) }
    } else if (record.downloadedBytes > 0 && (!partial.isFile || partial.length() < record.downloadedBytes)) {
      deleteArtifact(partial)
      record = writeUnlocked(
        record.copy(
          revision = record.revision + 1,
          status = BackgroundDownloadStatus.pausedBySystem,
          downloadedBytes = 0,
          strongEtag = null,
          updatedAtEpochMs = nextUpdatedAt(record),
        ),
        record.revision,
      )
    }
    return record
  }

  fun cancelArtifactsAndWriteTombstone(
    id: String,
    expectedRevision: Long,
  ): BackgroundDownloadRecord = withTaskLock(id) {
    requireSupportedBackingSchema(id)
    val current = readUnlocked(id)
    if (current.status == BackgroundDownloadStatus.canceled) {
      deleteArtifact(partialFile(id))
      deleteArtifact(apkFile(id))
      return@withTaskLock current
    }
    if (current.status == BackgroundDownloadStatus.completed || current.status == BackgroundDownloadStatus.failed) {
      throw BackgroundDownloadStateException("Terminal task must be removed instead of canceled")
    }
    requireExpectedRevision(current, expectedRevision)
    val tombstone = writeUnlocked(
      current.copy(
        revision = current.revision + 1,
        status = BackgroundDownloadStatus.canceled,
        errorCode = null,
        errorMessage = null,
        nativeErrorCode = null,
        updatedAtEpochMs = nextUpdatedAt(current),
      ),
      current.revision,
    )
    deleteArtifact(partialFile(id))
    deleteArtifact(apkFile(id))
    tombstone
  }

  fun remove(id: String) = withTaskLock(id) {
    val file = recordFile(id)
    if (!file.exists()) throw BackgroundDownloadStateException("Background download task does not exist")
    val contents = file.readText()
    val record = try {
      parseRecord(id, contents)
    } catch (_: JSONException) {
      null
    } catch (_: IllegalArgumentException) {
      null
    }
    if (record != null && !record.status.isTerminal) {
      throw BackgroundDownloadStateException("Only terminal background downloads can be removed")
    }
    deleteArtifact(partialFile(id))
    deleteArtifact(apkFile(id))
    recordFile(id).delete()
    val directory = taskDirectory(id)
    if (directory.exists() && !directory.delete()) {
      throw BackgroundDownloadStateException("Unable to remove background download task directory")
    }
  }

  private fun readUnlocked(id: String): BackgroundDownloadRecord {
    val validId = BackgroundDownloadContract.requireValidId(id)
    val file = recordFile(validId)
    if (!file.exists()) throw BackgroundDownloadStateException("Background download task does not exist")
    val contents = file.readText()
    val json = try {
      JSONObject(contents)
    } catch (_: JSONException) {
      return persistRecoveryRecord(validId, "corrupt_state")
    }
    val schemaVersion = json.opt("schemaVersion")
    if (schemaVersion is Number && schemaVersion.toLong() != BackgroundDownloadContract.SCHEMA_VERSION.toLong()) {
      return unsupportedSchemaRecord(validId, json)
    }
    val record = try {
      BackgroundDownloadRecord.fromJson(json)
    } catch (_: IllegalArgumentException) {
      return persistRecoveryRecord(validId, "corrupt_state")
    }
    if (record.id != validId) {
      return persistRecoveryRecord(validId, "corrupt_state")
    }
    return record
  }

  private fun parseRecord(id: String, contents: String): BackgroundDownloadRecord {
    val record = BackgroundDownloadRecord.fromJson(JSONObject(contents))
    require(record.id == id) { "Background download record id does not match its directory" }
    return record
  }

  private fun persistRecoveryRecord(id: String, errorCode: String): BackgroundDownloadRecord {
    val recovered = failedRecoveryRecord(id, errorCode)
    recordFile(id).writeText(recovered.toJson().toString())
    return recovered
  }

  private fun writeUnlocked(
    record: BackgroundDownloadRecord,
    expectedRevision: Long,
  ): BackgroundDownloadRecord {
    requireSupportedBackingSchema(record.id)
    val current = readUnlocked(record.id)
    requireExpectedRevision(current, expectedRevision)
    if (record.revision <= current.revision) {
      throw BackgroundDownloadRevisionException("Background download revision must increase")
    }
    if (!record.hasSameArtifactIdentity(current)) {
      throw BackgroundDownloadStateException("Background download artifact identity cannot change")
    }
    if (record.id != current.id || !record.hasSameImmutableConfiguration(current)) {
      throw BackgroundDownloadStateException("Background download immutable fields cannot change")
    }
    recordFile(record.id).writeText(record.toJson().toString())
    return record
  }

  private fun requireExpectedRevision(
    current: BackgroundDownloadRecord,
    expectedRevision: Long,
  ) {
    if (current.revision != expectedRevision) {
      throw BackgroundDownloadRevisionException(
        "Stale background download revision: expected $expectedRevision, current ${current.revision}",
      )
    }
  }

  private fun failRecord(
    record: BackgroundDownloadRecord,
    errorCode: String,
  ): BackgroundDownloadRecord = writeUnlocked(
    record.copy(
      revision = record.revision + 1,
      status = BackgroundDownloadStatus.failed,
      errorCode = errorCode,
      errorMessage = errorCode,
      nativeErrorCode = null,
      updatedAtEpochMs = nextUpdatedAt(record),
    ),
    record.revision,
  )

  private fun verifyArtifact(file: File, record: BackgroundDownloadRecord): Boolean =
    try {
      artifactVerifier(file, record)
    } catch (error: IOException) {
      throw error
    } catch (_: Exception) {
      false
    }

  private data class ArtifactVerificationCandidate(
    val record: BackgroundDownloadRecord,
    val apk: File,
  )

  private fun nextUpdatedAt(record: BackgroundDownloadRecord): Long =
    maxOf(nowEpochMs(), record.updatedAtEpochMs)

  private fun failedRecoveryRecord(id: String, errorCode: String): BackgroundDownloadRecord =
    BackgroundDownloadRecord(
      revision = 1,
      id = id,
      packageUrl = "invalid://recovered-state",
      status = BackgroundDownloadStatus.failed,
      downloadedBytes = 0,
      totalBytes = null,
      expectedSizeBytes = 1,
      expectedSha256 = "0".repeat(64),
      errorCode = errorCode,
      errorMessage = errorCode,
      createdAtEpochMs = 0,
      updatedAtEpochMs = 0,
    )

  private fun unsupportedSchemaRecord(id: String, json: JSONObject): BackgroundDownloadRecord {
    val createdAt = rawLong(json, "createdAtEpochMs")?.coerceAtLeast(0) ?: 0
    val updatedAt = maxOf(
      createdAt,
      rawLong(json, "updatedAtEpochMs")?.coerceAtLeast(0) ?: createdAt,
    )
    val revision = rawLong(json, "revision")?.takeIf { it > 0 } ?: 1
    return failedRecoveryRecord(id, "unsupported_schema").copy(
      revision = revision,
      createdAtEpochMs = createdAt,
      updatedAtEpochMs = updatedAt,
    )
  }

  private fun rawLong(json: JSONObject, key: String): Long? = when (val value = json.opt(key)) {
    is Byte -> value.toLong()
    is Short -> value.toLong()
    is Int -> value.toLong()
    is Long -> value
    else -> null
  }

  private fun requireSupportedBackingSchema(id: String) {
    if (hasUnsupportedBackingSchema(id)) {
      throw BackgroundDownloadStateException("unsupported_schema")
    }
  }

  private fun hasUnsupportedBackingSchema(id: String): Boolean {
    val file = recordFile(id)
    if (!file.exists()) throw BackgroundDownloadStateException("Background download task does not exist")
    val json = try {
      JSONObject(file.readText())
    } catch (_: JSONException) {
      return false
    }
    val schemaVersion = json.opt("schemaVersion")
    return schemaVersion is Number &&
      schemaVersion.toLong() != BackgroundDownloadContract.SCHEMA_VERSION.toLong()
  }

  private fun recordFile(id: String): BackgroundRecordFile =
    recordFileFactory.create(checkedTaskFile(id, RECORD_FILE_NAME))

  private fun checkedTaskDirectory(id: String): File {
    val validId = BackgroundDownloadContract.requireValidId(id)
    val directory = File(rootDirectory, validId).absoluteFile
    if (canonicalFile(directory) != directory) {
      throw InvalidBackgroundDownloadPathException(
        "Background download task path is not an exact direct child",
      )
    }
    return directory
  }

  private fun checkedTaskFile(id: String, name: String): File {
    val directory = checkedTaskDirectory(id)
    val file = File(directory, name).absoluteFile
    if (canonicalFile(file) != file) {
      throw InvalidBackgroundDownloadPathException(
        "Background download file path is not an exact direct file",
      )
    }
    return file
  }

  private fun canonicalFile(file: File): File = try {
    file.canonicalFile
  } catch (error: java.io.IOException) {
    throw InvalidBackgroundDownloadPathException("Unable to resolve background download path", error)
  }

  private fun deleteArtifact(file: File) {
    if (file.exists() && !file.delete()) {
      throw BackgroundDownloadStateException("Unable to delete background download artifact")
    }
  }

  private inline fun <T> withTaskLock(id: String, action: () -> T): T {
    val validId = BackgroundDownloadContract.requireValidId(id)
    val hash = validId.hashCode() xor (validId.hashCode() ushr 16)
    val lock = taskLocks[(hash and Int.MAX_VALUE) % taskLocks.size]
    return lock.withLock(action)
  }

  private companion object {
    const val LOCK_STRIPE_COUNT = 64
    const val RECORD_FILE_NAME = "task.json"
    const val PARTIAL_FILE_NAME = "artifact.download"
    const val APK_FILE_NAME = "artifact.apk"
  }
}

private class InvalidBackgroundDownloadPathException(
  message: String,
  cause: Throwable? = null,
) : IllegalArgumentException(message, cause)
