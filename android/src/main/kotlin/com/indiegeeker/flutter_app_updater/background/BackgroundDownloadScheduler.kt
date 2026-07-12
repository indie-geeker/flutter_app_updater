package com.indiegeeker.flutter_app_updater.background

import android.annotation.SuppressLint
import android.app.ForegroundServiceStartNotAllowedException
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.PersistableBundle
import androidx.annotation.RequiresApi

internal enum class BackgroundDownloadSchedulingMode {
  service,
  foregroundService,
  userInitiatedJob,
}

internal enum class BackgroundDownloadScheduleOperation { newTask, resume }

internal object BackgroundDownloadSchedulingPolicy {
  fun modeFor(sdkInt: Int): BackgroundDownloadSchedulingMode = when {
    sdkInt >= 34 -> BackgroundDownloadSchedulingMode.userInitiatedJob
    sdkInt >= 26 -> BackgroundDownloadSchedulingMode.foregroundService
    else -> BackgroundDownloadSchedulingMode.service
  }
}

internal data class UserInitiatedJobSpec(
  val jobId: Int,
  val taskId: String,
  val estimatedDownloadBytes: Long,
  val userInitiated: Boolean = true,
  val persisted: Boolean = false,
  val requiresInternet: Boolean = true,
  val extraKeys: Set<String> = setOf(BackgroundDownloadScheduler.EXTRA_TASK_ID),
)

internal data class ServiceStart(val taskId: String, val foreground: Boolean)

internal data class BackgroundDownloadHostSetupRequirements(
  val permissions: Set<String>,
  val requireDataSyncServiceType: Boolean,
) {
  companion object {
    fun forSdk(sdkInt: Int): BackgroundDownloadHostSetupRequirements {
      val permissions = linkedSetOf("android.permission.ACCESS_NETWORK_STATE")
      if (sdkInt >= 28) permissions += "android.permission.FOREGROUND_SERVICE"
      if (sdkInt >= 33) permissions += "android.permission.POST_NOTIFICATIONS"
      if (sdkInt >= 34) {
        permissions += "android.permission.FOREGROUND_SERVICE_DATA_SYNC"
        permissions += "android.permission.RUN_USER_INITIATED_JOBS"
      }
      return BackgroundDownloadHostSetupRequirements(permissions, sdkInt >= 29)
    }
  }
}

internal data class BackgroundDownloadHostComponent(
  val exported: Boolean,
  val enabled: Boolean,
  val permission: String? = null,
  val hasDataSyncType: Boolean = false,
)

internal data class BackgroundDownloadHostSetupSnapshot(
  val declaredPermissions: Set<String>,
  val jobService: BackgroundDownloadHostComponent,
  val foregroundService: BackgroundDownloadHostComponent,
  val receiver: BackgroundDownloadHostComponent,
)

internal object BackgroundDownloadHostSetupValidator {
  fun requireValid(
    requirements: BackgroundDownloadHostSetupRequirements,
    snapshot: BackgroundDownloadHostSetupSnapshot,
  ) {
    val missing = requirements.permissions - snapshot.declaredPermissions
    check(missing.isEmpty()) { "Missing background download permissions: ${missing.joinToString()}" }
    check(
      !snapshot.jobService.exported && snapshot.jobService.enabled &&
        snapshot.jobService.permission == "android.permission.BIND_JOB_SERVICE",
    ) { "UserInitiatedDownloadJobService metadata is invalid" }
    check(!snapshot.foregroundService.exported && snapshot.foregroundService.enabled) {
      "BackgroundDownloadForegroundService metadata is invalid"
    }
    if (requirements.requireDataSyncServiceType) {
      check(snapshot.foregroundService.hasDataSyncType) { "Foreground service must declare dataSync type" }
    }
    check(!snapshot.receiver.exported && snapshot.receiver.enabled) {
      "BackgroundDownloadActionReceiver metadata is invalid"
    }
  }
}

internal interface BackgroundDownloadJobBuilder<T> {
  fun setTaskIdOnly(key: String, taskId: String): BackgroundDownloadJobBuilder<T>
  fun setPersisted(value: Boolean): BackgroundDownloadJobBuilder<T>
  fun requireInternetNetwork(): BackgroundDownloadJobBuilder<T>
  fun setEstimatedDownloadBytes(bytes: Long): BackgroundDownloadJobBuilder<T>
  fun setUserInitiated(value: Boolean): BackgroundDownloadJobBuilder<T>
  fun build(): T
}

internal object BackgroundDownloadJobSpecWiring {
  fun <T> build(spec: UserInitiatedJobSpec, builder: BackgroundDownloadJobBuilder<T>): T = builder
    .setTaskIdOnly(BackgroundDownloadScheduler.EXTRA_TASK_ID, spec.taskId)
    .setPersisted(spec.persisted)
    .requireInternetNetwork()
    .setEstimatedDownloadBytes(spec.estimatedDownloadBytes)
    .setUserInitiated(spec.userInitiated)
    .build()
}

internal interface BackgroundDownloadSchedulingPlatform {
  val sdkInt: Int
  fun requireHostSetup(mode: BackgroundDownloadSchedulingMode)
  fun scheduleUserInitiatedJob(spec: UserInitiatedJobSpec): Boolean
  fun startService(taskId: String, foreground: Boolean)
  fun cancelUserInitiatedJob(jobId: Int)
}

internal open class BackgroundDownloadScheduleException(
  val code: String,
  message: String,
  cause: Throwable? = null,
) : IllegalStateException(message, cause)

internal class BackgroundDownloadPlatformStartNotAllowedException(
  message: String,
  cause: Throwable? = null,
) : IllegalStateException(message, cause)

/** Selects only Android-supported, user-visible execution mechanisms. */
internal class BackgroundDownloadScheduler internal constructor(
  private val platform: BackgroundDownloadSchedulingPlatform,
  private val loadRecord: (String) -> BackgroundDownloadRecord,
  private val failRejectedNewTask: (String) -> Unit,
) {
  constructor(context: Context) : this(
    platform = AndroidBackgroundDownloadSchedulingPlatform(context.applicationContext ?: context),
    loadRecord = { BackgroundDownloadRuntime.get(context).store.read(it) },
    failRejectedNewTask = { id -> failRejectedNewTask(BackgroundDownloadRuntime.get(context), id) },
  )

  fun schedule(id: String, operation: BackgroundDownloadScheduleOperation) {
    val validId = BackgroundDownloadContract.requireValidId(id)
    val record = loadRecord(validId)
    if (record.status.isTerminal) {
      throw BackgroundDownloadScheduleException(
        "background_task_terminal",
        "A terminal background download cannot be scheduled",
      )
    }
    val mode = BackgroundDownloadSchedulingPolicy.modeFor(platform.sdkInt)
    try {
      platform.requireHostSetup(mode)
    } catch (error: RuntimeException) {
      reject(
        validId,
        operation,
        "background_host_setup_missing",
        "The host app has not opted in to the required background component",
        error,
      )
    }

    when (mode) {
      BackgroundDownloadSchedulingMode.userInitiatedJob -> {
        val accepted = try {
          platform.scheduleUserInitiatedJob(
            UserInitiatedJobSpec(
              jobId = record.schedulerJobId,
              taskId = validId,
              estimatedDownloadBytes = (record.expectedSizeBytes - record.downloadedBytes).coerceAtLeast(0),
            ),
          )
        } catch (error: SecurityException) {
          reject(
            validId,
            operation,
            "background_schedule_not_permitted",
            "Android did not permit the user-initiated download job",
            error,
          )
        } catch (error: RuntimeException) {
          reject(
            validId,
            operation,
            "background_schedule_rejected",
            "Android rejected the user-initiated download job",
            error,
          )
        }
        if (!accepted) {
          reject(
            validId,
            operation,
            "background_schedule_rejected",
            "Android rejected the user-initiated download job",
          )
        }
      }
      BackgroundDownloadSchedulingMode.service,
      BackgroundDownloadSchedulingMode.foregroundService,
      -> try {
        platform.startService(
          validId,
          foreground = mode == BackgroundDownloadSchedulingMode.foregroundService,
        )
      } catch (error: BackgroundDownloadPlatformStartNotAllowedException) {
        reject(
          validId,
          operation,
          "background_start_not_allowed",
          "Android did not allow the foreground download service to start",
          error,
        )
      } catch (error: RuntimeException) {
        reject(
          validId,
          operation,
          "background_service_start_failed",
          "The background download service could not be started",
          error,
        )
      }
    }
  }

  fun cancelScheduled(record: BackgroundDownloadRecord) {
    if (platform.sdkInt >= 34) platform.cancelUserInitiatedJob(record.schedulerJobId)
  }

  private fun reject(
    id: String,
    operation: BackgroundDownloadScheduleOperation,
    code: String,
    message: String,
    cause: Throwable? = null,
  ): Nothing {
    if (operation == BackgroundDownloadScheduleOperation.newTask) failRejectedNewTask(id)
    throw BackgroundDownloadScheduleException(code, message, cause)
  }

  internal companion object {
    const val EXTRA_TASK_ID = "taskId"
    const val JOB_NAMESPACE = "flutter_app_updater"

    fun failRejectedNewTask(runtime: BackgroundDownloadRuntime, id: String) {
      val current = runtime.store.read(id)
      if (current.status.isTerminal) return
      val partial = runtime.store.partialFile(id)
      val apk = runtime.store.apkFile(id)
      if ((partial.exists() && !partial.delete()) || (apk.exists() && !apk.delete())) {
        throw BackgroundDownloadScheduleException(
          "background_storage_error",
          "Unable to remove bytes for a rejected background download",
        )
      }
      runtime.coordinator.transition(id, current.revision) {
        it.copy(
          status = BackgroundDownloadStatus.failed,
          downloadedBytes = 0,
          totalBytes = null,
          strongEtag = null,
          errorCode = "PACKAGE_DOWNLOAD_FAILED",
          errorMessage = "Android rejected the background download request",
          nativeErrorCode = "background_schedule_rejected",
        )
      }
    }
  }
}

private class AndroidBackgroundDownloadSchedulingPlatform(
  private val context: Context,
) : BackgroundDownloadSchedulingPlatform {
  override val sdkInt: Int get() = Build.VERSION.SDK_INT

  override fun requireHostSetup(mode: BackgroundDownloadSchedulingMode) {
    val requirements = BackgroundDownloadHostSetupRequirements.forSdk(sdkInt)
    try {
      val declaredPermissions = context.packageManager
        .getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
        .requestedPermissions
        ?.toSet()
        .orEmpty()
      val job = context.packageManager.getServiceInfo(
        ComponentName(context, UserInitiatedDownloadJobService::class.java),
        PackageManager.GET_META_DATA,
      )
      val foreground = context.packageManager.getServiceInfo(
        ComponentName(context, BackgroundDownloadForegroundService::class.java),
        PackageManager.GET_META_DATA,
      )
      val receiver = context.packageManager.getReceiverInfo(
        ComponentName(context, BackgroundDownloadActionReceiver::class.java),
        PackageManager.GET_META_DATA,
      )
      BackgroundDownloadHostSetupValidator.requireValid(
        requirements,
        BackgroundDownloadHostSetupSnapshot(
          declaredPermissions = declaredPermissions,
          jobService = BackgroundDownloadHostComponent(job.exported, job.enabled, job.permission),
          foregroundService = BackgroundDownloadHostComponent(
            foreground.exported,
            foreground.enabled,
            hasDataSyncType = if (Build.VERSION.SDK_INT >= 29) hasDataSyncTypeApi29(foreground) else false,
          ),
          receiver = BackgroundDownloadHostComponent(receiver.exported, receiver.enabled),
        ),
      )
    } catch (error: PackageManager.NameNotFoundException) {
      throw IllegalStateException("Required background download component is missing", error)
    }
  }

  @RequiresApi(29)
  private fun hasDataSyncTypeApi29(info: android.content.pm.ServiceInfo): Boolean =
    info.foregroundServiceType and 1 != 0

  @RequiresApi(34)
  @SuppressLint("MissingPermission")
  override fun scheduleUserInitiatedJob(spec: UserInitiatedJobSpec): Boolean {
    // RUN_USER_INITIATED_JOBS is deliberately supplied by the opt-in host,
    // not by the plugin manifest. persisted=false does not require boot work.
    check(Build.VERSION.SDK_INT >= 34)
    val info = BackgroundDownloadJobSpecWiring.build(
      spec,
      AndroidBackgroundDownloadJobBuilder(JobInfo.Builder(
      spec.jobId,
      ComponentName(context, UserInitiatedDownloadJobService::class.java),
      )),
    )
    val scheduler = context.getSystemService(JobScheduler::class.java)
      .forNamespace(BackgroundDownloadScheduler.JOB_NAMESPACE)
    return scheduler.schedule(info) == JobScheduler.RESULT_SUCCESS
  }

  override fun startService(taskId: String, foreground: Boolean) {
    val intent = Intent(context, BackgroundDownloadForegroundService::class.java)
      .setAction(BackgroundDownloadForegroundService.ACTION_START)
      .putExtra(BackgroundDownloadScheduler.EXTRA_TASK_ID, taskId)
    try {
      if (foreground && Build.VERSION.SDK_INT >= 26) {
        startForegroundServiceApi26(intent)
      } else {
        context.startService(intent)
      }
    } catch (error: RuntimeException) {
      if (Build.VERSION.SDK_INT >= 31 && isForegroundStartNotAllowed(error)) {
        throw BackgroundDownloadPlatformStartNotAllowedException("Foreground service start rejected", error)
      }
      throw error
    }
  }

  @RequiresApi(26)
  private fun startForegroundServiceApi26(intent: Intent) {
    context.startForegroundService(intent)
  }

  @RequiresApi(31)
  private fun isForegroundStartNotAllowed(error: RuntimeException): Boolean =
    error is ForegroundServiceStartNotAllowedException

  override fun cancelUserInitiatedJob(jobId: Int) {
    if (Build.VERSION.SDK_INT >= 34) {
      context.getSystemService(JobScheduler::class.java)
        .forNamespace(BackgroundDownloadScheduler.JOB_NAMESPACE)
        .cancel(jobId)
    }
  }
}

@RequiresApi(34)
@SuppressLint("MissingPermission")
private class AndroidBackgroundDownloadJobBuilder(
  private val builder: JobInfo.Builder,
) : BackgroundDownloadJobBuilder<JobInfo> {
  override fun setTaskIdOnly(key: String, taskId: String) = apply {
    builder.setExtras(PersistableBundle().apply { putString(key, taskId) })
  }

  override fun setPersisted(value: Boolean) = apply { builder.setPersisted(value) }

  override fun requireInternetNetwork() = apply {
    builder.setRequiredNetwork(
      NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(),
    )
  }

  override fun setEstimatedDownloadBytes(bytes: Long) = apply {
    builder.setEstimatedNetworkBytes(bytes, 0L)
  }

  override fun setUserInitiated(value: Boolean) = apply { builder.setUserInitiated(value) }

  override fun build(): JobInfo = builder.build()
}
