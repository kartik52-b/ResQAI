package com.example.resq_ai

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground service that keeps ResQ AI monitoring alive in background.
 * Shows a persistent notification while monitoring is active.
 *
 * Two notification channels:
 * 1. Monitoring channel (LOW importance) — persistent service notification
 * 2. Emergency channel (HIGH importance) — alerts user when accident detected
 */
class ResQMonitoringService : Service() {

    companion object {
        const val CHANNEL_ID = "resq_monitoring_channel"
        const val EMERGENCY_CHANNEL_ID = "resq_emergency_channel"
        const val NOTIFICATION_ID = 1001
        const val EMERGENCY_NOTIFICATION_ID = 2001
        const val ACTION_START = "com.example.resq_ai.START_MONITORING"
        const val ACTION_STOP = "com.example.resq_ai.STOP_MONITORING"

        private var isRunning = false
        private var methodChannel: MethodChannel? = null

        fun setIsRunning(running: Boolean) { isRunning = running }
        fun getIsRunning() = isRunning
        fun setMethodChannel(channel: MethodChannel?) { methodChannel = channel }

        /** Dismiss emergency notification from any context (static). */
        fun dismissEmergencyNotificationStatic(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.cancel(EMERGENCY_NOTIFICATION_ID)
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                startForegroundService()
            }
            null -> {
                // Service restarted by system
                startForegroundService()
            }
        }
        return START_STICKY
    }

    private fun startForegroundService() {
        val notification = buildNotification("Monitoring sensors and location")

        // Android 14+ (SDK 34+) requires specifying foreground service type
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Service type must match manifest: location|microphone
            startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        acquireWakeLock()
        isRunning = true

        // Notify Flutter that the service started
        try {
            methodChannel?.invokeMethod("onServiceStarted", null)
        } catch (_: Exception) {}
    }

    /**
     * Show a high-priority emergency notification.
     * Used when an accident is detected while the app may be in background.
     * Opens the emergency screen when tapped.
     */
    fun showEmergencyNotification(title: String, body: String) {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            putExtra("open_emergency", true)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        val pendingIntent = PendingIntent.getActivity(
            this, EMERGENCY_NOTIFICATION_ID, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, EMERGENCY_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentIntent(pendingIntent)
            .setAutoCancel(false)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(pendingIntent, true)
            .build()

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(EMERGENCY_NOTIFICATION_ID, notification)

        // Also try to wake the device and bring the app to front
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            val screenOn = powerManager.isInteractive
            if (!screenOn) {
                // Screen is off — the full-screen intent should fire
                launchIntent?.let { startActivity(it) }
            }
        } catch (_: Exception) {}
    }

    fun dismissEmergencyNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.cancel(EMERGENCY_NOTIFICATION_ID)
    }

    private fun buildNotification(text: String): Notification {
        val pendingIntent = packageManager
            .getLaunchIntentForPackage(packageName)
            ?.let { PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )}

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("ResQ AI Protection Active")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            // Monitoring channel (persistent, low priority)
            val monitoringChannel = NotificationChannel(
                CHANNEL_ID,
                "ResQ AI Monitoring",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Persistent notification while ResQ AI is monitoring"
                setShowBadge(false)
            }
            manager.createNotificationChannel(monitoringChannel)

            // Emergency channel (high priority, shows over lock screen)
            val emergencyChannel = NotificationChannel(
                EMERGENCY_CHANNEL_ID,
                "ResQ AI Emergency Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Critical emergency alerts when accident is detected"
                setShowBadge(true)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setBypassDnd(true)
            }
            manager.createNotificationChannel(emergencyChannel)
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "resq_ai::monitoring_wakelock"
            ).apply {
                acquire(60 * 60 * 1000L) // 1 hour max, will be reacquired
            }
        }
    }

    override fun onDestroy() {
        isRunning = false
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
        try {
            methodChannel?.invokeMethod("onServiceStopped", null)
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
