package com.indiegeeker.flutter_app_updater.background

import java.io.File
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class BackgroundDownloadSchedulerTest {
  @Test
  fun sdkPolicyUsesLegacyServiceThenForegroundServiceThenUidt() {
    assertEquals(BackgroundDownloadSchedulingMode.service, BackgroundDownloadSchedulingPolicy.modeFor(21))
    assertEquals(BackgroundDownloadSchedulingMode.service, BackgroundDownloadSchedulingPolicy.modeFor(25))
    assertEquals(BackgroundDownloadSchedulingMode.foregroundService, BackgroundDownloadSchedulingPolicy.modeFor(26))
    assertEquals(BackgroundDownloadSchedulingMode.foregroundService, BackgroundDownloadSchedulingPolicy.modeFor(33))
    assertEquals(BackgroundDownloadSchedulingMode.userInitiatedJob, BackgroundDownloadSchedulingPolicy.modeFor(34))
    assertEquals(BackgroundDownloadSchedulingMode.userInitiatedJob, BackgroundDownloadSchedulingPolicy.modeFor(35))
  }

  @Test
  fun api34BuildsAStableNonPersistedUserInitiatedInternetJob() {
    val platform = FakeSchedulingPlatform(34)
    val scheduler = scheduler(platform, record(downloadedBytes = 25))

    scheduler.schedule(TASK_ID, BackgroundDownloadScheduleOperation.newTask)

    val job = platform.uidtJobs.single()
    assertEquals(BackgroundDownloadContract.DEFAULT_SCHEDULER_JOB_ID, job.jobId)
    assertEquals(TASK_ID, job.taskId)
    assertEquals(75, job.estimatedDownloadBytes)
    assertTrue(job.userInitiated)
    assertFalse(job.persisted)
    assertTrue(job.requiresInternet)
    assertEquals(setOf(BackgroundDownloadScheduler.EXTRA_TASK_ID), job.extraKeys)
    assertEquals(0, platform.serviceStarts.size)
  }

  @Test
  fun api34ScheduleRejectionNeverFallsBackToForegroundService() {
    val platform = FakeSchedulingPlatform(34, uidtAccepted = false)
    val failures = mutableListOf<String>()
    val scheduler = scheduler(platform, record(), failures)

    val error = assertFailsWith<BackgroundDownloadScheduleException> {
      scheduler.schedule(TASK_ID, BackgroundDownloadScheduleOperation.newTask)
    }

    assertEquals("background_schedule_rejected", error.code)
    assertEquals(listOf(TASK_ID), failures)
    assertTrue(platform.serviceStarts.isEmpty())
  }

  @Test
  fun api34SecurityExceptionNeverFallsBackToForegroundService() {
    val platform = FakeSchedulingPlatform(34, uidtFailure = SecurityException("denied"))
    val failures = mutableListOf<String>()
    val scheduler = scheduler(platform, record(), failures)

    val error = assertFailsWith<BackgroundDownloadScheduleException> {
      scheduler.schedule(TASK_ID, BackgroundDownloadScheduleOperation.newTask)
    }

    assertEquals("background_schedule_not_permitted", error.code)
    assertEquals(listOf(TASK_ID), failures)
    assertTrue(platform.serviceStarts.isEmpty())
  }

  @Test
  fun resumeRejectionPreservesDurableState() {
    val platform = FakeSchedulingPlatform(34, uidtAccepted = false)
    val failures = mutableListOf<String>()
    val scheduler = scheduler(platform, record(status = BackgroundDownloadStatus.pausedBySystem), failures)

    assertFailsWith<BackgroundDownloadScheduleException> {
      scheduler.schedule(TASK_ID, BackgroundDownloadScheduleOperation.resume)
    }

    assertTrue(failures.isEmpty())
  }

  @Test
  fun api21Through25UsesStartServiceAnd26Through33UsesStartForegroundService() {
    val api25 = FakeSchedulingPlatform(25)
    scheduler(api25, record()).schedule(TASK_ID, BackgroundDownloadScheduleOperation.newTask)
    assertEquals(listOf(ServiceStart(TASK_ID, false)), api25.serviceStarts)

    val api26 = FakeSchedulingPlatform(26)
    scheduler(api26, record()).schedule(TASK_ID, BackgroundDownloadScheduleOperation.newTask)
    assertEquals(listOf(ServiceStart(TASK_ID, true)), api26.serviceStarts)

    val api33 = FakeSchedulingPlatform(33)
    scheduler(api33, record()).schedule(TASK_ID, BackgroundDownloadScheduleOperation.newTask)
    assertEquals(listOf(ServiceStart(TASK_ID, true)), api33.serviceStarts)
  }

  @Test
  fun missingHostSetupAndFgsStartRejectionAreTypedAndDoNotMutateResume() {
    val missing = FakeSchedulingPlatform(33, setupFailure = IllegalStateException("missing service"))
    val missingError = assertFailsWith<BackgroundDownloadScheduleException> {
      scheduler(missing, record()).schedule(TASK_ID, BackgroundDownloadScheduleOperation.newTask)
    }
    assertEquals("background_host_setup_missing", missingError.code)

    val rejected = FakeSchedulingPlatform(
      33,
      serviceFailure = BackgroundDownloadPlatformStartNotAllowedException("not allowed"),
    )
    val failures = mutableListOf<String>()
    val error = assertFailsWith<BackgroundDownloadScheduleException> {
      scheduler(rejected, record(status = BackgroundDownloadStatus.waitingForNetwork), failures)
        .schedule(TASK_ID, BackgroundDownloadScheduleOperation.resume)
    }
    assertEquals("background_start_not_allowed", error.code)
    assertTrue(failures.isEmpty())
  }

  @Test
  fun cancelSignalsExecutionBeforeCancelingScheduleAndPersistingTombstone() {
    val calls = mutableListOf<String>()
    val handler = BackgroundDownloadActionHandler(
      stopActiveExecution = { calls += "stop" },
      cancelScheduledExecution = { calls += "unschedule" },
      persistCancellation = { calls += "tombstone" },
      scheduleResume = { calls += "resume" },
    )

    handler.cancel(TASK_ID)

    assertEquals(listOf("stop", "unschedule", "tombstone"), calls)
  }

  @Test
  fun retryDelegatesToExplicitResumeOnly() {
    val calls = mutableListOf<String>()
    val handler = BackgroundDownloadActionHandler(
      stopActiveExecution = { calls += "stop" },
      cancelScheduledExecution = { calls += "unschedule" },
      persistCancellation = { calls += "tombstone" },
      scheduleResume = { calls += "resume:$it" },
    )

    handler.retry(TASK_ID)

    assertEquals(listOf("resume:$TASK_ID"), calls)
  }

  @Test
  fun notificationContractUsesNamespacedIdsActionsAndOneHertzGate() {
    assertEquals("flutter_app_updater_downloads", BackgroundDownloadNotifications.CHANNEL_ID)
    assertEquals(BackgroundDownloadContract.DEFAULT_NOTIFICATION_ID, BackgroundDownloadNotifications.notificationId(record()))
    assertEquals("com.indiegeeker.flutter_app_updater.background.CANCEL", BackgroundDownloadActionReceiver.ACTION_CANCEL)
    assertEquals("com.indiegeeker.flutter_app_updater.background.RETRY", BackgroundDownloadActionReceiver.ACTION_RETRY)

    var now = 1_000L
    val gate = BackgroundDownloadNotificationRateGate { now }
    assertTrue(gate.shouldPublish(TASK_ID, force = false))
    now = 1_999L
    assertFalse(gate.shouldPublish(TASK_ID, force = false))
    now = 2_000L
    assertTrue(gate.shouldPublish(TASK_ID, force = false))
    now = 2_001L
    assertTrue(gate.shouldPublish(TASK_ID, force = true))
  }

  @Test
  fun uidtCompletionIsExactlyOnceAndNeverRunsAfterStop() {
    val calls = mutableListOf<String>()
    val lifecycle = UserInitiatedJobCompletionGate()

    assertTrue(lifecycle.finish { calls += "finished" })
    assertFalse(lifecycle.finish { calls += "finished-again" })
    assertFalse(lifecycle.stop { calls += "stopped-after-finish" })
    assertEquals(listOf("finished"), calls)

    val stopped = UserInitiatedJobCompletionGate()
    assertTrue(stopped.stop { calls += "stopped" })
    assertFalse(stopped.finish { calls += "finished-after-stop" })
    assertEquals(listOf("finished", "stopped"), calls)
  }

  @Test
  fun uidtRunIfActiveSerializesWithStopAndRejectsLateNotificationAction() {
    val gate = UserInitiatedJobCompletionGate()
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    val pool = Executors.newFixedThreadPool(2)
    try {
      val notification = pool.submit(java.util.concurrent.Callable<Boolean> {
        gate.runIfActive {
          entered.countDown()
          release.await(5, TimeUnit.SECONDS)
        }
      })
      assertTrue(entered.await(5, TimeUnit.SECONDS))
      val stop = pool.submit(java.util.concurrent.Callable<Boolean> { gate.stop { } })
      Thread.sleep(50)
      assertFalse(stop.isDone)
      release.countDown()
      assertTrue(notification.get(5, TimeUnit.SECONDS))
      assertTrue(stop.get(5, TimeUnit.SECONDS))
      var lateAction = false
      assertFalse(gate.runIfActive { lateAction = true })
      assertFalse(lateAction)
    } finally {
      release.countDown()
      pool.shutdownNow()
    }
  }

  @Test
  fun uidtStopBeforeWorkerBeginPreventsExecutionFromStarting() {
    val lifecycle = UserInitiatedJobCompletionGate()
    assertTrue(lifecycle.stop { })
    assertFalse(lifecycle.begin())

    val active = UserInitiatedJobCompletionGate()
    assertTrue(active.begin())
    assertFalse(active.begin())
  }

  @Test
  fun uidtStoppedCompletionGateRejectsEveryNetworkRestartIteration() {
    val lifecycle = UserInitiatedJobCompletionGate()
    assertTrue(lifecycle.begin())
    assertTrue(lifecycle.stop { })

    // The worker checks this immediately after publishing each replacement
    // control, closing the null-control window between network iterations.
    assertTrue(lifecycle.isStopped())
    assertFalse(lifecycle.mayExecute())
  }

  @Test
  fun uidtNetworkChangeStopsOldControlBeforeBindingReplacement() {
    val calls = mutableListOf<String>()
    val binding = UserInitiatedJobNetworkBinding(
      initialNetwork = "network-a",
      stopOldExecution = { calls += "stop:$it" },
    )

    binding.replace("network-b")

    assertEquals(listOf("stop:network-a"), calls)
    assertEquals("network-b", binding.current())
  }

  @Test
  fun uidtNetworkGateLinearizesRebindAgainstFinalClose() {
    val gate = UserInitiatedJobNetworkGate("network-a")
    val first = checkNotNull(gate.lease())
    val calls = mutableListOf<String>()
    assertTrue(gate.rebind("network-b") { calls += "stop-old" })
    assertEquals(UserInitiatedJobNetworkGate.Decision.restart, gate.finish(first))
    assertEquals("network-b", gate.lease()?.network)
    assertEquals(listOf("stop-old"), calls)

    val finalGate = UserInitiatedJobNetworkGate("network-a")
    val finalLease = checkNotNull(finalGate.lease())
    assertEquals(UserInitiatedJobNetworkGate.Decision.close, finalGate.finish(finalLease))
    assertFalse(finalGate.rebind("network-b") { calls += "late-stop" })
    assertEquals(null, finalGate.lease())
    assertEquals(listOf("stop-old"), calls)
  }

  @Test
  fun foregroundBootstrapPromotesBeforeAnyRuntimeWorkAndIsNotSticky() {
    val calls = mutableListOf<String>()
    val result = BackgroundDownloadForegroundBootstrap.start(
      promote = { calls += "foreground" },
      beginWork = { calls += "work" },
    )

    assertEquals(listOf("foreground", "work"), calls)
    assertEquals(android.app.Service.START_NOT_STICKY, result)
  }

  @Test
  fun foregroundAdmissionReusesDuplicateStartAndRejectsFailedRegistration() {
    assertEquals(
      BackgroundDownloadForegroundAdmission.reuseExecution,
      BackgroundDownloadForegroundAdmissionPolicy.decide(TASK_ID, TASK_ID, registrationSucceeded = false),
    )
    assertEquals(
      BackgroundDownloadForegroundAdmission.keepExistingExecution,
      BackgroundDownloadForegroundAdmissionPolicy.decide("other_task", TASK_ID, registrationSucceeded = false),
    )
    assertEquals(
      BackgroundDownloadForegroundAdmission.reject,
      BackgroundDownloadForegroundAdmissionPolicy.decide(null, TASK_ID, registrationSucceeded = false),
    )
    assertEquals(
      BackgroundDownloadForegroundAdmission.newExecution,
      BackgroundDownloadForegroundAdmissionPolicy.decide(null, TASK_ID, registrationSucceeded = true),
    )
  }

  @Test
  fun notificationPermissionDenialIsContained() {
    assertFalse(BackgroundDownloadNotificationPermissionBoundary.attempt { throw SecurityException("denied") })
    assertTrue(BackgroundDownloadNotificationPermissionBoundary.attempt { })
  }

  @Test
  fun terminalAndDuplicateOutcomesNeverLeaveARunningNotification() {
    assertEquals(
      BackgroundDownloadNotificationState.failed,
      BackgroundDownloadNotificationStatePolicy.forOutcome(BackgroundDownloadExecutionOutcome.failed),
    )
    assertEquals(
      BackgroundDownloadNotificationState.cancel,
      BackgroundDownloadNotificationStatePolicy.forOutcome(BackgroundDownloadExecutionOutcome.canceled),
    )
    assertEquals(
      BackgroundDownloadNotificationState.cancel,
      BackgroundDownloadNotificationStatePolicy.forOutcome(BackgroundDownloadExecutionOutcome.alreadyRunning),
    )
  }

  @Test
  fun uidtRecoveryNotificationRemovesStartingWhenNoDurableRecordExists() {
    assertEquals(
      BackgroundDownloadNotificationState.cancel,
      BackgroundDownloadUidtRecoveryNotificationPolicy.forRecord(null),
    )
    assertEquals(
      BackgroundDownloadNotificationState.waiting,
      BackgroundDownloadUidtRecoveryNotificationPolicy.forRecord(
        record(status = BackgroundDownloadStatus.waitingForStorage),
      ),
    )
    assertEquals(
      BackgroundDownloadNotificationState.completed,
      BackgroundDownloadUidtRecoveryNotificationPolicy.forRecord(
        record(status = BackgroundDownloadStatus.completed),
      ),
    )
  }

  @Test
  fun canonicalHostSetupRequirementsTrackPlatformPermissions() {
    assertEquals(
      setOf("android.permission.ACCESS_NETWORK_STATE"),
      BackgroundDownloadHostSetupRequirements.forSdk(21).permissions,
    )
    assertTrue(
      BackgroundDownloadHostSetupRequirements.forSdk(33).permissions.containsAll(
        setOf(
          "android.permission.ACCESS_NETWORK_STATE",
          "android.permission.FOREGROUND_SERVICE",
          "android.permission.POST_NOTIFICATIONS",
        ),
      ),
    )
    val api34 = BackgroundDownloadHostSetupRequirements.forSdk(34)
    assertTrue(api34.permissions.contains("android.permission.RUN_USER_INITIATED_JOBS"))
    assertTrue(api34.permissions.contains("android.permission.FOREGROUND_SERVICE_DATA_SYNC"))
    assertTrue(api34.requireDataSyncServiceType)

    val valid = BackgroundDownloadHostSetupSnapshot(
      declaredPermissions = api34.permissions,
      jobService = BackgroundDownloadHostComponent(
        exported = false,
        enabled = true,
        permission = "android.permission.BIND_JOB_SERVICE",
      ),
      foregroundService = BackgroundDownloadHostComponent(
        exported = false,
        enabled = true,
        hasDataSyncType = true,
      ),
      receiver = BackgroundDownloadHostComponent(exported = false, enabled = true),
    )
    BackgroundDownloadHostSetupValidator.requireValid(api34, valid)
    assertFailsWith<IllegalStateException> {
      BackgroundDownloadHostSetupValidator.requireValid(
        api34,
        valid.copy(jobService = valid.jobService.copy(exported = true)),
      )
    }
    assertFailsWith<IllegalStateException> {
      BackgroundDownloadHostSetupValidator.requireValid(
        api34,
        valid.copy(declaredPermissions = valid.declaredPermissions - "android.permission.RUN_USER_INITIATED_JOBS"),
      )
    }
  }

  @Test
  fun productionJobSpecWiringCannotDriftFromTestedUidtContract() {
    val builder = RecordingJobBuilder()
    val spec = UserInitiatedJobSpec(7, TASK_ID, 123)

    val built = BackgroundDownloadJobSpecWiring.build(spec, builder)

    assertEquals("built", built)
    assertEquals(
      listOf(
        "extra:taskId=$TASK_ID",
        "persisted:false",
        "internet",
        "estimate:123",
        "userInitiated:true",
        "build",
      ),
      builder.calls,
    )
  }

  @Test
  fun preExecutionStopPersistsPausedStateAndRawReasonWithoutEngineWork() {
    val root = Files.createTempDirectory("scheduler-stop").toFile()
    try {
      val store = BackgroundDownloadStore(root, SchedulerTestRecordFileFactory())
      store.create(record())
      val coordinator = BackgroundDownloadCoordinator(store, nowEpochMs = { 50 })
      val result = BackgroundDownloadPreExecutionStopPersister(coordinator)
        .persist(TASK_ID, rawStopReason = 42)

      assertTrue(result.persisted)
      assertEquals(BackgroundDownloadStatus.pausedBySystem, result.record?.status)
      assertEquals(42, result.record?.lastStopReason)
      assertEquals(2, result.record?.revision)
      assertFalse(store.partialFile(TASK_ID).exists())
      listOf(BackgroundDownloadStatus.waitingForNetwork, BackgroundDownloadStatus.verifying)
        .forEachIndexed { index, status ->
          val id = "pause_$index"
          store.create(record(id = id, status = status))
          val paused = BackgroundDownloadPreExecutionStopPersister(coordinator).persist(id, index)
          assertTrue(paused.persisted)
          assertEquals(BackgroundDownloadStatus.pausedBySystem, paused.record?.status)
        }
      val terminalId = "terminal"
      store.create(record(id = terminalId, status = BackgroundDownloadStatus.failed))
      val terminal = BackgroundDownloadPreExecutionStopPersister(coordinator).persist(terminalId, 9)
      assertEquals(BackgroundDownloadStatus.failed, terminal.record?.status)
      val raceId = "pause_race"
      store.create(record(id = raceId))
      val pool = Executors.newFixedThreadPool(2)
      try {
        val pause = pool.submit { coordinator.pauseBySystem(raceId, 11) }
        val cancel = pool.submit { coordinator.cancel(raceId) }
        pause.get(5, TimeUnit.SECONDS)
        cancel.get(5, TimeUnit.SECONDS)
        assertEquals(BackgroundDownloadStatus.canceled, store.read(raceId).status)
      } finally {
        pool.shutdownNow()
      }
      val missing = BackgroundDownloadPreExecutionStopPersister(coordinator).persist("missing", 7)
      assertFalse(missing.persisted)
      assertEquals(null, missing.record)
    } finally {
      root.deleteRecursively()
    }
  }

  @Test
  fun stopPersistenceContainsRuntimeProviderFailure() {
    val result = BackgroundDownloadStopPersistence {
      throw IllegalStateException("runtime unavailable")
    }.persist(TASK_ID, 12)
    assertFalse(result.persisted)
    assertEquals(null, result.record)
  }

  @Test
  fun actionDispatchAlwaysFinishesAndContainsActionOrExecutorFailures() {
    val calls = mutableListOf<String>()
    BackgroundDownloadActionDispatch.dispatch(
      execute = { throw java.util.concurrent.RejectedExecutionException("closed") },
      action = { calls += "action" },
      onFailure = { calls += "failure:${it::class.simpleName}" },
      finish = { calls += "finish" },
    )
    assertEquals(listOf("failure:RejectedExecutionException", "finish"), calls)

    calls.clear()
    BackgroundDownloadActionDispatch.dispatch(
      execute = { it() },
      action = { throw IllegalStateException("boom") },
      onFailure = { calls += "failure:${it::class.simpleName}" },
      finish = { calls += "finish" },
    )
    assertEquals(listOf("failure:IllegalStateException", "finish"), calls)
  }

  @Test
  fun actionFailureRepublishReflectsDurableStatus() {
    assertEquals(
      BackgroundDownloadNotificationState.running,
      BackgroundDownloadDurableNotificationPolicy.forStatus(BackgroundDownloadStatus.running),
    )
    assertEquals(
      BackgroundDownloadNotificationState.running,
      BackgroundDownloadDurableNotificationPolicy.forStatus(BackgroundDownloadStatus.verifying),
    )
    assertEquals(
      BackgroundDownloadNotificationState.waiting,
      BackgroundDownloadDurableNotificationPolicy.forStatus(BackgroundDownloadStatus.pausedBySystem),
    )
  }

  @Test
  fun foregroundWorkerCleanupRunsEvenWhenUnexpectedWorkThrows() {
    val calls = mutableListOf<String>()
    BackgroundDownloadWorkerBoundary.run(
      work = { throw IllegalStateException("boom") },
      onFailure = { calls += "failure" },
      cleanup = { calls += "cleanup" },
    )
    assertEquals(listOf("failure", "cleanup"), calls)
  }

  @Test
  fun workerSubmissionRejectionRunsCleanupPath() {
    val calls = mutableListOf<String>()
    val submitted = BackgroundDownloadWorkerSubmission.submit(
      execute = { throw java.util.concurrent.RejectedExecutionException("closed") },
      work = { calls += "work" },
      onRejected = { calls += "rejected" },
    )
    assertFalse(submitted)
    assertEquals(listOf("rejected"), calls)
  }

  @Test
  fun foregroundLifecycleSlotLinearizesNewStartsAndFinalization() {
    val slot = BackgroundDownloadForegroundLifecycleSlot<Any>()
    val first = slot.admit(TASK_ID, 1)
    assertTrue(first.shouldPromote)
    val execution = Any()
    assertTrue(slot.activate(first.token, execution))

    val whileActive = slot.admit("other_task", 2)
    assertFalse(whileActive.shouldPromote)
    assertEquals(TASK_ID, whileActive.token.id)
    var finalizedStartId: Int? = null
    assertTrue(slot.finalizeWith(execution) { finalizedStartId = it })
    assertEquals(2, finalizedStartId)

    val afterFinalize = slot.admit("other_task", 3)
    assertTrue(afterFinalize.shouldPromote)
    assertEquals("other_task", afterFinalize.token.id)
  }

  @Test
  fun foregroundLifecycleSlotAbsorbsDifferentTaskWhilePromotionPending() {
    val slot = BackgroundDownloadForegroundLifecycleSlot<Any>()
    val pending = slot.admit(TASK_ID, 10)
    val other = slot.admit("other_task", 11)

    assertTrue(pending.shouldPromote)
    assertFalse(other.shouldPromote)
    assertEquals(TASK_ID, other.token.id)
    assertEquals(11, other.token.latestStartId.get())
  }

  @Test
  fun foregroundFinalizeHoldsAdmissionUntilNotificationAndStopComplete() {
    val slot = BackgroundDownloadForegroundLifecycleSlot<Any>()
    val first = slot.admit(TASK_ID, 1)
    val execution = Any()
    assertTrue(slot.activate(first.token, execution))
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    val pool = Executors.newFixedThreadPool(2)
    try {
      val finalizing = pool.submit(java.util.concurrent.Callable<Boolean> {
        slot.finalizeWith(execution) {
          entered.countDown()
          release.await(5, TimeUnit.SECONDS)
        }
      })
      assertTrue(entered.await(5, TimeUnit.SECONDS))
      val admission = pool.submit(
        java.util.concurrent.Callable<BackgroundDownloadForegroundLifecycleSlot.Admission> {
          slot.admit("next_task", 2)
        },
      )
      Thread.sleep(50)
      assertFalse(admission.isDone)
      release.countDown()
      assertTrue(finalizing.get(5, TimeUnit.SECONDS))
      assertTrue(admission.get(5, TimeUnit.SECONDS).shouldPromote)
    } finally {
      release.countDown()
      pool.shutdownNow()
    }
  }

  private fun scheduler(
    platform: FakeSchedulingPlatform,
    record: BackgroundDownloadRecord,
    failedNewTasks: MutableList<String> = mutableListOf(),
  ) = BackgroundDownloadScheduler(
    platform = platform,
    loadRecord = { id -> record.also { assertEquals(TASK_ID, id) } },
    failRejectedNewTask = { failedNewTasks += it },
  )

  private fun record(
    id: String = TASK_ID,
    status: BackgroundDownloadStatus = BackgroundDownloadStatus.queued,
    downloadedBytes: Long = 0,
  ) = BackgroundDownloadRecord(
    revision = 1,
    id = id,
    packageUrl = "https://example.test/app.apk",
    status = status,
    downloadedBytes = downloadedBytes,
    totalBytes = 100,
    expectedSizeBytes = 100,
    expectedSha256 = "a".repeat(64),
    createdAtEpochMs = 1,
    updatedAtEpochMs = 1,
  )

  private class FakeSchedulingPlatform(
    override val sdkInt: Int,
    private val uidtAccepted: Boolean = true,
    private val setupFailure: RuntimeException? = null,
    private val uidtFailure: RuntimeException? = null,
    private val serviceFailure: RuntimeException? = null,
  ) : BackgroundDownloadSchedulingPlatform {
    val uidtJobs = mutableListOf<UserInitiatedJobSpec>()
    val serviceStarts = mutableListOf<ServiceStart>()

    override fun requireHostSetup(mode: BackgroundDownloadSchedulingMode) {
      setupFailure?.let { throw it }
    }

    override fun scheduleUserInitiatedJob(spec: UserInitiatedJobSpec): Boolean {
      uidtJobs += spec
      uidtFailure?.let { throw it }
      return uidtAccepted
    }

    override fun startService(taskId: String, foreground: Boolean) {
      serviceStarts += ServiceStart(taskId, foreground)
      serviceFailure?.let { throw it }
    }

    override fun cancelUserInitiatedJob(jobId: Int) = Unit
  }

  private class RecordingJobBuilder : BackgroundDownloadJobBuilder<String> {
    val calls = mutableListOf<String>()
    override fun setTaskIdOnly(key: String, taskId: String) = apply { calls += "extra:$key=$taskId" }
    override fun setPersisted(value: Boolean) = apply { calls += "persisted:$value" }
    override fun requireInternetNetwork() = apply { calls += "internet" }
    override fun setEstimatedDownloadBytes(bytes: Long) = apply { calls += "estimate:$bytes" }
    override fun setUserInitiated(value: Boolean) = apply { calls += "userInitiated:$value" }
    override fun build(): String = "built".also { calls += "build" }
  }

  private class SchedulerTestRecordFileFactory : BackgroundRecordFileFactory {
    override fun create(file: File): BackgroundRecordFile = object : BackgroundRecordFile {
      override fun exists(): Boolean = file.isFile
      override fun readText(): String = file.readText()
      override fun writeText(contents: String) {
        file.parentFile?.mkdirs()
        file.writeText(contents)
      }
      override fun delete() {
        file.delete()
      }
    }
  }

  private companion object {
    const val TASK_ID = "task_1"
  }
}
