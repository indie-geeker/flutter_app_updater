package com.indiegeeker.flutter_app_updater.background

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import com.indiegeeker.flutter_app_updater.R

internal class BackgroundDownloadNotificationRateGate(
  private val nowElapsedMs: () -> Long = SystemClock::elapsedRealtime,
) {
  private val lastPublished = mutableMapOf<String, Long>()

  @Synchronized
  fun shouldPublish(id: String, force: Boolean): Boolean {
    if (force) {
      lastPublished[id] = nowElapsedMs()
      return true
    }
    val now = nowElapsedMs()
    val last = lastPublished[id]
    if (last != null && now - last < MIN_UPDATE_INTERVAL_MS) return false
    lastPublished[id] = now
    return true
  }

  private companion object {
    const val MIN_UPDATE_INTERVAL_MS = 1_000L
  }
}

internal class BackgroundDownloadNotifications(
  private val context: Context,
  private val notificationManager: NotificationManager =
    context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager,
  private val rateGate: BackgroundDownloadNotificationRateGate = BackgroundDownloadNotificationRateGate(),
) {
  fun ensureChannel() {
    if (Build.VERSION.SDK_INT < 26) return
    createChannel()
  }

  @RequiresApi(26)
  private fun createChannel() {
    val channel = NotificationChannel(
      CHANNEL_ID,
      context.getString(R.string.flutter_app_updater_download_channel_name),
      NotificationManager.IMPORTANCE_LOW,
    ).apply {
      description = context.getString(R.string.flutter_app_updater_download_channel_description)
      enableVibration(false)
      setSound(null, null)
    }
    try {
      notificationManager.createNotificationChannel(channel)
    } catch (_: SecurityException) {
      // The host owns notification permission. A denial never changes task state.
    }
  }

  fun running(record: BackgroundDownloadRecord): Notification {
    val max = record.expectedSizeBytes.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    val progress = record.downloadedBytes.coerceAtMost(max.toLong()).toInt()
    return baseBuilder(record)
      .setContentTitle(context.getString(R.string.flutter_app_updater_download_running_title))
      .setContentText(context.getString(R.string.flutter_app_updater_download_running_text))
      .setOngoing(true)
      .setProgress(max, progress, false)
      .addAction(
        0,
        context.getString(R.string.flutter_app_updater_download_cancel),
        actionIntent(record.id, BackgroundDownloadActionReceiver.ACTION_CANCEL),
      )
      .build()
  }

  fun starting(taskId: String): Notification = baseBuilder(taskId)
    .setContentTitle(context.getString(R.string.flutter_app_updater_download_running_title))
    .setContentText(context.getString(R.string.flutter_app_updater_download_running_text))
    .setOngoing(true)
    .setProgress(0, 0, true)
    .addAction(
      0,
      context.getString(R.string.flutter_app_updater_download_cancel),
      actionIntent(taskId, BackgroundDownloadActionReceiver.ACTION_CANCEL),
    )
    .build()

  fun waiting(record: BackgroundDownloadRecord): Notification = baseBuilder(record)
    .setContentTitle(context.getString(R.string.flutter_app_updater_download_waiting_title))
    .setContentText(context.getString(R.string.flutter_app_updater_download_waiting_text))
    .setOngoing(false)
    .addAction(
      0,
      context.getString(R.string.flutter_app_updater_download_retry),
      actionIntent(record.id, BackgroundDownloadActionReceiver.ACTION_RETRY),
    )
    .addAction(
      0,
      context.getString(R.string.flutter_app_updater_download_cancel),
      actionIntent(record.id, BackgroundDownloadActionReceiver.ACTION_CANCEL),
    )
    .build()

  fun completed(record: BackgroundDownloadRecord): Notification = baseBuilder(record)
    .setContentTitle(context.getString(R.string.flutter_app_updater_download_completed_title))
    .setContentText(context.getString(R.string.flutter_app_updater_download_completed_text))
    .setOngoing(false)
    .setAutoCancel(true)
    .setContentIntent(openHostAppIntent())
    .build()

  fun failed(record: BackgroundDownloadRecord): Notification = baseBuilder(record)
    .setContentTitle(context.getString(R.string.flutter_app_updater_download_failed_title))
    .setContentText(context.getString(R.string.flutter_app_updater_download_failed_text))
    .setOngoing(false)
    .setAutoCancel(true)
    .build()

  fun publish(record: BackgroundDownloadRecord, notification: Notification, force: Boolean = false) {
    if (!rateGate.shouldPublish(record.id, force)) return
    try {
      notificationManager.notify(notificationId(record), notification)
    } catch (_: SecurityException) {
      // Notification visibility must not control download correctness.
    }
  }

  fun cancel(record: BackgroundDownloadRecord) {
    cancelId(notificationId(record))
  }

  fun cancelId(notificationId: Int) {
    try {
      notificationManager.cancel(notificationId)
    } catch (_: SecurityException) {
      // A denied notification permission is not a task failure.
    }
  }

  private fun baseBuilder(record: BackgroundDownloadRecord): NotificationCompat.Builder {
    return baseBuilder(record.id)
  }

  private fun baseBuilder(taskId: String): NotificationCompat.Builder {
    ensureChannel()
    return NotificationCompat.Builder(context, CHANNEL_ID)
      .setSmallIcon(R.drawable.flutter_app_updater_ic_download)
      .setOnlyAlertOnce(true)
      .setSilent(true)
      .setCategory(NotificationCompat.CATEGORY_PROGRESS)
      .setPriority(NotificationCompat.PRIORITY_LOW)
      .setContentIntent(openHostAppIntent())
  }

  private fun actionIntent(taskId: String, action: String): PendingIntent {
    val intent = Intent(context, BackgroundDownloadActionReceiver::class.java)
      .setAction(action)
      .putExtra(BackgroundDownloadScheduler.EXTRA_TASK_ID, taskId)
    return PendingIntent.getBroadcast(
      context,
      31 * action.hashCode() + taskId.hashCode(),
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }

  private fun openHostAppIntent(): PendingIntent? {
    val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    return PendingIntent.getActivity(
      context,
      OPEN_APP_REQUEST_CODE,
      launch,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }

  internal companion object {
    const val CHANNEL_ID = "flutter_app_updater_downloads"
    private const val OPEN_APP_REQUEST_CODE = 0x465543

    fun notificationId(record: BackgroundDownloadRecord): Int = record.notificationId
  }
}
