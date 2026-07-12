package com.indiegeeker.flutter_app_updater.background

import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

internal class BackgroundDownloadCoordinator(
  private val store: BackgroundDownloadStore,
  private val nowEpochMs: () -> Long = System::currentTimeMillis,
) {
  private val transitionLock = ReentrantLock()

  fun start(candidate: BackgroundDownloadRecord): BackgroundDownloadRecord = transitionLock.withLock {
    requireValidStartRecord(candidate)
    val active = store.list().firstOrNull { !it.status.isTerminal }
    if (active != null) {
      if (active.hasSameArtifactIdentity(candidate)) return@withLock active
      throw BackgroundDownloadStartRejectedException(
        code = "active_download_exists",
        message = "Another background download is already active",
      )
    }
    store.create(candidate)
  }

  fun transition(
    id: String,
    expectedRevision: Long,
    update: (BackgroundDownloadRecord) -> BackgroundDownloadRecord,
  ): BackgroundDownloadRecord = transitionLock.withLock {
    transitionUnlocked(id, expectedRevision, update)
  }

  fun complete(
    id: String,
    expectedRevision: Long,
  ): BackgroundDownloadRecord = transitionLock.withLock {
    val current = store.read(id)
    requireExpectedRevision(current, expectedRevision)
    if (current.status != BackgroundDownloadStatus.verifying) {
      throw BackgroundDownloadStateException("Only a verifying background download can complete")
    }
    if (!store.apkFile(id).isFile) {
      throw BackgroundDownloadStateException("Verified background download artifact is missing")
    }
    store.write(
      current.copy(
        revision = current.revision + 1,
        status = BackgroundDownloadStatus.completed,
        updatedAtEpochMs = nextUpdatedAt(current),
      ),
      current.revision,
    )
  }

  fun cancel(id: String): BackgroundDownloadRecord = transitionLock.withLock {
    val current = store.read(id)
    store.cancelArtifactsAndWriteTombstone(id, current.revision)
  }

  fun remove(id: String) = transitionLock.withLock {
    store.remove(id)
  }

  fun reconcileOnStartup(activeExecutionIds: Set<String>): List<BackgroundDownloadRecord> =
    transitionLock.withLock {
      store.list().map { listed ->
        if (listed.errorCode == "corrupt_state" || listed.errorCode == "unsupported_schema") {
          return@map listed
        }
        if (listed.status == BackgroundDownloadStatus.running && listed.id in activeExecutionIds) {
          return@map listed
        }
        val reconciled = store.reconcileArtifacts(listed.id)
        if (reconciled.status == BackgroundDownloadStatus.running) {
          transitionUnlocked(reconciled.id, reconciled.revision) {
            it.copy(status = BackgroundDownloadStatus.pausedBySystem)
          }
        } else {
          reconciled
        }
      }.sortedWith(
        compareByDescending<BackgroundDownloadRecord> { it.updatedAtEpochMs }
          .thenBy { it.id },
      )
    }

  private fun transitionUnlocked(
    id: String,
    expectedRevision: Long,
    update: (BackgroundDownloadRecord) -> BackgroundDownloadRecord,
  ): BackgroundDownloadRecord {
    val current = store.read(id)
    requireExpectedRevision(current, expectedRevision)
    if (current.status.isTerminal) {
      throw BackgroundDownloadStateException("Terminal background download cannot transition")
    }
    val requested = update(current)
    if (requested.id != current.id) {
      throw BackgroundDownloadStateException("Background download task id cannot change")
    }
    if (!requested.hasSameArtifactIdentity(current)) {
      throw BackgroundDownloadStateException("Background download artifact identity cannot change")
    }
    if (!requested.hasSameImmutableConfiguration(current)) {
      throw BackgroundDownloadStateException("Background download immutable fields cannot change")
    }
    val changesStatus = requested.status != current.status
    if (changesStatus && requested.status !in LEGAL_GENERIC_TRANSITIONS[current.status].orEmpty()) {
      throw BackgroundDownloadStateException(
        "Illegal background download transition: ${current.status} -> ${requested.status}",
      )
    }
    val next = requested.copy(
      revision = current.revision + 1,
      createdAtEpochMs = current.createdAtEpochMs,
      updatedAtEpochMs = nextUpdatedAt(current),
    )
    return store.write(next, current.revision)
  }

  private fun requireValidStartRecord(candidate: BackgroundDownloadRecord) {
    val valid = candidate.status == BackgroundDownloadStatus.queued &&
      candidate.revision == 1L &&
      candidate.downloadedBytes == 0L &&
      (candidate.totalBytes == null || candidate.totalBytes == candidate.expectedSizeBytes) &&
      candidate.errorCode == null &&
      candidate.errorMessage == null &&
      candidate.nativeErrorCode == null
    if (!valid) {
      throw BackgroundDownloadStartRejectedException(
        code = "invalid_start_record",
        message = "Background download must start from a clean queued record",
      )
    }
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

  private fun nextUpdatedAt(current: BackgroundDownloadRecord): Long =
    maxOf(nowEpochMs(), current.updatedAtEpochMs + 1)

  private companion object {
    val LEGAL_GENERIC_TRANSITIONS = mapOf(
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
  }
}
