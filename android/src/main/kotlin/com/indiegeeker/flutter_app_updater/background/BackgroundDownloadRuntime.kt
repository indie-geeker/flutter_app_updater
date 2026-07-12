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
import java.util.concurrent.ScheduledExecutorService

/** Process-local native runtime. It deliberately has no Flutter attachment dependency. */
internal class BackgroundDownloadRuntime private constructor(
  val applicationContext: Context,
  val store: BackgroundDownloadStore,
  val coordinator: BackgroundDownloadCoordinator,
  val engine: BackgroundDownloadEngine,
  val workerExecutor: ExecutorService,
  val scheduledExecutor: ScheduledExecutorService,
) {
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
      val engine = BackgroundDownloadEngine(
        store = store,
        coordinator = coordinator,
        connectionFactory = UrlHttpDownloadConnectionFactory(),
        availableSpaceProvider = BackgroundDownloadAvailableSpaceProvider { directory ->
          StatFs(directory.absolutePath).availableBytes
        },
        artifactMover = AndroidBackgroundDownloadArtifactMover,
      )
      return BackgroundDownloadRuntime(
        applicationContext = context,
        store = store,
        coordinator = coordinator,
        engine = engine,
        workerExecutor = Executors.newSingleThreadExecutor { runnable ->
          Thread(runnable, "flutter-app-updater-download")
        },
        scheduledExecutor = Executors.newSingleThreadScheduledExecutor { runnable ->
          Thread(runnable, "flutter-app-updater-timer")
        },
      )
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
