package com.indiegeeker.flutter_app_updater.background

import java.io.File
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.CyclicBarrier
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class BackgroundDownloadCoordinatorTest {
  private val roots = mutableListOf<File>()

  @AfterTest
  fun cleanUp() {
    roots.forEach(File::deleteRecursively)
  }

  @Test
  fun startAllowsOneActiveTaskAndIsIdempotentForArtifactIdentity() {
    val coordinator = coordinator()
    val first = coordinator.start(record(id = "first"))
    val sameArtifact = coordinator.start(
      record(id = "second", packageUrl = "https://mirror.example.test/new.apk").copy(
        maxDownloadBytes = BackgroundDownloadContract.DEFAULT_MAX_DOWNLOAD_BYTES - 1,
        schedulerJobId = BackgroundDownloadContract.DEFAULT_SCHEDULER_JOB_ID + 1,
        notificationId = BackgroundDownloadContract.DEFAULT_NOTIFICATION_ID + 1,
        createdAtEpochMs = 101,
      ),
    )

    assertEquals(first, sameArtifact)
    val rejected = assertFailsWith<BackgroundDownloadStartRejectedException> {
      coordinator.start(record(id = "other", expectedSha256 = "b".repeat(64)))
    }
    assertEquals("active_download_exists", rejected.code)
  }

  @Test
  fun startRequiresCleanInitialQueuedRecord() {
    val expectedTotal = 1_000_000_000L
    val accepted = coordinator().start(record(totalBytes = expectedTotal))
    assertEquals(BackgroundDownloadStatus.queued, accepted.status)
    assertEquals(expectedTotal, accepted.totalBytes)

    val invalidCandidates = listOf(
      record(revision = 2),
      record(status = BackgroundDownloadStatus.running),
      record(downloadedBytes = 1),
      record().copy(errorCode = "error"),
      record().copy(errorMessage = "message"),
      record().copy(nativeErrorCode = "native"),
    )
    invalidCandidates.forEach { candidate ->
      val rejected = assertFailsWith<BackgroundDownloadStartRejectedException> {
        coordinator().start(candidate)
      }
      assertEquals("invalid_start_record", rejected.code)
    }
  }

  @Test
  fun genericTransitionsMatchLegalStateMachineTable() {
    BackgroundDownloadStatus.entries.forEach { source ->
      BackgroundDownloadStatus.entries.forEach { target ->
        val holder = coordinatorWithStore()
        val current = record(status = source)
        holder.store.create(current)
        val allowed = (!source.isTerminal && target == source) ||
          target in LEGAL_GENERIC_TRANSITIONS[source].orEmpty()

        if (allowed) {
          val transitioned = holder.coordinator.transition(current.id, current.revision) {
            it.copy(status = target)
          }
          assertEquals(target, transitioned.status, "$source -> $target")
        } else {
          assertFailsWith<BackgroundDownloadStateException>("$source -> $target") {
            holder.coordinator.transition(current.id, current.revision) {
              it.copy(status = target)
            }
          }
        }
      }
    }
  }

  @Test
  fun cancelIsDedicatedIdempotentTransitionFromEveryNonterminalState() {
    BackgroundDownloadStatus.entries.forEach { source ->
      val holder = coordinatorWithStore()
      val current = record(status = source)
      holder.store.create(current)
      if (source == BackgroundDownloadStatus.completed || source == BackgroundDownloadStatus.failed) {
        assertFailsWith<BackgroundDownloadStateException>(source.name) {
          holder.coordinator.cancel(current.id)
        }
      } else {
        val canceled = holder.coordinator.cancel(current.id)
        assertEquals(BackgroundDownloadStatus.canceled, canceled.status, source.name)
        assertEquals(canceled, holder.coordinator.cancel(current.id), source.name)
      }
    }
  }

  @Test
  fun completionRequiresVerifyingStateAndExistingApk() {
    val queuedHolder = coordinatorWithStore()
    val queued = queuedHolder.coordinator.start(record())
    assertFailsWith<BackgroundDownloadStateException> {
      queuedHolder.coordinator.complete(queued.id, queued.revision)
    }

    val missingHolder = coordinatorWithStore()
    val missing = record(status = BackgroundDownloadStatus.verifying)
    missingHolder.store.create(missing)
    assertFailsWith<BackgroundDownloadStateException> {
      missingHolder.coordinator.complete(missing.id, missing.revision)
    }

    val readyHolder = coordinatorWithStore()
    val ready = record(status = BackgroundDownloadStatus.verifying)
    readyHolder.store.create(ready)
    readyHolder.store.apkFile(ready.id).writeBytes(byteArrayOf(1))

    val completed = readyHolder.coordinator.complete(ready.id, ready.revision)

    assertEquals(BackgroundDownloadStatus.completed, completed.status)
    assertEquals(ready.revision + 1, completed.revision)
  }

  @Test
  fun concurrentStartsAdmitExactlyOneActiveArtifact() {
    val holder = coordinatorWithStore()
    val executor = Executors.newFixedThreadPool(2)
    val startBarrier = CyclicBarrier(3)
    try {
      val first = executor.submit<Result<BackgroundDownloadRecord>> {
        startBarrier.await()
        runCatching { holder.coordinator.start(record(id = "first")) }
      }
      val second = executor.submit<Result<BackgroundDownloadRecord>> {
        startBarrier.await()
        runCatching {
          holder.coordinator.start(
            record(id = "second", expectedSha256 = "b".repeat(64)),
          )
        }
      }
      startBarrier.await(5, TimeUnit.SECONDS)

      val results = listOf(
        first.get(5, TimeUnit.SECONDS),
        second.get(5, TimeUnit.SECONDS),
      )

      assertEquals(1, results.count { it.isSuccess })
      assertEquals(1, results.count { it.exceptionOrNull() is BackgroundDownloadStartRejectedException })
      assertEquals(1, holder.store.list().count { !it.status.isTerminal })
    } finally {
      executor.shutdownNow()
    }
  }

  @Test
  fun transitionsAreSerializedAndUseExpectedRevisionCas() {
    var now = 1_000L
    val coordinator = coordinator(now = { now })
    val initial = coordinator.start(record())
    now = 1_100

    val running = coordinator.transition(initial.id, expectedRevision = initial.revision) {
      it.copy(status = BackgroundDownloadStatus.running, downloadedBytes = 12)
    }

    assertEquals(2, running.revision)
    assertEquals(1_100, running.updatedAtEpochMs)
    assertEquals(12, running.downloadedBytes)
    assertFailsWith<BackgroundDownloadRevisionException> {
      coordinator.transition(initial.id, expectedRevision = initial.revision) {
        it.copy(downloadedBytes = 20)
      }
    }
  }

  @Test
  fun transitionCannotChangeTaskOrArtifactIdentity() {
    val coordinator = coordinator()
    val initial = coordinator.start(record())

    assertFailsWith<BackgroundDownloadStateException> {
      coordinator.transition(initial.id, initial.revision) { it.copy(id = "other") }
    }
    assertFailsWith<BackgroundDownloadStateException> {
      coordinator.transition(initial.id, initial.revision) {
        it.copy(expectedSizeBytes = it.expectedSizeBytes + 1)
      }
    }
  }

  @Test
  fun coordinatorTransitionsRejectEveryImmutableFieldMutation() {
    immutableRecordMutations.forEach { mutation ->
      val holder = coordinatorWithStore()
      val initial = holder.coordinator.start(record())

      assertFailsWith<BackgroundDownloadStateException>(mutation.name) {
        holder.coordinator.transition(initial.id, initial.revision, mutation.mutate)
      }
      assertEquals(initial, holder.store.read(initial.id), mutation.name)
    }
  }

  @Test
  fun coordinatorTransitionsAllowDocumentedMutableFields() {
    val holder = coordinatorWithStore(now = { 1_000 })
    val initial = record(status = BackgroundDownloadStatus.running)
    holder.store.create(initial)

    val updated = holder.coordinator.transition(initial.id, initial.revision) {
      it.copy(
        status = BackgroundDownloadStatus.waitingForNetwork,
        downloadedBytes = 5,
        totalBytes = it.expectedSizeBytes,
        strongEtag = "\"etag\"",
        lastStopReason = 7,
        errorCode = "retry",
        errorMessage = "retry later",
        nativeErrorCode = "503",
      )
    }

    assertEquals(BackgroundDownloadStatus.waitingForNetwork, updated.status)
    assertEquals(5, updated.downloadedBytes)
    assertEquals("\"etag\"", updated.strongEtag)
    assertEquals(1_000, updated.updatedAtEpochMs)
  }

  @Test
  fun canceledWinsAndStaleProgressVerifyOrCompleteCannotReviveIt() {
    val holder = coordinatorWithStore()
    val initial = record(status = BackgroundDownloadStatus.running)
    holder.store.create(initial)
    holder.store.partialFile(initial.id).writeBytes(byteArrayOf(1))
    holder.store.apkFile(initial.id).writeBytes(byteArrayOf(2))

    val canceled = holder.coordinator.cancel(initial.id)

    assertEquals(BackgroundDownloadStatus.canceled, canceled.status)
    assertFalse(holder.store.partialFile(initial.id).exists())
    assertFalse(holder.store.apkFile(initial.id).exists())
    listOf(
      BackgroundDownloadStatus.running,
      BackgroundDownloadStatus.verifying,
      BackgroundDownloadStatus.completed,
    ).forEach { lateStatus ->
      assertFailsWith<BackgroundDownloadRevisionException> {
        holder.coordinator.transition(initial.id, initial.revision) { it.copy(status = lateStatus) }
      }
    }
    assertEquals(canceled, holder.coordinator.cancel(initial.id))
  }

  @Test
  fun progressHoldingCoordinatorLockThenCancelStillEndsCanceled() {
    val holder = coordinatorWithStore()
    val initial = record(status = BackgroundDownloadStatus.running)
    holder.store.create(initial)
    val progressEntered = CountDownLatch(1)
    val releaseProgress = CountDownLatch(1)
    val cancelRequested = CountDownLatch(1)
    val executor = Executors.newFixedThreadPool(2)
    try {
      val progressFuture = executor.submit<BackgroundDownloadRecord> {
        holder.coordinator.transition(initial.id, initial.revision) {
          progressEntered.countDown()
          assertTrue(releaseProgress.await(5, TimeUnit.SECONDS))
          it.copy(downloadedBytes = 10)
        }
      }
      assertTrue(progressEntered.await(5, TimeUnit.SECONDS))
      val cancelFuture = executor.submit<BackgroundDownloadRecord> {
        cancelRequested.countDown()
        holder.coordinator.cancel(initial.id)
      }
      assertTrue(cancelRequested.await(5, TimeUnit.SECONDS))
      releaseProgress.countDown()

      val progressed = progressFuture.get(5, TimeUnit.SECONDS)
      val canceled = cancelFuture.get(5, TimeUnit.SECONDS)

      assertEquals(2, progressed.revision)
      assertEquals(BackgroundDownloadStatus.canceled, canceled.status)
      assertEquals(3, canceled.revision)
      assertEquals(canceled, holder.store.read(initial.id))
      assertFailsWith<BackgroundDownloadRevisionException> {
        holder.coordinator.transition(initial.id, progressed.revision) {
          it.copy(status = BackgroundDownloadStatus.completed)
        }
      }
    } finally {
      releaseProgress.countDown()
      executor.shutdownNow()
    }
  }

  @Test
  fun cancelHoldingCoordinatorLockMakesLateProgressStale() {
    val cancelWriteEntered = CountDownLatch(1)
    val releaseCancelWrite = CountDownLatch(1)
    val factory = TestCoordinatorRecordFileFactory { contents ->
      if (contents.contains("\"status\":\"canceled\"")) {
        cancelWriteEntered.countDown()
        assertTrue(releaseCancelWrite.await(5, TimeUnit.SECONDS))
      }
    }
    val holder = coordinatorWithStore(factory = factory)
    val initial = record(status = BackgroundDownloadStatus.running)
    holder.store.create(initial)
    val progressRequested = CountDownLatch(1)
    val executor = Executors.newFixedThreadPool(2)
    try {
      val cancelFuture = executor.submit<BackgroundDownloadRecord> {
        holder.coordinator.cancel(initial.id)
      }
      assertTrue(cancelWriteEntered.await(5, TimeUnit.SECONDS))
      val progressFuture = executor.submit<Result<BackgroundDownloadRecord>> {
        progressRequested.countDown()
        runCatching {
          holder.coordinator.transition(initial.id, initial.revision) {
            it.copy(downloadedBytes = 10)
          }
        }
      }
      assertTrue(progressRequested.await(5, TimeUnit.SECONDS))
      releaseCancelWrite.countDown()

      val canceled = cancelFuture.get(5, TimeUnit.SECONDS)
      val lateProgress = progressFuture.get(5, TimeUnit.SECONDS)

      assertEquals(BackgroundDownloadStatus.canceled, canceled.status)
      assertTrue(lateProgress.exceptionOrNull() is BackgroundDownloadRevisionException)
      assertEquals(canceled, holder.store.read(initial.id))
    } finally {
      releaseCancelWrite.countDown()
      executor.shutdownNow()
    }
  }

  @Test
  fun genericTransitionCannotBypassCancelArtifactCleanup() {
    val holder = coordinatorWithStore()
    val initial = record(status = BackgroundDownloadStatus.running)
    holder.store.create(initial)
    holder.store.partialFile(initial.id).writeBytes(byteArrayOf(1))

    assertFailsWith<BackgroundDownloadStateException> {
      holder.coordinator.transition(initial.id, initial.revision) {
        it.copy(status = BackgroundDownloadStatus.canceled)
      }
    }

    assertTrue(holder.store.partialFile(initial.id).exists())
    assertEquals(BackgroundDownloadStatus.running, holder.store.read(initial.id).status)
  }

  @Test
  fun completedOrFailedCancelIsRejectedAndTerminalRemoveSucceeds() {
    val completedHolder = coordinatorWithStore()
    val verifying = record(status = BackgroundDownloadStatus.verifying)
    completedHolder.store.create(verifying)
    completedHolder.store.apkFile(verifying.id).writeBytes(byteArrayOf(1))
    val completed = completedHolder.coordinator.complete(verifying.id, verifying.revision)
    assertFailsWith<BackgroundDownloadStateException> {
      completedHolder.coordinator.cancel(completed.id)
    }
    completedHolder.coordinator.remove(completed.id)
    assertFalse(completedHolder.store.taskDirectory(completed.id).exists())

    val activeHolder = coordinatorWithStore()
    val active = activeHolder.coordinator.start(record())
    assertFailsWith<BackgroundDownloadStateException> {
      activeHolder.coordinator.remove(active.id)
    }
  }

  @Test
  fun startupReconciliationKeepsRunningTaskWithHandle() {
    val holder = coordinatorWithStore()
    holder.store.create(record(status = BackgroundDownloadStatus.running))

    val records = holder.coordinator.reconcileOnStartup(setOf("task_1"))

    assertEquals(BackgroundDownloadStatus.running, records.single().status)
    assertEquals(1, records.single().revision)
  }

  @Test
  fun startupReconciliationPausesRunningTaskWithoutHandle() {
    val holder = coordinatorWithStore(now = { 2_000 })
    holder.store.create(record(status = BackgroundDownloadStatus.running))

    val records = holder.coordinator.reconcileOnStartup(emptySet())

    assertEquals(BackgroundDownloadStatus.pausedBySystem, records.single().status)
    assertEquals(2, records.single().revision)
    assertEquals(2_000, records.single().updatedAtEpochMs)
  }

  private fun coordinator(now: () -> Long = { 1_000 }): BackgroundDownloadCoordinator =
    coordinatorWithStore(now).coordinator

  private fun coordinatorWithStore(
    now: () -> Long = { 1_000 },
    factory: BackgroundRecordFileFactory = TestCoordinatorRecordFileFactory(),
  ): CoordinatorHolder {
    val root = Files.createTempDirectory("background-coordinator-").toFile().also(roots::add)
    val store = BackgroundDownloadStore(root, factory, { _, _ -> true }, now)
    return CoordinatorHolder(store, BackgroundDownloadCoordinator(store, now))
  }
}

private data class CoordinatorHolder(
  val store: BackgroundDownloadStore,
  val coordinator: BackgroundDownloadCoordinator,
)

private class TestCoordinatorRecordFileFactory(
  private val beforeWrite: (String) -> Unit = {},
) : BackgroundRecordFileFactory {
  override fun create(file: File): BackgroundRecordFile = object : BackgroundRecordFile {
    override fun exists(): Boolean = file.isFile
    override fun readText(): String = file.readText()
    override fun writeText(contents: String) {
      beforeWrite(contents)
      file.writeText(contents)
    }
    override fun delete() {
      file.delete()
    }
  }
}

private val LEGAL_GENERIC_TRANSITIONS = mapOf(
  BackgroundDownloadStatus.queued to setOf(
    BackgroundDownloadStatus.running,
    BackgroundDownloadStatus.failed,
  ),
  BackgroundDownloadStatus.running to setOf(
    BackgroundDownloadStatus.waitingForNetwork,
    BackgroundDownloadStatus.waitingForStorage,
    BackgroundDownloadStatus.pausedBySystem,
    BackgroundDownloadStatus.verifying,
    BackgroundDownloadStatus.failed,
  ),
  BackgroundDownloadStatus.waitingForNetwork to setOf(
    BackgroundDownloadStatus.queued,
    BackgroundDownloadStatus.failed,
  ),
  BackgroundDownloadStatus.waitingForStorage to setOf(
    BackgroundDownloadStatus.queued,
    BackgroundDownloadStatus.failed,
  ),
  BackgroundDownloadStatus.pausedBySystem to setOf(
    BackgroundDownloadStatus.queued,
    BackgroundDownloadStatus.failed,
  ),
  BackgroundDownloadStatus.verifying to setOf(BackgroundDownloadStatus.failed),
)
