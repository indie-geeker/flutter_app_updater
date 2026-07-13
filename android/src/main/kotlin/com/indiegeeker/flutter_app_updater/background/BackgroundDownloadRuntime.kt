package com.indiegeeker.flutter_app_updater.background

import android.content.Context
import android.os.StatFs
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/** Process-local native runtime. It deliberately has no Flutter attachment dependency. */
internal class BackgroundDownloadRuntime private constructor(
  val applicationContext: Context,
  val store: BackgroundDownloadStore,
  val coordinator: BackgroundDownloadCoordinator,
  val engine: BackgroundDownloadEngine,
  val workerExecutor: ExecutorService,
  val commandExecutor: ExecutorService,
  val scheduledExecutor: ScheduledExecutorService,
  val eventBus: BackgroundDownloadEventBus,
) {
  private val observationLock = Any()
  private var observationPoll: ScheduledFuture<*>? = null
  @Volatile private var startupReconciliation: BackgroundDownloadStartupReconciliation? = null

  fun awaitStartupReconciliation() {
    try {
      startupReconciliation?.await()
    } catch (error: InterruptedException) {
      Thread.currentThread().interrupt()
      throw BackgroundDownloadStateException("Background download reconciliation was interrupted")
    } catch (error: Exception) {
      throw BackgroundDownloadStateException("Background download reconciliation failed: ${error.message}")
    }
  }

  fun observe(listener: (Map<String, Any?>) -> Unit): AutoCloseable {
    val subscription = eventBus.addListener(listener)
    synchronized(observationLock) {
      if (observationPoll == null) {
        observationPoll = scheduledExecutor.scheduleWithFixedDelay(
          { publishDurableSnapshots() },
          0,
          250,
          TimeUnit.MILLISECONDS,
        )
      }
    }
    publishDurableSnapshots()
    return AutoCloseable {
      subscription.close()
      synchronized(observationLock) {
        if (!eventBus.hasListeners) {
          observationPoll?.cancel(false)
          observationPoll = null
        }
      }
    }
  }

  fun publish(record: BackgroundDownloadRecord) {
    val path = if (record.status == BackgroundDownloadStatus.completed) {
      runCatching { store.apkFile(record.id).takeIf(File::isFile)?.absolutePath }.getOrNull()
    } else {
      null
    }
    eventBus.publish(record, path)
  }

  fun snapshot(record: BackgroundDownloadRecord): Map<String, Any?> {
    val path = if (record.status == BackgroundDownloadStatus.completed) {
      runCatching { store.apkFile(record.id).takeIf(File::isFile)?.absolutePath }.getOrNull()
    } else {
      null
    }
    return record.toMap(path)
  }

  fun reconcileProcessState() {
    coordinator.reconcileOnStartup(emptySet()).forEach(::publish)
  }

  private fun startReconciliation() {
    startupReconciliation = BackgroundDownloadStartupReconciliation(
      workerExecutor,
      ::reconcileProcessState,
    )
  }

  private fun publishDurableSnapshots() {
    runCatching { store.list() }.getOrDefault(emptyList()).forEach(::publish)
  }

  companion object {
    @Volatile private var instance: BackgroundDownloadRuntime? = null

    fun get(context: Context): BackgroundDownloadRuntime {
      val appContext = context.applicationContext ?: context
      return instance ?: synchronized(this) {
        instance ?: create(appContext).also { instance = it }
      }
    }

    private fun create(context: Context): BackgroundDownloadRuntime {
      val store = BackgroundDownloadStore(context, artifactVerifier = ::verifyArtifact)
      val coordinator = BackgroundDownloadCoordinator(store)
      val eventBus = BackgroundDownloadEventBus()
      val workerExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "flutter-app-updater-download")
      }
      val commandExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "flutter-app-updater-command")
      }
      val scheduledExecutor = Executors.newSingleThreadScheduledExecutor { runnable ->
        Thread(runnable, "flutter-app-updater-timer")
      }
      val engine = BackgroundDownloadEngine(
        store = store,
        coordinator = coordinator,
        connectionFactory = UrlHttpDownloadConnectionFactory(),
        availableSpaceProvider = BackgroundDownloadAvailableSpaceProvider { directory ->
          StatFs(directory.absolutePath).availableBytes
        },
        progressListener = { progress ->
          runCatching { store.read(progress.id) }
            .getOrNull()
            ?.let { eventBus.publishProgress(progress, it) }
        },
        checkpointListener = { eventBus.publish(it) },
        artifactMover = AndroidBackgroundDownloadArtifactMover,
      )
      return BackgroundDownloadRuntime(
        applicationContext = context,
        store = store,
        coordinator = coordinator,
        engine = engine,
        workerExecutor = workerExecutor,
        commandExecutor = commandExecutor,
        scheduledExecutor = scheduledExecutor,
        eventBus = eventBus,
      ).also { it.startReconciliation() }
    }

    private fun verifyArtifact(file: File, record: BackgroundDownloadRecord): Boolean {
      if (!file.isFile || file.length() != record.expectedSizeBytes) return false
      val digest = MessageDigest.getInstance("SHA-256")
      file.inputStream().buffered().use { input ->
        val buffer = ByteArray(64 * 1024)
        while (true) {
          val read = input.read(buffer)
          if (read < 0) break
          if (read > 0) digest.update(buffer, 0, read)
        }
      }
      val hash = digest.digest().joinToString("") { "%02x".format(it) }
      return hash == record.expectedSha256
    }
  }
}

internal class BackgroundDownloadStartupReconciliation(
  executor: ExecutorService,
  reconcile: () -> Unit,
) {
  private val future: Future<*> = executor.submit(reconcile)

  fun await() {
    future.get()
  }
}

private object AndroidBackgroundDownloadArtifactMover : BackgroundDownloadArtifactMover {
  override fun moveAtomically(source: File, target: File) {
    try {
      Os.rename(source.absolutePath, target.absolutePath)
    } catch (error: ErrnoException) {
      throw IOException("Atomic artifact rename failed", error)
    }
  }

  override fun syncDirectory(directory: File) {
    try {
      val descriptor = Os.open(
        directory.absolutePath,
        OsConstants.O_RDONLY,
        0,
      )
      try {
        Os.fsync(descriptor)
      } finally {
        Os.close(descriptor)
      }
    } catch (error: ErrnoException) {
      throw IOException("Artifact directory sync failed", error)
    }
  }
}
