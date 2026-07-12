package com.indiegeeker.flutter_app_updater.background

import android.app.job.JobParameters
import android.app.job.JobService
import android.net.Network
import android.os.Build
import androidx.annotation.RequiresApi
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

internal class UserInitiatedJobCompletionGate {
  private var stopped = false
  private var finished = false
  private var begun = false

  @Synchronized
  fun begin(): Boolean {
    if (stopped || finished || begun) return false
    begun = true
    return true
  }

  @Synchronized
  fun finish(action: () -> Unit): Boolean {
    if (stopped || finished) return false
    finished = true
    action()
    return true
  }

  @Synchronized
  fun stop(action: () -> Unit): Boolean {
    if (stopped || finished) return false
    stopped = true
    action()
    return true
  }

  @Synchronized
  fun isStopped(): Boolean = stopped

  @Synchronized
  fun mayExecute(): Boolean = !stopped && !finished

  @Synchronized
  fun hasBegun(): Boolean = begun

  @Synchronized
  fun runIfActive(action: () -> Unit): Boolean {
    if (stopped || finished) return false
    action()
    return true
  }
}

internal class BackgroundDownloadPreExecutionStopPersister(
  private val coordinator: BackgroundDownloadCoordinator,
) {
  data class Result(val record: BackgroundDownloadRecord?, val persisted: Boolean)

  fun persist(
    id: String,
    rawStopReason: Int?,
    nativeErrorCode: String? = null,
  ): Result {
    return try {
      Result(
        coordinator.pauseBySystem(
          id = id,
          rawStopReason = rawStopReason,
          errorCode = if (nativeErrorCode == null) null else "PACKAGE_DOWNLOAD_FAILED",
          errorMessage = if (nativeErrorCode == null) null else
            "Background execution is temporarily unavailable",
          nativeErrorCode = nativeErrorCode,
        ),
        true,
      )
    } catch (_: Exception) {
      Result(null, false)
    }
  }
}

internal class BackgroundDownloadStopPersistence(
  private val coordinatorProvider: () -> BackgroundDownloadCoordinator,
) {
  fun persist(
    id: String,
    rawStopReason: Int?,
    nativeErrorCode: String? = null,
  ): BackgroundDownloadPreExecutionStopPersister.Result = runCatching {
    BackgroundDownloadPreExecutionStopPersister(coordinatorProvider())
      .persist(id, rawStopReason, nativeErrorCode)
  }.getOrElse { BackgroundDownloadPreExecutionStopPersister.Result(null, false) }
}

internal class UserInitiatedJobNetworkBinding<T>(
  initialNetwork: T,
  private val stopOldExecution: (T) -> Unit,
) {
  private var network = initialNetwork

  @Synchronized
  fun replace(next: T) {
    if (network == next) return
    stopOldExecution(network)
    network = next
  }

  @Synchronized
  fun current(): T = network
}

internal class UserInitiatedJobNetworkGate<T>(initialNetwork: T) {
  data class Lease<T>(val network: T, val generation: Long)
  enum class Decision { restart, close }

  private var network = initialNetwork
  private var generation = 0L
  private var closed = false

  @Synchronized
  fun lease(): Lease<T>? = if (closed) null else Lease(network, generation)

  @Synchronized
  fun rebind(next: T, stopOldExecution: () -> Unit): Boolean {
    if (closed || network == next) return false
    generation += 1
    stopOldExecution()
    network = next
    return true
  }

  @Synchronized
  fun finish(lease: Lease<T>): Decision {
    if (closed) return Decision.close
    if (lease.generation != generation) return Decision.restart
    closed = true
    return Decision.close
  }

  @Synchronized
  fun close() {
    closed = true
  }
}

class UserInitiatedDownloadJobService : JobService() {
  private val active = AtomicReference<ActiveJob?>()

  override fun onStartJob(params: JobParameters): Boolean {
    if (Build.VERSION.SDK_INT < 34) return false
    val id = params.extras.getString(BackgroundDownloadScheduler.EXTRA_TASK_ID)
      ?.takeIf(BackgroundDownloadContract::isValidId)
      ?: return false

    val notifications = BackgroundDownloadNotifications(this)
    val initialNetwork = params.network
    if (initialNetwork == null) {
      val stopped = persistPreExecutionStop(id, null)
      stopped.record?.let { record ->
        BackgroundDownloadNotificationPermissionBoundary.attempt {
          setUidtNotification(params, notifications.waiting(record), JOB_END_NOTIFICATION_POLICY_DETACH)
        }
      }
      return false
    }

    // UIDT requires this call within ten seconds. Do it before runtime/store I/O.
    val notified = BackgroundDownloadNotificationPermissionBoundary.attempt {
      setUidtNotification(params, notifications.starting(id), JOB_END_NOTIFICATION_POLICY_DETACH)
    }
    if (!notified) {
      val stopped = persistPreExecutionStop(id, null)
      stopped.record?.let { notifications.publish(it, notifications.waiting(it), force = true) }
      return false
    }
    val runtime = try {
      BackgroundDownloadRuntime.get(this)
    } catch (_: Exception) {
      BackgroundDownloadNotificationPermissionBoundary.attempt {
        setUidtNotification(
          params,
          notifications.starting(id),
          JOB_END_NOTIFICATION_POLICY_REMOVE,
        )
      }
      notifications.cancelId(BackgroundDownloadContract.DEFAULT_NOTIFICATION_ID)
      return false
    }
    val job = ActiveJob(params, id, initialNetwork)
    if (!active.compareAndSet(null, job)) {
      job.completion.runIfActive {
        BackgroundDownloadNotificationPermissionBoundary.attempt {
          setUidtNotification(
            params,
            notifications.starting(id),
            JOB_END_NOTIFICATION_POLICY_REMOVE,
          )
        }
      }
      return false
    }
    try {
      job.progress.set(
        runtime.scheduledExecutor.scheduleWithFixedDelay(
          { publishProgress(runtime, notifications, job) },
          1,
          1,
          TimeUnit.SECONDS,
        ),
      )
      runtime.workerExecutor.execute { runJob(runtime, notifications, job) }
    } catch (_: Exception) {
      job.progress.getAndSet(null)?.cancel(false)
      job.completion.runIfActive {
        BackgroundDownloadNotificationPermissionBoundary.attempt {
          setUidtNotification(
            params,
            notifications.starting(id),
            JOB_END_NOTIFICATION_POLICY_REMOVE,
          )
        }
      }
      job.completion.stop { persistPreExecutionStop(id, null) }
      active.compareAndSet(job, null)
      return false
    }
    return true
  }

  override fun onStopJob(params: JobParameters): Boolean {
    val job = active.get() ?: return false
    val rawReason = stopReason(params)
    job.rawStopReason.set(rawReason)
    job.completion.stop {
      job.progress.getAndSet(null)?.cancel(false)
      job.network.close()
      val record = if (job.completion.hasBegun()) {
        job.control.get()?.requestSystemStop(rawReason)
        runCatching { BackgroundDownloadRuntime.get(this).store.read(job.id) }.getOrNull()
      } else {
        persistPreExecutionStop(job.id, rawReason).record
      }
      val notifications = BackgroundDownloadNotifications(this)
      if (record != null && !record.status.isTerminal) {
        BackgroundDownloadNotificationPermissionBoundary.attempt {
          if (Build.VERSION.SDK_INT >= 34) {
            setUidtNotification(
              params,
              notifications.waiting(record),
              JOB_END_NOTIFICATION_POLICY_DETACH,
            )
          }
        }
      } else if (record == null) {
        BackgroundDownloadNotificationPermissionBoundary.attempt {
          if (Build.VERSION.SDK_INT >= 34) {
            setUidtNotification(
              params,
              notifications.starting(job.id),
              JOB_END_NOTIFICATION_POLICY_REMOVE,
            )
          }
        }
        notifications.cancelId(BackgroundDownloadContract.DEFAULT_NOTIFICATION_ID)
      }
    }
    active.compareAndSet(job, null)
    // Explicit resume is required. Never call jobFinished after this callback.
    return false
  }

  override fun onNetworkChanged(params: JobParameters) {
    if (Build.VERSION.SDK_INT < 34) return
    val job = active.get() ?: return
    val next = params.network ?: return
    job.network.rebind(next) { job.control.get()?.requestSystemStop() }
  }

  private fun runJob(
    runtime: BackgroundDownloadRuntime,
    notifications: BackgroundDownloadNotifications,
    job: ActiveJob,
  ) {
    BackgroundDownloadWorkerBoundary.run(
      work = work@{
        // Install the control before linearizing the start. If onStopJob wins,
        // begin() returns false and no engine/network work starts.
        val initialControl = BackgroundDownloadExecutionControl()
        job.control.set(initialControl)
        if (!job.completion.begin()) return@work
        while (job.completion.mayExecute()) {
          val lease = job.network.lease() ?: break
          val control = job.control.getAndSet(null) ?: BackgroundDownloadExecutionControl()
          job.control.set(control)
          // Linearization with onStopJob: if stop won before this set, observe
          // stopped and do not execute; if stop wins after it, it sees control.
          if (!job.completion.mayExecute()) {
            job.control.compareAndSet(control, null)
            break
          }
          if (!BackgroundDownloadActiveExecutions.register(job.id, control)) {
            val record = runCatching { runtime.store.read(job.id) }.getOrNull()
            if (record != null && Build.VERSION.SDK_INT >= 34) {
              job.completion.runIfActive {
                BackgroundDownloadNotificationPermissionBoundary.attempt {
                  setUidtNotification(
                    job.params,
                    notifications.failed(record),
                    JOB_END_NOTIFICATION_POLICY_REMOVE,
                  )
                }
              }
            } else {
              job.completion.runIfActive {
                notifications.cancelId(BackgroundDownloadContract.DEFAULT_NOTIFICATION_ID)
              }
            }
            break
          }
          val result = try {
            runtime.engine.execute(
              job.id,
              connectionFactory = UrlHttpDownloadConnectionFactory(lease.network::openConnection),
              control = control,
            )
          } finally {
            BackgroundDownloadActiveExecutions.unregister(job.id, control)
            job.control.compareAndSet(control, null)
          }
          when (job.network.finish(lease)) {
            UserInitiatedJobNetworkGate.Decision.restart -> continue
            UserInitiatedJobNetworkGate.Decision.close -> {
              val durableRecord = result.record ?: runCatching { runtime.store.read(job.id) }.getOrNull()
              publishOutcome(job, notifications, result, durableRecord)
              break
            }
          }
        }
      },
      onFailure = {
        val recovered = runCatching {
          BackgroundDownloadPreExecutionStopPersister(runtime.coordinator)
            .persist(job.id, job.rawStopReason.get(), "uidt_worker_error")
        }.getOrNull()
        val record = recovered?.record ?: runCatching { runtime.store.read(job.id) }.getOrNull()
        publishRecoveryNotification(job, notifications, record)
      },
      cleanup = {
        job.progress.getAndSet(null)?.cancel(false)
        job.completion.finish { jobFinished(job.params, false) }
        active.compareAndSet(job, null)
      },
    )
  }

  private fun publishOutcome(
    job: ActiveJob,
    notifications: BackgroundDownloadNotifications,
    result: BackgroundDownloadExecutionResult,
    record: BackgroundDownloadRecord?,
  ) {
    if (record == null) {
      publishRecoveryNotification(job, notifications, null)
      return
    }
    val notification = when (BackgroundDownloadNotificationStatePolicy.forOutcome(result.outcome)) {
      BackgroundDownloadNotificationState.completed -> notifications.completed(record)
      BackgroundDownloadNotificationState.waiting -> notifications.waiting(record)
      BackgroundDownloadNotificationState.failed -> notifications.failed(record)
      // Transient only; jobFinished immediately applies REMOVE end policy.
      BackgroundDownloadNotificationState.cancel -> notifications.failed(record)
      BackgroundDownloadNotificationState.running -> notifications.running(record)
    }
    job.completion.runIfActive {
      val published = BackgroundDownloadNotificationPermissionBoundary.attempt {
        if (Build.VERSION.SDK_INT >= 34) {
          val policy = if (BackgroundDownloadNotificationStatePolicy.forOutcome(result.outcome) ==
            BackgroundDownloadNotificationState.cancel
          ) JOB_END_NOTIFICATION_POLICY_REMOVE else JOB_END_NOTIFICATION_POLICY_DETACH
          setUidtNotification(job.params, notification, policy)
        }
      }
      if (!published) notifications.cancel(record)
    }
  }

  private fun publishRecoveryNotification(
    job: ActiveJob,
    notifications: BackgroundDownloadNotifications,
    record: BackgroundDownloadRecord?,
  ) {
    val state = BackgroundDownloadUidtRecoveryNotificationPolicy.forRecord(record)
    val notification = when (state) {
      BackgroundDownloadNotificationState.completed -> notifications.completed(checkNotNull(record))
      BackgroundDownloadNotificationState.failed -> notifications.failed(checkNotNull(record))
      BackgroundDownloadNotificationState.waiting -> notifications.waiting(checkNotNull(record))
      BackgroundDownloadNotificationState.cancel -> notifications.starting(record?.id ?: job.id)
      BackgroundDownloadNotificationState.running -> notifications.running(checkNotNull(record))
    }
    val endPolicy = if (state == BackgroundDownloadNotificationState.cancel) {
      JOB_END_NOTIFICATION_POLICY_REMOVE
    } else {
      JOB_END_NOTIFICATION_POLICY_DETACH
    }
    job.completion.runIfActive {
      val published = BackgroundDownloadNotificationPermissionBoundary.attempt {
        if (Build.VERSION.SDK_INT >= 34) {
          setUidtNotification(job.params, notification, endPolicy)
        }
      }
      if (!published) {
        if (record == null) {
          notifications.cancelId(BackgroundDownloadContract.DEFAULT_NOTIFICATION_ID)
        } else {
          notifications.cancel(record)
        }
      }
    }
  }

  private fun publishProgress(
    runtime: BackgroundDownloadRuntime,
    notifications: BackgroundDownloadNotifications,
    job: ActiveJob,
  ) {
    val record = runCatching { runtime.store.read(job.id) }.getOrNull()
      ?.takeIf { it.status == BackgroundDownloadStatus.running }
      ?: return
    job.completion.runIfActive {
      val published = BackgroundDownloadNotificationPermissionBoundary.attempt {
        if (Build.VERSION.SDK_INT >= 34) {
          setUidtNotification(
            job.params,
            notifications.running(record),
            JOB_END_NOTIFICATION_POLICY_DETACH,
          )
        }
      }
      if (!published) job.control.get()?.requestSystemStop()
    }
  }

  @RequiresApi(34)
  private fun setUidtNotification(
    params: JobParameters,
    notification: android.app.Notification,
    endPolicy: Int,
  ) {
    setNotification(
      params,
      BackgroundDownloadContract.DEFAULT_NOTIFICATION_ID,
      notification,
      endPolicy,
    )
  }

  private fun stopReason(params: JobParameters): Int? =
    if (Build.VERSION.SDK_INT >= 31) stopReasonApi31(params) else null

  @RequiresApi(31)
  private fun stopReasonApi31(params: JobParameters): Int = params.stopReason

  private fun persistPreExecutionStop(
    id: String,
    rawStopReason: Int?,
  ): BackgroundDownloadPreExecutionStopPersister.Result {
    return BackgroundDownloadStopPersistence {
      BackgroundDownloadRuntime.get(this).coordinator
    }.persist(id, rawStopReason)
  }

  private class ActiveJob(
    val params: JobParameters,
    val id: String,
    initialNetwork: Network,
  ) {
    val completion = UserInitiatedJobCompletionGate()
    val control = AtomicReference<BackgroundDownloadExecutionControl?>()
    val rawStopReason = AtomicReference<Int?>(null)
    val progress = AtomicReference<ScheduledFuture<*>?>()
    val network = UserInitiatedJobNetworkGate(initialNetwork)
  }
}

internal object BackgroundDownloadNotificationPermissionBoundary {
  fun attempt(action: () -> Unit): Boolean = try {
    action()
    true
  } catch (_: SecurityException) {
    false
  }
}

internal object BackgroundDownloadUidtRecoveryNotificationPolicy {
  fun forRecord(record: BackgroundDownloadRecord?): BackgroundDownloadNotificationState = when {
    record == null -> BackgroundDownloadNotificationState.cancel
    record.status == BackgroundDownloadStatus.completed -> BackgroundDownloadNotificationState.completed
    record.status == BackgroundDownloadStatus.failed -> BackgroundDownloadNotificationState.failed
    record.status == BackgroundDownloadStatus.canceled -> BackgroundDownloadNotificationState.cancel
    else -> BackgroundDownloadNotificationState.waiting
  }
}
