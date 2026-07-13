package com.indiegeeker.flutter_app_updater

import com.indiegeeker.flutter_app_updater.background.BackgroundDownloadPluginDelegate
import com.indiegeeker.flutter_app_updater.background.BackgroundDownloadPluginCompletion
import com.indiegeeker.flutter_app_updater.background.BackgroundDownloadStreamHandler
import com.indiegeeker.flutter_app_updater.background.BackgroundDownloadStartupReconciliation
import com.indiegeeker.flutter_app_updater.background.BackgroundDownloadUrlPolicy
import com.indiegeeker.flutter_app_updater.background.BackgroundDownloadEventBus
import com.indiegeeker.flutter_app_updater.background.BackgroundDownloadProgress
import com.indiegeeker.flutter_app_updater.background.BackgroundDownloadRecord
import com.indiegeeker.flutter_app_updater.background.BackgroundDownloadStatus
import com.indiegeeker.flutter_app_updater.background.ApkIdentityVerificationException
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import org.mockito.Mockito
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

internal class BackgroundDownloadPluginTest {
  @Test
  fun exactBackgroundMethodsAreDelegatedWithExactArguments() {
    val delegate = FakeDelegate()
    val plugin = FlutterAppUpdaterPlugin(delegate)
    val result = RecordingResult()
    val methods = listOf(
      "startBackgroundDownload" to mapOf(
        "packageUrl" to "https://example.com/update.apk",
        "packageType" to "apk",
        "packageSizeBytes" to 1024L,
        "sha256" to "a".repeat(64),
      ),
      "getBackgroundDownload" to mapOf("taskId" to "task-1"),
      "listBackgroundDownloads" to null,
      "resumeBackgroundDownload" to mapOf("taskId" to "task-1"),
      "cancelBackgroundDownload" to mapOf("taskId" to "task-1"),
      "removeBackgroundDownload" to mapOf("taskId" to "task-1"),
      "prepareBackgroundDownloadInstall" to mapOf("taskId" to "task-1"),
    )

    methods.forEach { (method, arguments) ->
      plugin.onMethodCall(MethodCall(method, arguments), result)
    }

    assertEquals(methods.map { it.first }, delegate.calls.map { it.first })
    assertEquals(methods.map { it.second }, delegate.calls.map { it.second })
    assertEquals(7, result.successes.size)
  }

  @Test
  fun streamSinkIsDispatchedThroughMainThreadBoundaryAndDetachOnlyUnregisters() {
    val delegate = FakeDelegate()
    val mainQueue = ArrayDeque<() -> Unit>()
    val handler = BackgroundDownloadStreamHandler(
      delegateProvider = { delegate },
      dispatchToMain = mainQueue::add,
    )
    val sink = Mockito.mock(EventChannel.EventSink::class.java)

    handler.onListen(null, sink)
    delegate.emit(mapOf("id" to "task-1", "revision" to 1L))

    Mockito.verifyNoInteractions(sink)
    mainQueue.removeFirst().invoke()
    Mockito.verify(sink).success(mapOf("id" to "task-1", "revision" to 1L))
    handler.detach()

    assertEquals(1, delegate.unregisterCount)
    assertFalse(delegate.canceled)
  }

  @Test
  fun queuedSinkDeliveryIsSuppressedAfterDetach() {
    val delegate = FakeDelegate()
    val mainQueue = ArrayDeque<() -> Unit>()
    val handler = BackgroundDownloadStreamHandler(
      delegateProvider = { delegate },
      dispatchToMain = mainQueue::add,
    )
    val sink = Mockito.mock(EventChannel.EventSink::class.java)
    handler.onListen(null, sink)
    delegate.emit(mapOf("id" to "task-1", "revision" to 1L))

    handler.detach()
    mainQueue.removeFirst().invoke()

    Mockito.verifyNoInteractions(sink)
    assertTrue(delegate.listeners.isEmpty())
  }

  @Test
  fun prepareInstallCompletionIsMarshaledAfterBackgroundCompletion() {
    val delegate = FakeDelegate(autoComplete = false)
    val mainQueue = ArrayDeque<() -> Unit>()
    val plugin = FlutterAppUpdaterPlugin(delegate) { mainQueue.add(it) }
    val result = RecordingResult()

    plugin.onMethodCall(
      MethodCall("prepareBackgroundDownloadInstall", mapOf("taskId" to "task-1")),
      result,
    )
    assertTrue(result.successes.isEmpty())
    delegate.completeNext(Result.success("/internal/artifact.apk"))
    assertTrue(result.successes.isEmpty())

    mainQueue.removeFirst().invoke()

    assertEquals(listOf<Any?>("/internal/artifact.apk"), result.successes)
  }

  @Test
  fun startupReconciliationIsSubmittedWithoutBlockingItsCallerAndCanBeAwaitedOffMain() {
    val worker = Executors.newSingleThreadExecutor()
    val waiter = Executors.newSingleThreadExecutor()
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    try {
      val reconciliation = BackgroundDownloadStartupReconciliation(worker) {
        entered.countDown()
        release.await(5, TimeUnit.SECONDS)
      }
      assertTrue(entered.await(5, TimeUnit.SECONDS))
      val awaited = waiter.submit { reconciliation.await() }
      assertFalse(awaited.isDone)

      release.countDown()

      awaited.get(5, TimeUnit.SECONDS)
    } finally {
      release.countDown()
      worker.shutdownNow()
      waiter.shutdownNow()
    }
  }

  @Test
  fun eventBusSupportsTwoWatchersStaleFilteringAndTerminalLateProgressBarrier() {
    val bus = BackgroundDownloadEventBus()
    val first = mutableListOf<Map<String, Any?>>()
    val second = mutableListOf<Map<String, Any?>>()
    val firstSubscription = bus.addListener { first += it }
    bus.addListener { second += it }

    bus.publish(eventRecord(2, BackgroundDownloadStatus.running, 20))
    bus.publish(eventRecord(1, BackgroundDownloadStatus.running, 10))
    bus.publishProgress(
      BackgroundDownloadProgress("task-1", 2, 30, 100),
      eventRecord(2, BackgroundDownloadStatus.running, 20),
    )
    firstSubscription.close()
    bus.publish(eventRecord(3, BackgroundDownloadStatus.canceled, 0))
    bus.publishProgress(
      BackgroundDownloadProgress("task-1", 3, 90, 100),
      eventRecord(3, BackgroundDownloadStatus.running, 20),
    )

    assertEquals(listOf(2L, 2L), first.map { it["revision"] })
    assertEquals(listOf(2L, 2L, 3L), second.map { it["revision"] })
    assertEquals("canceled", second.last()["status"])
    assertEquals(1, bus.listenerCount)
  }

  @Test
  fun eventBusReplaysTerminalOnReattachAndNeverCallsListenersUnderItsLock() {
    val bus = BackgroundDownloadEventBus()
    val calls = AtomicInteger()
    lateinit var firstSubscription: AutoCloseable
    firstSubscription = bus.addListener {
      calls.incrementAndGet()
      firstSubscription.close()
      bus.publish(eventRecord(5, BackgroundDownloadStatus.completed, 100))
    }
    bus.publish(
      eventRecord(4, BackgroundDownloadStatus.completed, 100),
      "/internal/artifact.apk",
    )

    val reattached = mutableListOf<Map<String, Any?>>()
    bus.addListener { reattached += it }

    assertEquals(1, calls.get())
    assertEquals(listOf(4L), reattached.map { it["revision"] })
    assertEquals("completed", reattached.single()["status"])
    assertEquals("/internal/artifact.apk", reattached.single()["filePath"])
  }

  @Test
  fun forgottenTaskRejectsLateRecordAndProgressAndIsNotReplayed() {
    val bus = BackgroundDownloadEventBus()
    val received = mutableListOf<Map<String, Any?>>()
    val subscription = bus.addListener { received += it }
    val stale = eventRecord(4, BackgroundDownloadStatus.running, 40)
    bus.publish(stale)
    subscription.close()

    bus.forget(stale.id)
    bus.publish(stale.copy(revision = 5, downloadedBytes = 50))
    bus.publishProgress(
      BackgroundDownloadProgress(stale.id, 4, 60, 100),
      stale,
    )

    val reattached = mutableListOf<Map<String, Any?>>()
    bus.addListener { reattached += it }
    assertTrue(reattached.isEmpty())
  }

  @Test
  fun blockingReplayAndConcurrentPublishStayOrderedPerListener() {
    val bus = BackgroundDownloadEventBus()
    bus.publish(eventRecord(1, BackgroundDownloadStatus.running, 10))
    val enteredReplay = CountDownLatch(1)
    val releaseReplay = CountDownLatch(1)
    val received = mutableListOf<Long>()
    val pool = Executors.newSingleThreadExecutor()
    try {
      val registration = pool.submit {
        bus.addListener { event ->
          synchronized(received) { received += event["revision"] as Long }
          if (event["revision"] == 1L) {
            enteredReplay.countDown()
            releaseReplay.await(5, TimeUnit.SECONDS)
          }
        }
      }
      assertTrue(enteredReplay.await(5, TimeUnit.SECONDS))
      bus.publish(eventRecord(2, BackgroundDownloadStatus.running, 20))
      bus.publish(eventRecord(2, BackgroundDownloadStatus.running, 20))
      releaseReplay.countDown()
      registration.get(5, TimeUnit.SECONDS)

      assertEquals(listOf(1L, 2L), synchronized(received) { received.toList() })
    } finally {
      releaseReplay.countDown()
      pool.shutdownNow()
    }
  }

  @Test
  fun nativeUrlPolicyAcceptsOnlyRealLoopbackHttpHosts() {
    for (url in listOf(
      "https://example.com/update.apk",
      "http://localhost:8080/update.apk",
      "http://127.0.0.1:8080/update.apk",
      "http://127.255.1.2/update.apk",
      "http://[::1]:8080/update.apk",
    )) {
      assertTrue(BackgroundDownloadUrlPolicy.isAllowed(url), url)
    }
    for (url in listOf(
      "http://127.evil.com/update.apk",
      "http://127.0.0.1.evil.com/update.apk",
      "http://example.com/update.apk",
      "ftp://localhost/update.apk",
    )) {
      assertFalse(BackgroundDownloadUrlPolicy.isAllowed(url), url)
    }
  }

  @Test
  fun startupReconciliationFailureIsPropagatedToEveryWaiter() {
    val worker = Executors.newSingleThreadExecutor()
    try {
      val reconciliation = BackgroundDownloadStartupReconciliation(worker) {
        error("reconcile failed")
      }

      assertFailsWith<Exception> { reconciliation.await() }
      assertFailsWith<Exception> { reconciliation.await() }
    } finally {
      worker.shutdownNow()
    }
  }

  @Test
  fun installDoesNotLaunchWhenManagedPathRevalidationFails() {
    val delegate = FakeDelegate(
      installVerificationFailure = ApkIdentityVerificationException(
        "PACKAGE_HASH_MISMATCH",
        "The completed APK hash changed.",
      ),
    )
    val plugin = FlutterAppUpdaterPlugin(delegate)
    val result = RecordingResult()

    plugin.onMethodCall(MethodCall("installApp", "/internal/artifact.apk"), result)

    assertEquals(listOf("PACKAGE_HASH_MISMATCH"), result.errors)
    assertTrue(result.successes.isEmpty())
  }
}

private fun eventRecord(
  revision: Long,
  status: BackgroundDownloadStatus,
  downloadedBytes: Long,
) = BackgroundDownloadRecord(
  revision = revision,
  id = "task-1",
  packageUrl = "https://example.com/update.apk",
  status = status,
  downloadedBytes = downloadedBytes,
  totalBytes = 100,
  expectedSizeBytes = 100,
  expectedSha256 = "a".repeat(64),
  createdAtEpochMs = 1,
  updatedAtEpochMs = revision,
)

private class FakeDelegate(
  private val autoComplete: Boolean = true,
  private val installVerificationFailure: Throwable? = null,
) : BackgroundDownloadPluginDelegate {
  val calls = mutableListOf<Pair<String, Any?>>()
  val listeners = mutableListOf<(Map<String, Any?>) -> Unit>()
  var unregisterCount = 0
  var canceled = false
  private val pending = ArrayDeque<BackgroundDownloadPluginCompletion>()

  override fun execute(
    method: String,
    arguments: Any?,
    completion: BackgroundDownloadPluginCompletion,
  ) {
    calls += method to arguments
    if (!autoComplete) {
      pending.add(completion)
      return
    }
    val value = when (method) {
      "listBackgroundDownloads" -> emptyList<Map<String, Any?>>()
      "removeBackgroundDownload" -> null
      "prepareBackgroundDownloadInstall" -> "/internal/artifact.apk"
      else -> mapOf("id" to "task-1")
    }
    completion.complete(Result.success(value))
  }

  override fun observe(listener: (Map<String, Any?>) -> Unit): AutoCloseable {
    listeners += listener
    return AutoCloseable {
      listeners -= listener
      unregisterCount += 1
    }
  }

  override fun verifyInstallPath(path: String, completion: BackgroundDownloadPluginCompletion) {
    completion.complete(
      installVerificationFailure?.let { Result.failure(it) } ?: Result.success(path),
    )
  }

  fun emit(event: Map<String, Any?>) {
    listeners.toList().forEach { it(event) }
  }

  fun completeNext(result: Result<Any?>) {
    pending.removeFirst().complete(result)
  }
}

private class RecordingResult : MethodChannel.Result {
  val successes = mutableListOf<Any?>()
  val errors = mutableListOf<String>()
  var notImplemented = false

  override fun success(result: Any?) {
    successes += result
  }

  override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
    errors += errorCode
  }

  override fun notImplemented() {
    notImplemented = true
  }
}
