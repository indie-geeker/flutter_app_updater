package com.indiegeeker.flutter_app_updater.background

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.util.concurrent.atomic.AtomicBoolean

internal object BackgroundDownloadActionDispatch {
  fun dispatch(
    execute: ((() -> Unit) -> Unit),
    action: () -> Unit,
    onFailure: (Throwable) -> Unit,
    finish: () -> Unit,
  ) {
    val finished = AtomicBoolean()
    fun finishOnce() {
      if (finished.compareAndSet(false, true)) finish()
    }
    val work: () -> Unit = {
      try {
        action()
      } catch (error: Exception) {
        runCatching { onFailure(error) }
      } finally {
        finishOnce()
      }
      Unit
    }
    try {
      execute(work)
    } catch (error: Exception) {
      runCatching { onFailure(error) }
      finishOnce()
    }
  }
}

internal object BackgroundDownloadDurableNotificationPolicy {
  fun forStatus(status: BackgroundDownloadStatus): BackgroundDownloadNotificationState = when (status) {
    BackgroundDownloadStatus.running,
    BackgroundDownloadStatus.verifying,
    -> BackgroundDownloadNotificationState.running
    BackgroundDownloadStatus.completed -> BackgroundDownloadNotificationState.completed
    BackgroundDownloadStatus.failed -> BackgroundDownloadNotificationState.failed
    BackgroundDownloadStatus.canceled -> BackgroundDownloadNotificationState.cancel
    else -> BackgroundDownloadNotificationState.waiting
  }
}

internal class BackgroundDownloadActionHandler(
  private val stopActiveExecution: (String) -> Unit,
  private val cancelScheduledExecution: (String) -> Unit,
  private val persistCancellation: (String) -> Unit,
  private val scheduleResume: (String) -> Unit,
) {
  fun cancel(id: String) {
    BackgroundDownloadContract.requireValidId(id)
    stopActiveExecution(id)
    cancelScheduledExecution(id)
    persistCancellation(id)
  }

  fun retry(id: String) {
    BackgroundDownloadContract.requireValidId(id)
    scheduleResume(id)
  }
}
internal object BackgroundDownloadActiveExecutions {
  private val controls = mutableMapOf<String, BackgroundDownloadExecutionControl>()

  @Synchronized
  fun register(id: String, control: BackgroundDownloadExecutionControl): Boolean =
    if (controls.containsKey(id)) false else {
      controls[id] = control
      true
    }

  @Synchronized
  fun unregister(id: String, control: BackgroundDownloadExecutionControl) {
    if (controls[id] === control) controls.remove(id)
  }

  @Synchronized
  fun cancel(id: String) {
    controls[id]?.requestCancel()
  }
}

class BackgroundDownloadActionReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val id = intent.getStringExtra(BackgroundDownloadScheduler.EXTRA_TASK_ID)
      ?.takeIf(BackgroundDownloadContract::isValidId)
      ?: return
    if (intent.action != ACTION_CANCEL && intent.action != ACTION_RETRY) return
    val pendingResult = goAsync()
    val appContext = context.applicationContext ?: context
    var runtime: BackgroundDownloadRuntime? = null
    BackgroundDownloadActionDispatch.dispatch(
      execute = { work ->
        val initialized = BackgroundDownloadRuntime.get(appContext)
        runtime = initialized
        initialized.scheduledExecutor.execute(work)
      },
      action = {
        val initialized = checkNotNull(runtime)
        val scheduler = BackgroundDownloadScheduler(appContext)
        val handler = BackgroundDownloadActionHandler(
          stopActiveExecution = BackgroundDownloadActiveExecutions::cancel,
          cancelScheduledExecution = { taskId ->
            val record = initialized.store.read(taskId)
            scheduler.cancelScheduled(record)
          },
          persistCancellation = { taskId ->
            val record = initialized.store.read(taskId)
            if (!record.status.isTerminal) initialized.coordinator.cancel(taskId)
          },
          scheduleResume = { taskId ->
            scheduler.schedule(taskId, BackgroundDownloadScheduleOperation.resume)
          },
        )
        if (intent.action == ACTION_CANCEL) handler.cancel(id) else handler.retry(id)
      },
      onFailure = {
        runtime?.let { republishDurableState(it, appContext, id) }
      },
      finish = pendingResult::finish,
    )
  }

  private fun republishDurableState(
    runtime: BackgroundDownloadRuntime,
    context: Context,
    id: String,
  ) {
    val record = runCatching { runtime.store.read(id) }.getOrNull() ?: return
    val notifications = BackgroundDownloadNotifications(context)
    when (BackgroundDownloadDurableNotificationPolicy.forStatus(record.status)) {
      BackgroundDownloadNotificationState.completed ->
        notifications.publish(record, notifications.completed(record), force = true)
      BackgroundDownloadNotificationState.failed ->
        notifications.publish(record, notifications.failed(record), force = true)
      BackgroundDownloadNotificationState.cancel -> notifications.cancel(record)
      BackgroundDownloadNotificationState.running ->
        notifications.publish(record, notifications.running(record), force = true)
      BackgroundDownloadNotificationState.waiting ->
        notifications.publish(record, notifications.waiting(record), force = true)
    }
  }

  companion object {
    const val ACTION_CANCEL = "com.indiegeeker.flutter_app_updater.background.CANCEL"
    const val ACTION_RETRY = "com.indiegeeker.flutter_app_updater.background.RETRY"
  }
}
