package com.raddflix.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Minimal foreground service for background audio playback.
 *
 * Why this exists:
 * Android 8+ will terminate a process that has been in the background for
 * ~1 minute with no foreground component. media_kit / libmpv runs its audio
 * pipeline on native threads, so audio CAN physically continue after the
 * Flutter Dart isolate is suspended — but the OS kills the whole process
 * regardless, stopping audio.
 *
 * Starting this service with startForeground() posts a persistent
 * FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK notification that:
 *   1. Prevents Android from killing the process.
 *   2. Shows the user that RaddFlix is playing (lock screen, notification shade).
 *   3. Tapping the notification brings the player back to the foreground.
 *
 * The service is started via the PIP method channel from player_screen.dart
 * when the user has Background Play enabled and the app moves to background.
 * It is stopped when the app returns to foreground or the player is closed.
 */
class PlaybackService : Service() {

    companion object {
        const val CHANNEL_ID      = "raddflix_playback"
        const val NOTIFICATION_ID = 1001
        const val EXTRA_TITLE     = "media_title"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Playing…"
        startForeground(NOTIFICATION_ID, buildNotification(title))
        // START_NOT_STICKY: if the OS kills this service, don't restart it.
        // The player is already dead at that point, so restarting is useless.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun buildNotification(title: String): Notification {
        // Tapping the notification restores the app to the player screen.
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                    PendingIntent.FLAG_IMMUTABLE else 0
        val pendingOpen = PendingIntent.getActivity(this, 0, openIntent, pendingFlags)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("RaddFlix")
            .setContentText(title)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingOpen)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "RaddFlix Background Playback",
                NotificationManager.IMPORTANCE_LOW   // silent — no sound, no vibration
            ).apply {
                description = "Shows while RaddFlix is playing audio in the background"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm?.createNotificationChannel(channel)
        }
    }
}
