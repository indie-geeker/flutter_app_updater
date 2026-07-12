package com.indiegeeker.flutter_app_updater.background

import android.annotation.SuppressLint
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import androidx.core.app.ServiceCompat
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

internal object BackgroundDownloadForegroundBootstrap {
  fun start(promote: () -> Unit, beginWork: () -> Unit): Int {
    promote()
    beginWork()
    return Service.START_NOT_STICKY
  }
}

internal enum class BackgroundDownloadNotificationState { running, waiting, completed, failed, cancel }

internal object BackgroundDownloadNotificationStatePolicy {
  fun forOutcome(outcome: BackgroundDownloadExecutionOutcome): BackgroundDownloadNotificationState = when (outcome) {
    BackgroundDownloadExecutionOutcome.completed -> BackgroundDownloadNotificationState.completed
    BackgroundDownloadExecutionOutcome.waitingForNetwork,
    BackgroundDownloadExecutionOutcome.waitingForStorage,
    BackgroundDownloadExecutionOutcome.pausedBySystem,
    -> BackgroundDownloadNotificationState.waiting
    BackgroundDownloadExecutionOutcome.failed -> BackgroundDownloadNotificationState.failed
    BackgroundDownloadExecutionOutcome.canceled,
    BackgroundDownloadExecutionOutcome.alreadyRunning,
    -> BackgroundDownloadNotificationState.cancel
  }
}

internal enum class BackgroundDownloadForegroundAdmission {
  newExecution,
  reuseExecution,
  keepExistingExecution,
  reject,
}

internal object BackgroundDownloadForegroundAdmissionPolicy {
  fun decide(
    activeTaskId: String?,
    incomingTaskId: String,
    registrationSucceeded: Boolean,
  ): BackgroundDownloadForegroundAdmission = when {
    activeTaskId == incomingTaskId -> BackgroundDownloadForegroundAdmission.reuseExecution
    activeTaskId != null -> BackgroundDownloadForegroundAdmission.keepExistingExecution
    registrationSucceeded -> BackgroundDownloadForegroundAdmission.newExecution
    else -> BackgroundDownloadForegroundAdmission.reject
  }
}

internal object BackgroundDownloadWorkerBoundary {
  fun run(work: () -> Unit, onFailure: (Exception) -> Unit, cleanup: () -> Unit) {
    try {
      work()
    } catch (error: Exception) {
      onFailure(error)
    } finally {
      cleanup()
    }
  }
}

internal object BackgroundDownloadWorkerSubmission {
  fun submit(execute: ((() -> Unit) -> Unit), work: () -> Unit, onRejected: (Exception) -> Unit): Boolean =
    try {
      execute(work)
      true
    } catch (error: Exception) {
      onRejected(error)
      false
    }
}

internal class BackgroundDownloadForegroundLifecycleSlot<T : Any> {
  data class Token(val id: String, val latestStartId: AtomicInteger)
  data class Admission(val token: Token, val shouldPromote: Boolean)

  private var pending: Token? = null
  private var active: Pair<Token, T>? = null

  @Synchronized
  fun admit(id: String, startId: Int): Admission {
    active?.let { (token, _) ->
      token.latestStartId.set(startId)
      return Admission(token, false)
    }
    pending?.let { token ->
      token.latestStartId.set(startId)
      return Admission(token, false)
    }
    val token = Token(id, AtomicInteger(startId))
    pending = token
    return Admission(token, true)
  }

  @Synchronized
  fun activate(token: Token, value: T): Boolean {
    if (pending !== token || active != null) return false
    pending = null
    active = token to value
    return true
  }

  @Synchronized
  fun activeValue(): T? = active?.second

  @Synchronized
  fun finalizeWith(value: T, action: (Int) -> Unit): Boolean {
    val current = active ?: return false
    if (current.second !== value) return false
    try {
      action(current.first.latestStartId.get())
    } finally {
      active = null
    }
    return true
  }

  @Synchronized
  fun release(token: Token) {
    if (pending === token) pending = null
  }
}

class BackgroundDownloadForegroundService : Service() {
  private val lifecycle = BackgroundDownloadForegroundLifecycleSlot<ActiveServiceExecution>()

  override fun onBind(intent: Intent?): IBinder? = null

  @SuppressLint("InlinedApi")
  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    val id = intent?.getStringExtra(BackgroundDownloadScheduler.EXTRA_TASK_ID)
      ?.takeIf(BackgroundDownloadContract::isValidId)
      ?: return START_NOT_STICKY.also { stopSelfResult(startId) }
    val admission = lifecycle.admit(id, startId)
    // Do not replace the visible notification or demote an existing task.
    if (!admission.shouldPromote) return START_NOT_STICKY
    val accepted = admission.token
    val notifications = BackgroundDownloadNotifications(this)
    return try {
      val result = BackgroundDownloadForegroundBootstrap.start(
        promote = {
          ServiceCompat.startForeground(
            this,
            BackgroundDownloadContract.DEFAULT_NOTIFICATION_ID,
            notifications.starting(accepted.id),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
          )
        },
        beginWork = {
          if (!beginExecution(accepted, notifications)) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelfResult(accepted.latestStartId.get())
          }
        },
      )
      result
    } catch (error: SecurityException) {
      // This can indicate missing FGS permission/type, not notification denial.
      releasePending(accepted)
      persistRecoverableStop(accepted.id, "foreground_start_security")
      ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
      stopSelfResult(accepted.latestStartId.get())
      START_NOT_STICKY
    } catch (_: Exception) {
      releasePending(accepted)
      persistRecoverableStop(accepted.id, "foreground_start_error")
      ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
      stopSelfResult(accepted.latestStartId.get())
      START_NOT_STICKY
    }
  }

  override fun onDestroy() {
    lifecycle.activeValue()?.control?.requestSystemStop()
    super.onDestroy()
  }

  private fun beginExecution(
    admission: BackgroundDownloadForegroundLifecycleSlot.Token,
    notifications: BackgroundDownloadNotifications,
  ): Boolean {
    val id = admission.id
    val runtime = BackgroundDownloadRuntime.get(this)
    val control = BackgroundDownloadExecutionControl()
    val registered = BackgroundDownloadActiveExecutions.register(id, control)
    if (BackgroundDownloadForegroundAdmissionPolicy.decide(null, id, registered) ==
      BackgroundDownloadForegroundAdmission.reject
    ) {
      releasePending(admission)
      return false
    }
    val progress = try {
      runtime.scheduledExecutor.scheduleWithFixedDelay(
        {
          runCatching { runtime.store.read(id) }
            .getOrNull()
            ?.takeIf { it.status == BackgroundDownloadStatus.running }
            ?.let { notifications.publish(it, notifications.running(it)) }
        },
        1,
        1,
        TimeUnit.SECONDS,
      )
    } catch (_: Exception) {
      BackgroundDownloadActiveExecutions.unregister(id, control)
      releasePending(admission)
      persistRecoverableStop(id, "foreground_progress_executor_rejected")
      return false
    }
    val execution = ActiveServiceExecution(id, admission.latestStartId, control, progress)
    val installed = lifecycle.activate(admission, execution)
    if (!installed) {
      progress.cancel(false)
      BackgroundDownloadActiveExecutions.unregister(id, control)
      return false
    }
    BackgroundDownloadWorkerSubmission.submit(
      execute = { work -> runtime.workerExecutor.execute(work) },
      work = {
        var result: BackgroundDownloadExecutionResult? = null
        var failureRecord: BackgroundDownloadRecord? = null
        BackgroundDownloadWorkerBoundary.run(
          work = {
            result = runtime.engine.execute(id, control = control)
          },
          onFailure = {
            persistRecoverableStop(id, "foreground_worker_error")
            failureRecord = runCatching { runtime.store.read(id) }.getOrNull()
          },
          cleanup = {
            progress.cancel(false)
            BackgroundDownloadActiveExecutions.unregister(id, control)
            lifecycle.finalizeWith(execution) { latestStartId ->
              val endPolicy = result?.let { publishOutcome(notifications, it) }
                ?: failureRecord?.takeUnless { it.status.isTerminal }?.let {
                  notifications.publish(it, notifications.waiting(it), force = true)
                  ForegroundNotificationEndPolicy.detach
                }
                ?: ForegroundNotificationEndPolicy.remove
              ServiceCompat.stopForeground(
                this,
                if (endPolicy == ForegroundNotificationEndPolicy.remove) {
                  ServiceCompat.STOP_FOREGROUND_REMOVE
                } else {
                  ServiceCompat.STOP_FOREGROUND_DETACH
                },
              )
              stopSelfResult(latestStartId)
            }
          },
        )
      },
      onRejected = {
        progress.cancel(false)
        BackgroundDownloadActiveExecutions.unregister(id, control)
        persistRecoverableStop(id, "foreground_executor_rejected")
        lifecycle.finalizeWith(execution) { latestStartId ->
          val record = runCatching { runtime.store.read(id) }.getOrNull()
          val detach = record != null && !record.status.isTerminal
          if (detach) {
            val waiting = checkNotNull(record)
            notifications.publish(waiting, notifications.waiting(waiting), force = true)
          }
          ServiceCompat.stopForeground(
            this,
            if (detach) ServiceCompat.STOP_FOREGROUND_DETACH else ServiceCompat.STOP_FOREGROUND_REMOVE,
          )
          stopSelfResult(latestStartId)
        }
      },
    )
    return true
  }

  private fun publishOutcome(
    notifications: BackgroundDownloadNotifications,
    result: BackgroundDownloadExecutionResult,
  ): ForegroundNotificationEndPolicy {
    val record = result.record ?: return ForegroundNotificationEndPolicy.remove
    return when (BackgroundDownloadNotificationStatePolicy.forOutcome(result.outcome)) {
      BackgroundDownloadNotificationState.completed ->
        ForegroundNotificationEndPolicy.detach.also {
          notifications.publish(record, notifications.completed(record), force = true)
        }
      BackgroundDownloadNotificationState.waiting ->
        ForegroundNotificationEndPolicy.detach.also {
          notifications.publish(record, notifications.waiting(record), force = true)
        }
      BackgroundDownloadNotificationState.failed ->
        ForegroundNotificationEndPolicy.detach.also {
          notifications.publish(record, notifications.failed(record), force = true)
        }
      BackgroundDownloadNotificationState.cancel -> ForegroundNotificationEndPolicy.remove.also {
        notifications.cancel(record)
      }
      BackgroundDownloadNotificationState.running ->
        ForegroundNotificationEndPolicy.detach.also {
          notifications.publish(record, notifications.running(record), force = true)
        }
    }
  }

  private fun releasePending(admission: BackgroundDownloadForegroundLifecycleSlot.Token) =
    lifecycle.release(admission)

  private fun persistRecoverableStop(id: String, nativeCode: String) {
    runCatching {
      val runtime = BackgroundDownloadRuntime.get(this)
      BackgroundDownloadPreExecutionStopPersister(runtime.coordinator).persist(id, null, nativeCode)
    }
  }

  private data class ActiveServiceExecution(
    val id: String,
    val latestStartId: AtomicInteger,
    val control: BackgroundDownloadExecutionControl,
    val progress: ScheduledFuture<*>,
  )

  private enum class ForegroundNotificationEndPolicy { remove, detach }

  companion object {
    const val ACTION_START = "com.indiegeeker.flutter_app_updater.background.START"
  }
}
