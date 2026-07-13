package com.indiegeeker.flutter_app_updater.background

import android.content.Context
import io.flutter.plugin.common.EventChannel
import java.net.URI
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/** Process-local fan-out for revisioned download snapshots. */
internal class BackgroundDownloadEventBus {
  private val lock = Any()
  private val listeners = linkedMapOf<Long, ListenerRegistration>()
  private val latestByTask = mutableMapOf<String, PublishedState>()
  private var nextListenerId = 1L

  val listenerCount: Int
    get() = synchronized(lock) { listeners.size }

  val hasListeners: Boolean
    get() = listenerCount > 0

  fun addListener(listener: (Map<String, Any?>) -> Unit): AutoCloseable {
    val registration = ListenerRegistration(listener)
    val (id, replay) = synchronized(lock) {
      val listenerId = nextListenerId.also {
        nextListenerId += 1
        listeners[it] = registration
      }
      listenerId to latestByTask.values.map { it.snapshot }
    }
    // A new EventChannel attachment must see terminal and other latest states.
    replay.forEach(registration::offer)
    val closed = AtomicBoolean()
    return AutoCloseable {
      if (closed.compareAndSet(false, true)) {
        synchronized(lock) { listeners.remove(id) }
        registration.close()
      }
    }
  }

  fun publish(record: BackgroundDownloadRecord, filePath: String? = null) {
    publishSnapshot(
      record.toMap(filePath),
      PublishedState(
        revision = record.revision,
        downloadedBytes = record.downloadedBytes,
        terminal = record.status.isTerminal,
        snapshot = record.toMap(filePath),
      ),
    )
  }

  /**
   * Progress keeps the durable revision. Dart deliberately deduplicates equal
   * revisions; durable checkpoint snapshots remain the cross-isolate contract.
   */
  fun publishProgress(progress: BackgroundDownloadProgress, record: BackgroundDownloadRecord) {
    if (record.id != progress.id || record.status.isTerminal || record.revision != progress.revision) return
    publishSnapshot(
      record.toMap().toMutableMap().apply {
        this["downloadedBytes"] = progress.downloadedBytes
        this["totalBytes"] = progress.totalBytes
      },
      PublishedState(
        revision = progress.revision,
        downloadedBytes = progress.downloadedBytes,
        terminal = false,
        snapshot = record.toMap().toMutableMap().apply {
          this["downloadedBytes"] = progress.downloadedBytes
          this["totalBytes"] = progress.totalBytes
        },
      ),
    )
  }

  fun forget(id: String) {
    synchronized(lock) { latestByTask.remove(id) }
  }

  private fun publishSnapshot(snapshot: Map<String, Any?>, next: PublishedState) {
    val id = snapshot["id"] as? String ?: return
    val targets = synchronized(lock) {
      val latest = latestByTask[id]
      if (latest?.terminal == true ||
        (latest != null && next.revision < latest.revision) ||
        (latest != null && next.revision == latest.revision && next.downloadedBytes <= latest.downloadedBytes)
      ) {
        return
      }
      latestByTask[id] = next
      listeners.values.toList()
    }
    // User/Flutter callbacks are intentionally outside the event-bus lock.
    targets.forEach { listener -> listener.offer(snapshot) }
  }

  private data class PublishedState(
    val revision: Long,
    val downloadedBytes: Long,
    val terminal: Boolean,
    val snapshot: Map<String, Any?>,
  )

  /** Serializes and deduplicates one listener without holding the bus lock. */
  private class ListenerRegistration(
    private val listener: (Map<String, Any?>) -> Unit,
  ) {
    private val lock = Any()
    private val latestByTask = mutableMapOf<String, Pair<Long, Long>>()
    private val queue = ArrayDeque<Map<String, Any?>>()
    private var active = true
    private var draining = false

    fun offer(snapshot: Map<String, Any?>) {
      val shouldDrain = synchronized(lock) {
        if (!active) return
        val id = snapshot["id"] as? String ?: return
        val revision = (snapshot["revision"] as? Number)?.toLong() ?: return
        val downloaded = (snapshot["downloadedBytes"] as? Number)?.toLong() ?: return
        val latest = latestByTask[id]
        if (latest != null &&
          (revision < latest.first || (revision == latest.first && downloaded <= latest.second))
        ) {
          return
        }
        latestByTask[id] = revision to downloaded
        queue.addLast(snapshot)
        if (draining) false else true.also { draining = true }
      }
      if (shouldDrain) drain()
    }

    fun close() {
      synchronized(lock) {
        active = false
        queue.clear()
      }
    }

    private fun drain() {
      while (true) {
        val next = synchronized(lock) {
          if (!active || queue.isEmpty()) {
            draining = false
            null
          } else {
            queue.removeFirst()
          }
        } ?: return
        runCatching { listener(next) }
      }
    }
  }
}

internal object BackgroundDownloadUrlPolicy {
  fun isAllowed(value: String): Boolean {
    val uri = try {
      URI(value)
    } catch (_: Exception) {
      return false
    }
    val rawHost = uri.host?.lowercase()?.trim().orEmpty()
    if (!uri.isAbsolute || rawHost.isBlank()) return false
    if (uri.scheme.equals("https", true)) return true
    if (!uri.scheme.equals("http", true)) return false
    val host = rawHost.removePrefix("[").removeSuffix("]")
    return host == "localhost" || host == "::1" || isIpv4Loopback(host)
  }

  private fun isIpv4Loopback(host: String): Boolean {
    val parts = host.split('.')
    if (parts.size != 4) return false
    val octets = parts.map { part ->
      if (part.isEmpty() || part.any { !it.isDigit() }) return false
      part.toIntOrNull()?.takeIf { it in 0..255 } ?: return false
    }
    return octets.first() == 127
  }
}

internal class BackgroundDownloadPluginException(
  val code: String,
  message: String,
  cause: Throwable? = null,
) : Exception(message, cause)

internal fun interface BackgroundDownloadPluginCompletion {
  fun complete(result: Result<Any?>)
}

internal interface BackgroundDownloadPluginDelegate {
  fun execute(method: String, arguments: Any?, completion: BackgroundDownloadPluginCompletion)
  fun observe(listener: (Map<String, Any?>) -> Unit): AutoCloseable
}

/** Keeps every command, including 1 GiB install verification, off Flutter's main thread. */
internal class RuntimeBackgroundDownloadPluginDelegate(
  context: Context,
) : BackgroundDownloadPluginDelegate {
  private val applicationContext = context.applicationContext ?: context
  private val runtime = BackgroundDownloadRuntime.get(applicationContext)
  private val scheduler = BackgroundDownloadScheduler(applicationContext)
  private val apkVerifier = ApkIdentityVerifier(applicationContext, runtime.store)

  override fun execute(
    method: String,
    arguments: Any?,
    completion: BackgroundDownloadPluginCompletion,
  ) {
    try {
      runtime.commandExecutor.execute {
        completion.complete(runCatching {
          runtime.awaitStartupReconciliation()
          invoke(method, arguments)
        })
      }
    } catch (error: Exception) {
      completion.complete(Result.failure(
        BackgroundDownloadPluginException(
          "BACKGROUND_DOWNLOAD_UNAVAILABLE",
          "The background download command executor is unavailable.",
          error,
        ),
      ))
    }
  }

  override fun observe(listener: (Map<String, Any?>) -> Unit): AutoCloseable =
    runtime.observe(listener)

  private fun invoke(method: String, arguments: Any?): Any? = when (method) {
    "startBackgroundDownload" -> start(arguments)
    "getBackgroundDownload" -> runtime.snapshot(read(taskId(arguments)))
    "listBackgroundDownloads" -> runtime.store.list().map(runtime::snapshot)
    "resumeBackgroundDownload" -> resume(taskId(arguments))
    "cancelBackgroundDownload" -> cancel(taskId(arguments))
    "removeBackgroundDownload" -> remove(taskId(arguments))
    "prepareBackgroundDownloadInstall" -> apkVerifier.verifyCompleted(taskId(arguments)).absolutePath
    else -> throw BackgroundDownloadPluginException(
      "BACKGROUND_DOWNLOAD_UNAVAILABLE",
      "Unknown background download method.",
    )
  }

  private fun start(arguments: Any?): Map<String, Any?> {
    val values = argumentMap(arguments)
    val packageUrl = requiredString(values, "packageUrl")
    if (requiredString(values, "packageType") != "apk") invalidArgument("packageType must be apk")
    val expectedSize = requiredLong(values, "packageSizeBytes")
    if (expectedSize <= 0 || expectedSize > BackgroundDownloadContract.MAX_DOWNLOAD_BYTES_CEILING) {
      invalidArgument("packageSizeBytes is outside the native download limit")
    }
    val sha = requiredString(values, "sha256").lowercase()
    try {
      BackgroundDownloadContract.requireValidSha256(sha)
    } catch (error: IllegalArgumentException) {
      invalidArgument("sha256 must be 64 lowercase hexadecimal characters", error)
    }
    if (!BackgroundDownloadUrlPolicy.isAllowed(packageUrl)) {
      invalidArgument("packageUrl must use HTTPS outside loopback")
    }
    val now = System.currentTimeMillis()
    val candidate = BackgroundDownloadRecord(
      revision = 1,
      id = UUID.randomUUID().toString(),
      packageUrl = packageUrl,
      status = BackgroundDownloadStatus.queued,
      downloadedBytes = 0,
      totalBytes = expectedSize,
      expectedSizeBytes = expectedSize,
      expectedSha256 = sha,
      createdAtEpochMs = now,
      updatedAtEpochMs = now,
    )
    val accepted = try {
      runtime.coordinator.start(candidate)
    } catch (error: BackgroundDownloadStartRejectedException) {
      throw BackgroundDownloadPluginException(
        "BACKGROUND_DOWNLOAD_START_REJECTED",
        error.message ?: "The background download was rejected.",
        error,
      )
    }
    runtime.publish(accepted)
    if (accepted.id == candidate.id) {
      try {
        scheduler.schedule(accepted.id, BackgroundDownloadScheduleOperation.newTask)
      } catch (error: BackgroundDownloadScheduleException) {
        runCatching { runtime.store.read(accepted.id) }.getOrNull()?.let(runtime::publish)
        throw BackgroundDownloadPluginException(
          "BACKGROUND_DOWNLOAD_START_REJECTED",
          error.message ?: "Android rejected the background download schedule.",
          error,
        )
      }
    }
    return runtime.snapshot(runCatching { runtime.store.read(accepted.id) }.getOrDefault(accepted))
  }

  private fun resume(id: String): Map<String, Any?> {
    val current = read(id)
    if (current.status !in setOf(
        BackgroundDownloadStatus.waitingForNetwork,
        BackgroundDownloadStatus.waitingForStorage,
        BackgroundDownloadStatus.pausedBySystem,
      )
    ) {
      invalidState("Only a paused or waiting background download can be resumed")
    }
    try {
      scheduler.schedule(id, BackgroundDownloadScheduleOperation.resume)
    } catch (error: BackgroundDownloadScheduleException) {
      throw BackgroundDownloadPluginException(
        "BACKGROUND_DOWNLOAD_INVALID_STATE",
        error.message ?: "The background download could not be resumed.",
        error,
      )
    }
    return runtime.snapshot(read(id))
  }

  private fun cancel(id: String): Map<String, Any?> {
    val current = read(id)
    BackgroundDownloadActiveExecutions.cancel(id)
    scheduler.cancelScheduled(current)
    val canceled = try {
      runtime.coordinator.cancel(id)
    } catch (error: BackgroundDownloadStateException) {
      invalidState(error.message ?: "The background download cannot be canceled", error)
    }
    runtime.publish(canceled)
    return runtime.snapshot(canceled)
  }

  private fun remove(id: String) {
    try {
      runtime.coordinator.remove(id)
    } catch (error: BackgroundDownloadStateException) {
      invalidState(error.message ?: "The background download cannot be removed", error)
    }
    runtime.eventBus.forget(id)
  }

  private fun read(id: String): BackgroundDownloadRecord = try {
    runtime.store.read(id)
  } catch (error: BackgroundDownloadStateException) {
    throw BackgroundDownloadPluginException(
      "BACKGROUND_DOWNLOAD_NOT_FOUND",
      "Background download task was not found.",
      error,
    )
  }

  private fun taskId(arguments: Any?): String {
    val id = requiredString(argumentMap(arguments), "taskId")
    try {
      return BackgroundDownloadContract.requireValidId(id)
    } catch (error: IllegalArgumentException) {
      invalidArgument("taskId is invalid", error)
    }
  }

  private fun argumentMap(arguments: Any?): Map<*, *> =
    arguments as? Map<*, *> ?: invalidArgument("Background download arguments must be a map")

  private fun requiredString(values: Map<*, *>, key: String): String =
    (values[key] as? String)?.takeIf { it.isNotBlank() }
      ?: invalidArgument("$key must be a nonblank string")

  private fun requiredLong(values: Map<*, *>, key: String): Long = when (val value = values[key]) {
    is Byte, is Short, is Int, is Long -> (value as Number).toLong()
    else -> invalidArgument("$key must be an integer")
  }

  private fun invalidArgument(message: String, cause: Throwable? = null): Nothing =
    throw BackgroundDownloadPluginException("INVALID_ARGUMENT", message, cause)

  private fun invalidState(message: String, cause: Throwable? = null): Nothing =
    throw BackgroundDownloadPluginException("BACKGROUND_DOWNLOAD_INVALID_STATE", message, cause)
}

internal class BackgroundDownloadStreamHandler(
  private val delegateProvider: () -> BackgroundDownloadPluginDelegate?,
  private val dispatchToMain: ((() -> Unit) -> Unit),
) : EventChannel.StreamHandler {
  private val lock = Any()
  private var generation = 0L
  private var sink: EventChannel.EventSink? = null
  private var subscription: AutoCloseable? = null

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    detach()
    if (events == null) return
    val currentGeneration = synchronized(lock) {
      generation += 1
      sink = events
      generation
    }
    val delegate = delegateProvider()
    if (delegate == null) {
      dispatch(currentGeneration) {
        it.error("BACKGROUND_DOWNLOAD_UNAVAILABLE", "Background downloads are unavailable.", null)
      }
      return
    }
    val registered = delegate.observe { event ->
      dispatch(currentGeneration) { it.success(event) }
    }
    synchronized(lock) {
      if (generation == currentGeneration && sink === events) {
        subscription = registered
      } else {
        registered.close()
      }
    }
  }

  override fun onCancel(arguments: Any?) {
    detach()
  }

  fun detach() {
    val detached = synchronized(lock) {
      generation += 1
      sink = null
      subscription.also { subscription = null }
    }
    detached?.close()
  }

  private fun dispatch(expectedGeneration: Long, action: (EventChannel.EventSink) -> Unit) {
    dispatchToMain {
      val target = synchronized(lock) {
        sink?.takeIf { generation == expectedGeneration }
      } ?: return@dispatchToMain
      action(target)
    }
  }
}
