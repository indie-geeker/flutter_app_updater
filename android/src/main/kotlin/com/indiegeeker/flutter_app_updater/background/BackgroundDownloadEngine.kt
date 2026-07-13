package com.indiegeeker.flutter_app_updater.background

import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.RandomAccessFile
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.URI
import java.net.UnknownHostException
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.SSLException
import kotlin.math.max

internal enum class BackgroundDownloadExecutionOutcome {
  completed,
  waitingForNetwork,
  waitingForStorage,
  pausedBySystem,
  failed,
  canceled,
  alreadyRunning,
}

internal data class BackgroundDownloadExecutionResult(
  val outcome: BackgroundDownloadExecutionOutcome,
  val record: BackgroundDownloadRecord?,
)

internal data class BackgroundDownloadProgress(
  val id: String,
  val revision: Long,
  val downloadedBytes: Long,
  val totalBytes: Long,
)

internal class BackgroundDownloadStopReason private constructor(
  val kind: Kind,
  val nativeReason: Int?,
) {
  internal enum class Kind { none, cancel, system }

  companion object {
    val none = BackgroundDownloadStopReason(Kind.none, null)
    val cancel = BackgroundDownloadStopReason(Kind.cancel, null)
    fun system(nativeReason: Int? = null) = BackgroundDownloadStopReason(Kind.system, nativeReason)
  }
}

internal fun interface BackgroundDownloadAvailableSpaceProvider {
  fun availableBytes(directory: File): Long
}

internal interface BackgroundDownloadArtifactMover {
  fun moveAtomically(source: File, target: File)
  fun syncDirectory(directory: File)
}

internal object JvmBackgroundDownloadArtifactMover : BackgroundDownloadArtifactMover {
  override fun moveAtomically(source: File, target: File) {
    if (!source.renameTo(target)) throw IOException("Unable to rename artifact")
  }

  override fun syncDirectory(directory: File) = Unit
}

internal fun interface BackgroundDownloadArtifactCleaner {
  fun delete(file: File): Boolean
}

internal object JvmBackgroundDownloadArtifactCleaner : BackgroundDownloadArtifactCleaner {
  override fun delete(file: File): Boolean = !file.exists() || file.delete()
}

internal interface BackgroundDownloadArtifactWriter : AutoCloseable {
  val length: Long
  fun truncate(length: Long)
  fun seek(position: Long)
  fun write(bytes: ByteArray, offset: Int, length: Int)
  fun flush()
  override fun close()
}

internal class RandomAccessArtifactWriter(file: File) : BackgroundDownloadArtifactWriter {
  private val output = RandomAccessFile(file, "rw")
  override val length: Long get() = output.length()
  override fun truncate(length: Long) = output.setLength(length)
  override fun seek(position: Long) = output.seek(position)
  override fun write(bytes: ByteArray, offset: Int, length: Int) = output.write(bytes, offset, length)
  override fun flush() = output.fd.sync()
  override fun close() = output.close()
}

private class StorageClassifyingArtifactWriter(
  private val delegate: BackgroundDownloadArtifactWriter,
) : BackgroundDownloadArtifactWriter {
  override val length: Long get() = storageCall { delegate.length }
  override fun truncate(length: Long) = storageCall { delegate.truncate(length) }
  override fun seek(position: Long) = storageCall { delegate.seek(position) }
  override fun write(bytes: ByteArray, offset: Int, length: Int) =
    storageCall { delegate.write(bytes, offset, length) }
  override fun flush() = storageCall { delegate.flush() }
  override fun close() = storageCall { delegate.close() }

  private fun <T> storageCall(action: () -> T): T = try {
    action()
  } catch (error: BackgroundDownloadWriteException) {
    throw error
  } catch (error: IOException) {
    throw BackgroundDownloadWriteException("Artifact storage operation failed", error)
  }
}

internal open class BackgroundDownloadEngineException(message: String, cause: Throwable? = null) :
  Exception(message, cause)

internal class BackgroundDownloadProtocolException(message: String) :
  BackgroundDownloadEngineException(message)

internal class BackgroundDownloadIntegrityException(
  message: String,
  val code: String = "integrity_error",
) : BackgroundDownloadEngineException(message)

internal open class BackgroundDownloadWriteException(message: String, cause: Throwable? = null) :
  BackgroundDownloadEngineException(message, cause)

private class BackgroundDownloadRecordWriteException(
  val snapshot: BackgroundDownloadRecord,
  cause: IOException,
) : BackgroundDownloadWriteException("Task record storage operation failed", cause)

private class BackgroundDownloadCheckpointWriteException(
  val snapshot: BackgroundDownloadRecord,
  val downloadedBytes: Long,
  val strongEtag: String,
  cause: BackgroundDownloadRecordWriteException,
) : BackgroundDownloadWriteException("Checkpoint record storage operation failed", cause)

private class RetryableNetworkException(message: String, cause: Throwable? = null) :
  BackgroundDownloadEngineException(message, cause)

private class ExecutionStopped(val reason: BackgroundDownloadStopReason) : Exception()

private class BackgroundDownloadTlsException(cause: Throwable) :
  BackgroundDownloadEngineException("TLS validation failed", cause)

internal class BackgroundDownloadExecutionControl {
  private val stopReason = AtomicReference(BackgroundDownloadStopReason.none)
  private val activeConnection = AtomicReference<HttpDownloadConnection?>(null)

  fun requestSystemStop(nativeReason: Int? = null) {
    stopReason.compareAndSet(BackgroundDownloadStopReason.none, BackgroundDownloadStopReason.system(nativeReason))
    closeActiveConnection()
  }

  fun requestCancel() {
    while (true) {
      val current = stopReason.get()
      if (current.kind == BackgroundDownloadStopReason.Kind.cancel) break
      if (stopReason.compareAndSet(current, BackgroundDownloadStopReason.cancel)) break
    }
    closeActiveConnection()
  }

  internal fun reason(): BackgroundDownloadStopReason = stopReason.get()

  internal fun track(connection: HttpDownloadConnection): HttpDownloadConnection {
    val tracked = TrackedHttpDownloadConnection(connection, this)
    if (!activeConnection.compareAndSet(null, tracked)) {
      runCatching { tracked.close() }
      throw BackgroundDownloadStateException("An HTTP connection is already active")
    }
    if (reason().kind != BackgroundDownloadStopReason.Kind.none) {
      closeActiveConnection()
      throw ExecutionStopped(reason())
    }
    return tracked
  }

  internal fun untrack(connection: HttpDownloadConnection) {
    activeConnection.compareAndSet(connection, null)
  }

  private fun closeActiveConnection() {
    activeConnection.getAndSet(null)?.let { runCatching { it.close() } }
  }
}

private class TrackedHttpDownloadConnection(
  private val delegate: HttpDownloadConnection,
  private val control: BackgroundDownloadExecutionControl,
) : HttpDownloadConnection {
  private val closed = AtomicBoolean()
  override val statusCode: Int get() = delegate.statusCode
  override fun header(name: String): String? = delegate.header(name)
  override fun body() = delegate.body()
  override fun close() {
    if (closed.compareAndSet(false, true)) {
      control.untrack(this)
      delegate.close()
    }
  }
}

internal class BackgroundDownloadEngine(
  private val store: BackgroundDownloadStore,
  private val coordinator: BackgroundDownloadCoordinator,
  private val connectionFactory: HttpDownloadConnectionFactory,
  private val availableSpaceProvider: BackgroundDownloadAvailableSpaceProvider,
  private val nowElapsedMs: () -> Long = { System.nanoTime() / 1_000_000L },
  private val sleeper: (Long) -> Unit = Thread::sleep,
  private val stopSignal: () -> BackgroundDownloadStopReason = { BackgroundDownloadStopReason.none },
  private val progressListener: (BackgroundDownloadProgress) -> Unit = {},
  private val artifactWriterFactory: (File) -> BackgroundDownloadArtifactWriter = ::RandomAccessArtifactWriter,
  private val checkpointListener: (BackgroundDownloadRecord) -> Unit = {},
  private val verificationChunkListener: (Long) -> Unit = {},
  private val artifactMover: BackgroundDownloadArtifactMover = JvmBackgroundDownloadArtifactMover,
  private val artifactCleaner: BackgroundDownloadArtifactCleaner = JvmBackgroundDownloadArtifactCleaner,
  private val artifactInputStreamFactory: (File) -> InputStream = File::inputStream,
  private val beforeFailureTransition: () -> Unit = {},
) {
  private val activeExecutions = ConcurrentHashMap<String, Boolean>()
  private val executionOverrides = ThreadLocal<ExecutionOverrides>()

  fun execute(
    id: String,
    connectionFactory: HttpDownloadConnectionFactory = this.connectionFactory,
    stopSignal: () -> BackgroundDownloadStopReason = this.stopSignal,
    control: BackgroundDownloadExecutionControl = BackgroundDownloadExecutionControl(),
  ): BackgroundDownloadExecutionResult {
    BackgroundDownloadContract.requireValidId(id)
    if (activeExecutions.putIfAbsent(id, true) != null) {
      return BackgroundDownloadExecutionResult(
        BackgroundDownloadExecutionOutcome.alreadyRunning,
        runCatching { store.read(id) }.getOrNull(),
      )
    }
    executionOverrides.set(ExecutionOverrides(connectionFactory, stopSignal, control))
    return try {
      try {
        try {
          executeExclusive(id)
        } catch (error: BackgroundDownloadRecordWriteException) {
          waitForStorage(error.snapshot, "storage_write_error", null)
        } catch (_: BackgroundDownloadWriteException) {
          result(BackgroundDownloadExecutionOutcome.waitingForStorage, null)
        }
      } catch (stopped: ExecutionStopped) {
        handleStopAtExecutionBoundary(id, stopped.reason)
      }
    } finally {
      executionOverrides.remove()
      activeExecutions.remove(id)
    }
  }

  private fun executeExclusive(id: String): BackgroundDownloadExecutionResult {
    var record = readRecord(id)
    if (record.status == BackgroundDownloadStatus.canceled) return result(BackgroundDownloadExecutionOutcome.canceled, record)
    if (record.status.isTerminal) return result(
      if (record.status == BackgroundDownloadStatus.completed) BackgroundDownloadExecutionOutcome.completed
      else BackgroundDownloadExecutionOutcome.failed,
      record,
    )
    if (record.status == BackgroundDownloadStatus.verifying) {
      val reconciled = try {
        store.reconcileArtifacts(id)
      } catch (_: IOException) {
        return result(BackgroundDownloadExecutionOutcome.waitingForStorage, record)
      }
      return result(
        when (reconciled.status) {
          BackgroundDownloadStatus.completed -> BackgroundDownloadExecutionOutcome.completed
          BackgroundDownloadStatus.failed -> BackgroundDownloadExecutionOutcome.failed
          else -> BackgroundDownloadExecutionOutcome.pausedBySystem
        },
        reconciled,
      )
    }
    if (record.expectedSizeBytes > record.maxDownloadBytes ||
      record.expectedSizeBytes > BackgroundDownloadContract.MAX_DOWNLOAD_BYTES_CEILING
    ) {
      return fail(record, "size_limit_exceeded", "Expected package exceeds configured maximum")
    }

    record = when (record.status) {
      BackgroundDownloadStatus.waitingForNetwork,
      BackgroundDownloadStatus.waitingForStorage,
      BackgroundDownloadStatus.pausedBySystem,
      -> transition(record) {
        it.copy(
          status = BackgroundDownloadStatus.queued,
          lastStopReason = null,
          errorCode = null,
          errorMessage = null,
          nativeErrorCode = null,
        )
      }
      BackgroundDownloadStatus.queued -> record
      BackgroundDownloadStatus.running -> transition(record) {
        it.copy(status = BackgroundDownloadStatus.pausedBySystem)
      }.let { paused -> transition(paused) { it.copy(status = BackgroundDownloadStatus.queued) } }
      BackgroundDownloadStatus.verifying -> return fail(record, "invalid_engine_state", "Task is already verifying")
      else -> record
    }
    record = transition(record) {
      it.copy(
        status = BackgroundDownloadStatus.running,
        errorCode = null,
        errorMessage = null,
        nativeErrorCode = null,
      )
    }

    try {
      recoverDurableApk(record)?.let { return it }
    } catch (stopped: ExecutionStopped) {
      return handleStop(id, stopped.reason)
    } catch (write: BackgroundDownloadWriteException) {
      val snapshot = (write as? BackgroundDownloadRecordWriteException)?.snapshot ?: record
      return waitForStorage(snapshot, "storage_write_error", write.message)
    }

    val prepared = try {
      prepareCheckpoint(record)
    } catch (error: BackgroundDownloadWriteException) {
      return waitForStorage(record, "storage_write_error", error.message)
    }
    record = prepared.record

    val remaining = record.expectedSizeBytes - prepared.offset
    val headroom = max(MINIMUM_STORAGE_HEADROOM, ceilFivePercent(record.expectedSizeBytes))
    val available = try {
      availableSpaceProvider.availableBytes(store.taskDirectory(id))
    } catch (error: Exception) {
      return waitForStorage(record, "storage_query_error", error.message)
    }
    if (available < saturatingAdd(remaining, headroom)) {
      return waitForStorage(record, "insufficient_storage", "Insufficient storage for package")
    }

    var lastNetworkError: Throwable? = null
    val cleanRetryBudget = CleanRetryBudget(prepared.cleanRetryUsed)
    repeat(MAX_NETWORK_ATTEMPTS) { attempt ->
      try {
        checkStopped()
        return downloadAttempt(record, cleanRetryBudget)
      } catch (stopped: ExecutionStopped) {
        return handleStop(id, stopped.reason)
      } catch (checkpoint: BackgroundDownloadCheckpointWriteException) {
        return waitForStorageCheckpoint(checkpoint)
      } catch (write: BackgroundDownloadWriteException) {
        val snapshot = (write as? BackgroundDownloadRecordWriteException)?.snapshot ?: record
        return waitForStorage(snapshot, "storage_write_error", null)
      } catch (integrity: BackgroundDownloadIntegrityException) {
        return fail(currentNonterminal(id) ?: return canceledResult(id), integrity.code, integrity.message)
      } catch (tls: BackgroundDownloadTlsException) {
        return fail(currentNonterminal(id) ?: return canceledResult(id), "tls_error", tls.message)
      } catch (protocol: BackgroundDownloadProtocolException) {
        return fail(currentNonterminal(id) ?: return canceledResult(id), "protocol_error", protocol.message)
      } catch (network: RetryableNetworkException) {
        lastNetworkError = network
        if (attempt + 1 < MAX_NETWORK_ATTEMPTS) {
          try {
            cooperativeSleep(RETRY_DELAYS_MS[attempt])
          } catch (stopped: ExecutionStopped) {
            return handleStop(id, stopped.reason)
          }
        }
      } catch (error: Throwable) {
        val network = classifyConnectionFailure(error)
        if (network != null) {
          lastNetworkError = network
          if (attempt + 1 < MAX_NETWORK_ATTEMPTS) {
            try {
              cooperativeSleep(RETRY_DELAYS_MS[attempt])
            } catch (stopped: ExecutionStopped) {
              return handleStop(id, stopped.reason)
            }
          }
        } else {
          return fail(currentNonterminal(id) ?: return canceledResult(id), "engine_error", error.message)
        }
      }
    }
    val current = currentNonterminal(id) ?: return canceledResult(id)
    return transitionResult(
      current,
      BackgroundDownloadStatus.waitingForNetwork,
      BackgroundDownloadExecutionOutcome.waitingForNetwork,
      "network_error",
      lastNetworkError?.message,
    )
  }

  private fun downloadAttempt(
    initial: BackgroundDownloadRecord,
    cleanRetryBudget: CleanRetryBudget,
  ): BackgroundDownloadExecutionResult {
    var record = currentNonterminal(initial.id) ?: return canceledResult(initial.id)
    val partial = store.partialFile(record.id)
    var offset = record.downloadedBytes
    var etag = record.strongEtag?.takeIf(::isStrongEtag)

    while (true) {
      checkStopped()
      val response = openFollowingRedirects(record.packageUrl, offset, etag)
      response.use { connection ->
        val encoding = networkHeader(connection, "Content-Encoding")?.trim()
        if (!encoding.isNullOrBlank() && !encoding.equals("identity", ignoreCase = true)) {
          throw BackgroundDownloadProtocolException("Non-identity content encoding is not supported")
        }
        when (val statusCode = networkStatusCode(connection)) {
          200 -> {
            if (offset > 0) {
              record = cleanRestart(record, partial)
              offset = 0
              etag = null
            }
            validateCleanResponse(connection, record)
          }
          206 -> validatePartialResponse(connection, offset, record.expectedSizeBytes)
          416 -> {
            val total = parseUnsatisfiedRange(networkHeader(connection, "Content-Range"))
            if (total == record.expectedSizeBytes && offset == total && partial.length() == total) {
              closeNetworkConnection(connection)
              return verifyAndComplete(record, partial, etag)
            }
            if (!cleanRetryBudget.tryUse()) throw BackgroundDownloadProtocolException("Invalid 416 after clean retry")
            record = cleanRestart(record, partial)
            offset = 0
            etag = null
            continue
          }
          408, 429 -> throw RetryableNetworkException("HTTP $statusCode")
          in 500..599 -> throw RetryableNetworkException("HTTP $statusCode")
          else -> throw BackgroundDownloadProtocolException("Unexpected HTTP $statusCode")
        }

        val responseEtag = networkHeader(connection, "ETag")?.trim()?.takeIf(::isStrongEtag)
        if (offset > 0 && (responseEtag == null || responseEtag != etag)) {
          throw BackgroundDownloadProtocolException("Resumed response ETag is missing, weak, or changed")
        }
        val durableEtag = if (offset > 0) etag else responseEtag
        record = streamBody(connection, record, partial, offset, durableEtag)
        closeNetworkConnection(connection)
        return verifyAndComplete(record, partial, durableEtag)
      }
    }
  }

  private fun streamBody(
    connection: HttpDownloadConnection,
    startingRecord: BackgroundDownloadRecord,
    partial: File,
    offset: Long,
    strongEtag: String?,
  ): BackgroundDownloadRecord {
    var record = startingRecord
    var downloaded = offset
    var checkpointBytes = offset
    var checkpointAt = nowElapsedMs()
    var lastProgressAt = Long.MIN_VALUE
    var nextCancellationCheck = offset + CANCELLATION_CHECK_BYTES
    val buffer = ByteArray(64 * 1024)
    val writer = try {
      StorageClassifyingArtifactWriter(artifactWriterFactory(partial))
    } catch (error: Throwable) {
      throw BackgroundDownloadWriteException("Unable to open partial file", error)
    }
    writer.use { output ->
      try {
        output.truncate(offset)
        output.seek(offset)
      } catch (error: Throwable) {
        throw BackgroundDownloadWriteException("Unable to prepare partial file", error)
      }
      val input = try {
        connection.body()
      } catch (error: Throwable) {
        throw classifyNetworkBoundaryFailure(error)
      }
      try {
        input.use {
        try {
          while (true) {
            checkStopped()
            if (downloaded >= nextCancellationCheck) {
              if (readRecord(record.id).status == BackgroundDownloadStatus.canceled) {
                throw ExecutionStopped(BackgroundDownloadStopReason.cancel)
              }
              nextCancellationCheck = downloaded + CANCELLATION_CHECK_BYTES
            }
            val read = try {
              input.read(buffer)
            } catch (error: Throwable) {
              throw classifyNetworkBoundaryFailure(error)
            }
            if (read < 0) break
            if (read == 0) continue
            if (downloaded + read > record.expectedSizeBytes || downloaded + read > record.maxDownloadBytes ||
              downloaded + read > BackgroundDownloadContract.MAX_DOWNLOAD_BYTES_CEILING
            ) {
              throw BackgroundDownloadIntegrityException("Response exceeds expected package size", "size_limit_exceeded")
            }
            try {
              output.write(buffer, 0, read)
            } catch (error: Throwable) {
              throw BackgroundDownloadWriteException("Unable to write partial file", error)
            }
            downloaded += read
            val now = nowElapsedMs()
            if (now - lastProgressAt >= PROGRESS_INTERVAL_MS || lastProgressAt == Long.MIN_VALUE) {
              checkStopped()
              val offered = try {
                coordinator.offerProgress(record.id, downloaded, record.expectedSizeBytes)
              } catch (error: IOException) {
                throw BackgroundDownloadRecordWriteException(record, error)
              }
              if (offered == null) throw ExecutionStopped(BackgroundDownloadStopReason.cancel)
              coordinator.pollProgress()?.let { progress ->
                runCatching {
                  progressListener(progress)
                }
              }
              if (currentNonterminal(record.id) == null) {
                throw ExecutionStopped(BackgroundDownloadStopReason.cancel)
              }
              lastProgressAt = now
            }
            if (strongEtag != null &&
              (downloaded - checkpointBytes >= CHECKPOINT_BYTES || now - checkpointAt >= CHECKPOINT_INTERVAL_MS)
            ) {
              record = persistCheckpoint(output, record, downloaded, strongEtag)
              checkpointBytes = downloaded
              checkpointAt = now
            }
          }
        } catch (stopped: ExecutionStopped) {
          if (stopped.reason.kind == BackgroundDownloadStopReason.Kind.system &&
            strongEtag != null && downloaded > record.downloadedBytes
          ) {
            record = persistCheckpoint(output, record, downloaded, strongEtag)
          }
          throw stopped
        } catch (network: RetryableNetworkException) {
          val stop = requestedStopReason()
          if (stop.kind != BackgroundDownloadStopReason.Kind.none) {
            if (stop.kind == BackgroundDownloadStopReason.Kind.system &&
              strongEtag != null && downloaded > record.downloadedBytes
            ) {
              record = persistCheckpoint(output, record, downloaded, strongEtag)
            }
            throw ExecutionStopped(stop)
          }
          if (strongEtag != null && downloaded > record.downloadedBytes) {
            record = persistCheckpoint(output, record, downloaded, strongEtag)
          }
          throw network
        }
        }
      } catch (error: IOException) {
        val classified = classifyNetworkBoundaryFailure(error)
        if (classified is RetryableNetworkException) {
          val stop = requestedStopReason()
          if (stop.kind != BackgroundDownloadStopReason.Kind.none) {
            if (stop.kind == BackgroundDownloadStopReason.Kind.system &&
              strongEtag != null && downloaded > record.downloadedBytes
            ) {
              record = persistCheckpoint(output, record, downloaded, strongEtag)
            }
            throw ExecutionStopped(stop)
          }
          if (strongEtag != null && downloaded > record.downloadedBytes) {
            record = persistCheckpoint(output, record, downloaded, strongEtag)
          }
        }
        throw classified
      }
      if (downloaded != record.expectedSizeBytes) {
        val stop = requestedStopReason()
        if (stop.kind != BackgroundDownloadStopReason.Kind.none) {
          if (stop.kind == BackgroundDownloadStopReason.Kind.system &&
            strongEtag != null && downloaded > record.downloadedBytes
          ) {
            record = persistCheckpoint(output, record, downloaded, strongEtag)
          }
          throw ExecutionStopped(stop)
        }
        throw BackgroundDownloadIntegrityException("Downloaded size does not match expected size")
      }
      try {
        output.flush()
      } catch (error: Throwable) {
        throw BackgroundDownloadWriteException("Unable to flush partial file", error)
      }
      record = updateDownloaded(record, downloaded, strongEtag)
    }
    return record
  }

  private fun persistCheckpoint(
    output: BackgroundDownloadArtifactWriter,
    record: BackgroundDownloadRecord,
    downloaded: Long,
    strongEtag: String,
  ): BackgroundDownloadRecord {
    try {
      output.flush()
    } catch (error: Throwable) {
      throw BackgroundDownloadWriteException("Unable to flush checkpoint", error)
    }
    val updated = try {
      updateDownloaded(record, downloaded, strongEtag)
    } catch (error: BackgroundDownloadRecordWriteException) {
      throw BackgroundDownloadCheckpointWriteException(record, downloaded, strongEtag, error)
    }
    runCatching { checkpointListener(updated) }
    return updated
  }

  private fun updateDownloaded(
    record: BackgroundDownloadRecord,
    downloaded: Long,
    strongEtag: String?,
  ): BackgroundDownloadRecord {
    val current = currentNonterminal(record.id) ?: throw ExecutionStopped(BackgroundDownloadStopReason.cancel)
    return transition(current) {
      it.copy(
        status = BackgroundDownloadStatus.running,
        downloadedBytes = downloaded,
        totalBytes = it.expectedSizeBytes,
        strongEtag = strongEtag,
      )
    }
  }

  private fun verifyAndComplete(
    record: BackgroundDownloadRecord,
    partial: File,
    strongEtag: String?,
  ): BackgroundDownloadExecutionResult {
    checkStopped()
    if (partial.length() != record.expectedSizeBytes) {
      throw BackgroundDownloadIntegrityException("Partial artifact has unexpected size")
    }
    val actualHash = try {
      sha256(partial, record.id)
    } catch (error: IOException) {
      throw BackgroundDownloadWriteException("Unable to read package for verification", error)
    }
    if (actualHash != record.expectedSha256) {
      throw BackgroundDownloadIntegrityException("Downloaded package hash does not match", "hash_mismatch")
    }
    checkStopped()
    checkCanceled(record.id)
    val apk = store.apkFile(record.id)
    if (apk.exists() && !artifactCleaner.delete(apk)) {
      throw BackgroundDownloadWriteException("Unable to replace APK")
    }
    try {
      artifactMover.moveAtomically(partial, apk)
      checkCanceled(record.id)
      artifactMover.syncDirectory(apk.parentFile ?: store.taskDirectory(record.id))
      checkCanceled(record.id)
    } catch (error: ExecutionStopped) {
      throw error
    } catch (error: IOException) {
      throw BackgroundDownloadWriteException("Unable to durably move APK", error)
    }
    val current = currentNonterminal(record.id) ?: return canceledResult(record.id)
    val verifying = transition(current) {
      it.copy(
        status = BackgroundDownloadStatus.verifying,
        downloadedBytes = it.expectedSizeBytes,
        totalBytes = it.expectedSizeBytes,
        strongEtag = strongEtag,
      )
    }
    checkCanceled(verifying.id)
    val completed = try {
      coordinator.complete(record.id, verifying.revision)
    } catch (error: IOException) {
      throw BackgroundDownloadRecordWriteException(verifying, error)
    } catch (error: BackgroundDownloadRevisionException) {
      val latest = readRecord(record.id)
      if (latest.status == BackgroundDownloadStatus.canceled) {
        runCatching { coordinator.cancel(record.id) }
        return result(BackgroundDownloadExecutionOutcome.canceled, readRecord(record.id))
      }
      throw error
    }
    return result(BackgroundDownloadExecutionOutcome.completed, completed)
  }

  private fun recoverDurableApk(record: BackgroundDownloadRecord): BackgroundDownloadExecutionResult? {
    val apk = store.apkFile(record.id)
    if (!apk.isFile) return null
    val valid = try {
      apk.length() == record.expectedSizeBytes && sha256(apk, record.id) == record.expectedSha256
    } catch (error: IOException) {
      throw BackgroundDownloadWriteException("Unable to read recovered APK", error)
    }
    if (!valid) {
      val deleted = try {
        artifactCleaner.delete(apk)
      } catch (error: IOException) {
        throw BackgroundDownloadWriteException("Unable to remove invalid APK", error)
      }
      if (!deleted || apk.exists()) throw BackgroundDownloadWriteException("Unable to remove invalid APK")
      return null
    }
    checkStopped()
    try {
      artifactMover.syncDirectory(apk.parentFile ?: store.taskDirectory(record.id))
    } catch (error: IOException) {
      throw BackgroundDownloadWriteException("Unable to sync recovered APK", error)
    }
    checkCanceled(record.id)
    val current = currentNonterminal(record.id) ?: return canceledResult(record.id)
    val verifying = transition(current) {
      it.copy(
        status = BackgroundDownloadStatus.verifying,
        downloadedBytes = it.expectedSizeBytes,
        totalBytes = it.expectedSizeBytes,
      )
    }
    val completed = try {
      coordinator.complete(record.id, verifying.revision)
    } catch (error: IOException) {
      throw BackgroundDownloadRecordWriteException(verifying, error)
    }
    return result(BackgroundDownloadExecutionOutcome.completed, completed)
  }

  private fun prepareCheckpoint(record: BackgroundDownloadRecord): PreparedCheckpoint {
    val partial = store.partialFile(record.id)
    val validStrong = record.strongEtag?.takeIf(::isStrongEtag)
    if (record.downloadedBytes <= 0 || validStrong == null) {
      if (partial.exists()) truncateFile(partial, 0)
      val reset = if (record.downloadedBytes != 0L || record.strongEtag != null || record.totalBytes != null) {
        transition(record) {
          it.copy(downloadedBytes = 0, totalBytes = null, strongEtag = null)
        }
      } else record
      return PreparedCheckpoint(reset, 0, false)
    }
    if (!partial.isFile || partial.length() < record.downloadedBytes) {
      if (partial.exists()) truncateFile(partial, 0)
      val reset = transition(record) { it.copy(downloadedBytes = 0, totalBytes = null, strongEtag = null) }
      return PreparedCheckpoint(reset, 0, false)
    }
    if (partial.length() > record.downloadedBytes) truncateFile(partial, record.downloadedBytes)
    return PreparedCheckpoint(record, record.downloadedBytes, false)
  }

  private fun cleanRestart(record: BackgroundDownloadRecord, partial: File): BackgroundDownloadRecord {
    truncateFile(partial, 0)
    val current = currentNonterminal(record.id) ?: throw ExecutionStopped(BackgroundDownloadStopReason.cancel)
    return transition(current) { it.copy(downloadedBytes = 0, totalBytes = null, strongEtag = null) }
  }

  private fun truncateFile(file: File, length: Long) {
    try {
      StorageClassifyingArtifactWriter(artifactWriterFactory(file)).use { writer ->
        writer.truncate(length)
        writer.flush()
      }
    } catch (error: BackgroundDownloadWriteException) {
      throw error
    } catch (error: Throwable) {
      throw BackgroundDownloadWriteException("Unable to truncate partial file", error)
    }
  }

  private fun openFollowingRedirects(
    originalUrl: String,
    offset: Long,
    etag: String?,
  ): HttpDownloadConnection {
    var current = originalUrl
    var redirects = 0
    while (true) {
      requireAllowedUrl(current)
      val headers = linkedMapOf("Accept-Encoding" to "identity")
      if (offset > 0 && etag != null) {
        headers["Range"] = "bytes=$offset-"
        headers["If-Range"] = etag
      }
      val connection = try {
        val opened = activeConnectionFactory().open(HttpDownloadRequest(current, headers))
        activeControl().track(opened)
      } catch (error: Throwable) {
        if (error is ExecutionStopped) throw error
        throw classifyNetworkBoundaryFailure(error)
      }
      val statusCode = try {
        networkStatusCode(connection)
      } catch (error: Throwable) {
        runCatching { connection.close() }
        throw error
      }
      if (statusCode !in REDIRECT_CODES) return connection
      val location = try {
        networkHeader(connection, "Location")
      } finally {
        closeNetworkConnection(connection)
      }
      if (location.isNullOrBlank()) throw BackgroundDownloadProtocolException("Redirect is missing Location")
      if (redirects++ >= MAX_REDIRECTS) throw BackgroundDownloadProtocolException("Too many redirects")
      current = URI(current).resolve(location).toString()
      requireAllowedUrl(current)
      val from = URI(originalUrl)
      val to = URI(current)
      if (from.scheme.equals("https", true) && to.scheme.equals("http", true) &&
        !BackgroundDownloadUrlPolicy.isAllowed(to.toString())
      ) {
        throw BackgroundDownloadProtocolException("HTTPS redirect downgrade is not allowed")
      }
    }
  }

  private fun closeNetworkConnection(connection: HttpDownloadConnection) {
    try {
      connection.close()
    } catch (error: Throwable) {
      throw classifyNetworkBoundaryFailure(error)
    }
  }

  private fun validateCleanResponse(connection: HttpDownloadConnection, record: BackgroundDownloadRecord) {
    val length = parseOptionalLength(networkHeader(connection, "Content-Length"))
    if (length != null && length != record.expectedSizeBytes) {
      throw BackgroundDownloadIntegrityException("Content-Length does not match expected size")
    }
  }

  private fun validatePartialResponse(connection: HttpDownloadConnection, offset: Long, total: Long) {
    if (offset <= 0) throw BackgroundDownloadProtocolException("Unexpected 206 without resume checkpoint")
    val match = CONTENT_RANGE.matchEntire(networkHeader(connection, "Content-Range")?.trim().orEmpty())
      ?: throw BackgroundDownloadProtocolException("Malformed Content-Range")
    val start = match.groupValues[1].toLongOrNull()
    val end = match.groupValues[2].toLongOrNull()
    val responseTotal = match.groupValues[3].toLongOrNull()
    if (start != offset || end == null || responseTotal != total || end < start || end >= total) {
      throw BackgroundDownloadProtocolException("Content-Range does not match checkpoint")
    }
    val span = end - start + 1
    val length = parseOptionalLength(networkHeader(connection, "Content-Length"))
      ?: throw BackgroundDownloadProtocolException("Resumed response is missing Content-Length")
    if (length != span) {
      throw BackgroundDownloadProtocolException("Content-Length does not match Content-Range")
    }
  }

  private fun parseUnsatisfiedRange(value: String?): Long? =
    UNSATISFIED_RANGE.matchEntire(value?.trim().orEmpty())?.groupValues?.get(1)?.toLongOrNull()

  private fun parseOptionalLength(value: String?): Long? {
    if (value == null) return null
    return value.trim().toLongOrNull()?.takeIf { it >= 0 }
      ?: throw BackgroundDownloadProtocolException("Malformed Content-Length")
  }

  private fun handleStop(id: String, reason: BackgroundDownloadStopReason): BackgroundDownloadExecutionResult {
    val latest = readRecord(id)
    if (latest.status == BackgroundDownloadStatus.canceled) {
      return result(BackgroundDownloadExecutionOutcome.canceled, latest)
    }
    if (latest.status.isTerminal) return result(
      if (latest.status == BackgroundDownloadStatus.completed) BackgroundDownloadExecutionOutcome.completed else BackgroundDownloadExecutionOutcome.failed,
      latest,
    )
    if (reason.kind == BackgroundDownloadStopReason.Kind.cancel) {
      val canceled = try {
        coordinator.cancel(id)
      } catch (_: IOException) {
        return waitForStorage(latest, "storage_write_error", null)
      }
      return result(BackgroundDownloadExecutionOutcome.canceled, canceled)
    }
    val paused = transition(latest) {
      it.copy(
        status = BackgroundDownloadStatus.pausedBySystem,
        lastStopReason = reason.nativeReason,
        errorCode = null,
        errorMessage = null,
        nativeErrorCode = null,
      )
    }
    return result(BackgroundDownloadExecutionOutcome.pausedBySystem, paused)
  }

  private fun cooperativeSleep(millis: Long) {
    checkStopped()
    try {
      sleeper(millis)
    } catch (_: InterruptedException) {
      Thread.currentThread().interrupt()
      throw ExecutionStopped(BackgroundDownloadStopReason.system())
    }
    checkStopped()
  }

  private fun checkStopped() {
    val reason = requestedStopReason()
    if (reason.kind != BackgroundDownloadStopReason.Kind.none) throw ExecutionStopped(reason)
  }

  private fun requestedStopReason(): BackgroundDownloadStopReason {
    val controlled = activeControl().reason()
    return if (controlled.kind != BackgroundDownloadStopReason.Kind.none) controlled else activeStopSignal()()
  }

  private fun checkCanceled(id: String) {
    val storedStatus = try {
      store.read(id).status
    } catch (error: IOException) {
      throw BackgroundDownloadWriteException("Task record storage read failed", error)
    }
    if (activeControl().reason().kind == BackgroundDownloadStopReason.Kind.cancel ||
      activeStopSignal()().kind == BackgroundDownloadStopReason.Kind.cancel ||
      storedStatus == BackgroundDownloadStatus.canceled
    ) {
      throw ExecutionStopped(BackgroundDownloadStopReason.cancel)
    }
  }

  private fun activeConnectionFactory(): HttpDownloadConnectionFactory =
    executionOverrides.get()?.connectionFactory ?: connectionFactory

  private fun activeStopSignal(): () -> BackgroundDownloadStopReason =
    executionOverrides.get()?.stopSignal ?: stopSignal

  private fun activeControl(): BackgroundDownloadExecutionControl =
    checkNotNull(executionOverrides.get()).control

  private fun currentNonterminal(id: String): BackgroundDownloadRecord? {
    val latest = readRecord(id)
    return latest.takeUnless { it.status.isTerminal }
  }

  private fun readRecord(id: String): BackgroundDownloadRecord = try {
    store.read(id)
  } catch (error: IOException) {
    throw BackgroundDownloadWriteException("Task record storage read failed", error)
  }

  private fun waitForStorage(
    record: BackgroundDownloadRecord,
    code: String,
    message: String?,
  ): BackgroundDownloadExecutionResult = if (
    record.status == BackgroundDownloadStatus.queued ||
    record.status == BackgroundDownloadStatus.verifying
  ) {
    result(BackgroundDownloadExecutionOutcome.waitingForStorage, record)
  } else try {
    transitionResult(
      record,
      BackgroundDownloadStatus.waitingForStorage,
      BackgroundDownloadExecutionOutcome.waitingForStorage,
      code,
      message,
    )
  } catch (error: BackgroundDownloadRecordWriteException) {
    result(BackgroundDownloadExecutionOutcome.waitingForStorage, error.snapshot)
  } catch (_: BackgroundDownloadWriteException) {
    result(BackgroundDownloadExecutionOutcome.waitingForStorage, record)
  }

  private fun waitForStorageCheckpoint(
    error: BackgroundDownloadCheckpointWriteException,
  ): BackgroundDownloadExecutionResult {
    val current = try {
      store.read(error.snapshot.id)
    } catch (_: IOException) {
      return result(BackgroundDownloadExecutionOutcome.waitingForStorage, error.snapshot)
    }
    if (current.status == BackgroundDownloadStatus.canceled) {
      return result(BackgroundDownloadExecutionOutcome.canceled, current)
    }
    return try {
      val waiting = transition(current) {
        it.copy(
          status = BackgroundDownloadStatus.waitingForStorage,
          downloadedBytes = error.downloadedBytes,
          totalBytes = it.expectedSizeBytes,
          strongEtag = error.strongEtag,
          errorCode = publicErrorCode("storage_write_error"),
          errorMessage = safeErrorMessage("storage_write_error"),
          nativeErrorCode = "storage_write_error",
        )
      }
      result(BackgroundDownloadExecutionOutcome.waitingForStorage, waiting)
    } catch (write: BackgroundDownloadRecordWriteException) {
      result(BackgroundDownloadExecutionOutcome.waitingForStorage, write.snapshot)
    } catch (_: BackgroundDownloadWriteException) {
      result(BackgroundDownloadExecutionOutcome.waitingForStorage, current)
    }
  }

  private fun transitionResult(
    record: BackgroundDownloadRecord,
    status: BackgroundDownloadStatus,
    outcome: BackgroundDownloadExecutionOutcome,
    code: String,
    message: String?,
  ): BackgroundDownloadExecutionResult {
    val latest = currentNonterminal(record.id) ?: return canceledResult(record.id)
    val updated = transition(latest) {
      it.copy(
        status = status,
        errorCode = publicErrorCode(code),
        errorMessage = safeErrorMessage(code),
        nativeErrorCode = code,
      )
    }
    return result(outcome, updated)
  }

  private fun fail(
    record: BackgroundDownloadRecord,
    code: String,
    message: String?,
  ): BackgroundDownloadExecutionResult {
    beforeFailureTransition()
    // Invalidate the durable checkpoint before deleting bytes. If record
    // storage is unavailable, retain the artifact and its truthful checkpoint.
    var failureBase = record
    if (record.status == BackgroundDownloadStatus.running) {
      failureBase = try {
        transition(record) {
          it.copy(
            status = BackgroundDownloadStatus.waitingForStorage,
            downloadedBytes = 0,
            totalBytes = null,
            strongEtag = null,
            errorCode = publicErrorCode("storage_write_error"),
            errorMessage = safeErrorMessage("storage_write_error"),
            nativeErrorCode = "storage_write_error",
          )
        }
      } catch (write: BackgroundDownloadRecordWriteException) {
        return result(BackgroundDownloadExecutionOutcome.waitingForStorage, write.snapshot)
      }
    }

    if (!cleanupUnsafeArtifacts(record.id)) {
      return if (failureBase.status == BackgroundDownloadStatus.waitingForStorage) {
        try {
          transitionResult(
            failureBase,
            BackgroundDownloadStatus.waitingForStorage,
            BackgroundDownloadExecutionOutcome.waitingForStorage,
            "storage_cleanup_error",
            null,
          )
        } catch (_: BackgroundDownloadWriteException) {
          result(BackgroundDownloadExecutionOutcome.waitingForStorage, failureBase)
        }
      } else {
        result(BackgroundDownloadExecutionOutcome.waitingForStorage, failureBase)
      }
    }

    val latest = currentNonterminal(record.id) ?: return canceledResult(record.id)
    val failed = try {
      transition(latest) {
        it.copy(
          status = BackgroundDownloadStatus.failed,
          downloadedBytes = 0,
          totalBytes = null,
          strongEtag = null,
          errorCode = publicErrorCode(code),
          errorMessage = safeErrorMessage(code),
          nativeErrorCode = code,
        )
      }
    } catch (write: BackgroundDownloadRecordWriteException) {
      return result(
        BackgroundDownloadExecutionOutcome.waitingForStorage,
        if (failureBase.status == BackgroundDownloadStatus.waitingForStorage) failureBase else write.snapshot,
      )
    }
    return result(BackgroundDownloadExecutionOutcome.failed, failed)
  }

  private fun handleStopAtExecutionBoundary(
    id: String,
    reason: BackgroundDownloadStopReason,
  ): BackgroundDownloadExecutionResult = try {
    handleStop(id, reason)
  } catch (raced: ExecutionStopped) {
    if (raced.reason.kind == BackgroundDownloadStopReason.Kind.cancel) {
      canceledResult(id)
    } else {
      throw raced
    }
  } catch (write: BackgroundDownloadRecordWriteException) {
    waitForStorage(write.snapshot, "storage_write_error", null)
  } catch (_: BackgroundDownloadWriteException) {
    result(BackgroundDownloadExecutionOutcome.waitingForStorage, null)
  }

  private fun cleanupUnsafeArtifacts(id: String): Boolean {
    // Delete the non-checkpoint APK first. If deleting the partial then fails,
    // the durable downloadedBytes/ETag checkpoint still describes a real file.
    for (artifact in listOf(store.apkFile(id), store.partialFile(id))) {
      if (artifact.exists()) {
        val deleted = try {
          artifactCleaner.delete(artifact)
        } catch (_: Exception) {
          false
        }
        if (!deleted || artifact.exists()) return false
      }
    }
    return true
  }

  private fun transition(
    record: BackgroundDownloadRecord,
    update: (BackgroundDownloadRecord) -> BackgroundDownloadRecord,
  ): BackgroundDownloadRecord = try {
    coordinator.transition(record.id, record.revision, update)
  } catch (error: IOException) {
    throw BackgroundDownloadRecordWriteException(record, error)
  } catch (error: BackgroundDownloadRevisionException) {
    val latest = try {
      store.read(record.id)
    } catch (storage: IOException) {
      throw BackgroundDownloadRecordWriteException(record, storage)
    }
    if (latest.status == BackgroundDownloadStatus.canceled) throw ExecutionStopped(BackgroundDownloadStopReason.cancel)
    throw error
  }

  private fun canceledResult(id: String): BackgroundDownloadExecutionResult =
    result(BackgroundDownloadExecutionOutcome.canceled, runCatching { store.read(id) }.getOrNull())

  private fun result(
    outcome: BackgroundDownloadExecutionOutcome,
    record: BackgroundDownloadRecord?,
  ) = BackgroundDownloadExecutionResult(outcome, record)

  private fun classifyConnectionFailure(error: Throwable): RetryableNetworkException? = when (error) {
    is SocketTimeoutException,
    is ConnectException,
    is UnknownHostException,
    is NoRouteToHostException,
    is SocketException,
    -> RetryableNetworkException(error.message ?: "Network failure", error)
    else -> null
  }

  private fun publicErrorCode(nativeCode: String): String = when (nativeCode) {
    "hash_mismatch" -> "PACKAGE_HASH_MISMATCH"
    "size_limit_exceeded" -> "PACKAGE_TOO_LARGE"
    "insufficient_storage", "storage_query_error", "storage_write_error", "storage_cleanup_error" -> "BACKGROUND_STORAGE_UNAVAILABLE"
    else -> "PACKAGE_DOWNLOAD_FAILED"
  }

  private fun safeErrorMessage(nativeCode: String): String = when (nativeCode) {
    "hash_mismatch" -> "Downloaded package hash verification failed."
    "size_limit_exceeded" -> "Downloaded package exceeds the allowed size."
    "insufficient_storage" -> "Insufficient storage is available for the download."
    "storage_query_error", "storage_write_error", "storage_cleanup_error" -> "Package storage is temporarily unavailable."
    "network_error" -> "The download is waiting for a network connection."
    "tls_error" -> "The secure download connection could not be verified."
    "protocol_error" -> "The download server returned an invalid response."
    "integrity_error" -> "Downloaded package integrity verification failed."
    else -> "The package download failed."
  }

  private fun classifyNetworkBoundaryFailure(error: Throwable): Throwable = when (error) {
    is SSLException -> BackgroundDownloadTlsException(error)
    else -> classifyConnectionFailure(error)
      ?: if (error is IOException) RetryableNetworkException("Network I/O failure", error) else error
  }

  private fun networkStatusCode(connection: HttpDownloadConnection): Int = try {
    connection.statusCode
  } catch (error: Throwable) {
    throw classifyNetworkBoundaryFailure(error)
  }

  private fun networkHeader(connection: HttpDownloadConnection, name: String): String? = try {
    connection.header(name)
  } catch (error: Throwable) {
    throw classifyNetworkBoundaryFailure(error)
  }

  private fun requireAllowedUrl(value: String) {
    if (BackgroundDownloadUrlPolicy.isAllowed(value)) return
    throw BackgroundDownloadProtocolException("Download URL must use HTTPS")
  }

  private fun isStrongEtag(value: String): Boolean =
    !value.startsWith("W/", ignoreCase = true) && value.length >= 2 && value.first() == '"' && value.last() == '"'

  private fun sha256(file: File, id: String): String {
    val digest = MessageDigest.getInstance("SHA-256")
    var verifiedBytes = 0L
    var nextCancellationCheck = CANCELLATION_CHECK_BYTES
    artifactInputStreamFactory(file).buffered().use { input ->
      val buffer = ByteArray(64 * 1024)
      while (true) {
        val read = input.read(buffer)
        if (read < 0) break
        if (read > 0) {
          digest.update(buffer, 0, read)
          verifiedBytes += read
          verificationChunkListener(verifiedBytes)
          checkStopped()
          if (verifiedBytes >= nextCancellationCheck) {
            checkCanceled(id)
            nextCancellationCheck = verifiedBytes + CANCELLATION_CHECK_BYTES
          }
        }
      }
    }
    return digest.digest().joinToString("") { "%02x".format(it) }
  }

  private fun ceilFivePercent(value: Long): Long = value / 20 + if (value % 20 == 0L) 0 else 1

  private fun saturatingAdd(left: Long, right: Long): Long =
    if (Long.MAX_VALUE - left < right) Long.MAX_VALUE else left + right

  private data class PreparedCheckpoint(
    val record: BackgroundDownloadRecord,
    val offset: Long,
    val cleanRetryUsed: Boolean,
  )

  private data class ExecutionOverrides(
    val connectionFactory: HttpDownloadConnectionFactory,
    val stopSignal: () -> BackgroundDownloadStopReason,
    val control: BackgroundDownloadExecutionControl,
  )

  private class CleanRetryBudget(usedInitially: Boolean) {
    private var used = usedInitially

    fun tryUse(): Boolean {
      if (used) return false
      used = true
      return true
    }
  }

  private companion object {
    const val CHECKPOINT_BYTES = 4L * 1024 * 1024
    const val CHECKPOINT_INTERVAL_MS = 2_000L
    const val PROGRESS_INTERVAL_MS = 250L
    const val CANCELLATION_CHECK_BYTES = 1024L * 1024
    const val MINIMUM_STORAGE_HEADROOM = 64L * 1024 * 1024
    const val MAX_NETWORK_ATTEMPTS = 3
    const val MAX_REDIRECTS = 5
    val RETRY_DELAYS_MS = longArrayOf(250, 500)
    val REDIRECT_CODES = setOf(301, 302, 303, 307, 308)
    val CONTENT_RANGE = Regex("bytes (\\d+)-(\\d+)/(\\d+)")
    val UNSATISFIED_RANGE = Regex("bytes \\*/(\\d+)")
  }
}
