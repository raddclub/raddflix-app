package com.raddflix.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat as MediaNotificationCompat

/**
 * Foreground service for background audio playback with a MediaStyle notification.
 *
 * Shows play/pause + seek transport controls in the notification shade, lock screen,
 * and any Bluetooth peripherals.  A MediaSessionCompat is set up so Android Auto,
 * headset hardware buttons, and Google Assistant can control playback.
 *
 * Features:
 *   • Three transport actions in compact view: −10 s | ▶︎/⏸ | +30 s
 *   • Determinate progress bar that reflects the current position inside the episode
 *   • On Android 13+ the progress bar is also swipe-seekable (ACTION_SEEK_TO via MediaSession)
 *
 * Life-cycle:
 *   • Started / refreshed via "startBgPlayback" or "updateBgNotification" on the pip channel.
 *   • Stopped via "stopBgPlayback" when the app returns to foreground or player closes.
 *
 * Button taps and seek gestures are broadcast locally and caught by MainActivity's
 * BroadcastReceiver, which forwards them to Flutter as "onNotificationAction".
 */
class PlaybackService : Service() {

    companion object {
        const val CHANNEL_ID      = "raddflix_playback"
        const val NOTIFICATION_ID = 1001

        // Intent extras
        const val EXTRA_TITLE      = "media_title"
        const val EXTRA_IS_PLAYING = "is_playing"
        const val EXTRA_POSITION   = "position_ms"
        const val EXTRA_DURATION   = "duration_ms"

        // Local broadcasts caught by MainActivity.notifReceiver
        const val ACTION_PLAY_PAUSE = "com.raddflix.app.PLAY_PAUSE"
        const val ACTION_SEEK_BACK  = "com.raddflix.app.SEEK_BACK"
        const val ACTION_SEEK_FWD   = "com.raddflix.app.SEEK_FWD"
        const val ACTION_SEEK_TO    = "com.raddflix.app.SEEK_TO"
        const val EXTRA_SEEK_TO_MS  = "seek_to_ms"

        // Resolution of the progress bar (1 000 = 0.1 % granularity)
        private const val PROGRESS_MAX = 1000
    }

    private var mediaSession : MediaSessionCompat? = null
    private var currentTitle  = "Playing…"
    private var isPlaying     = true
    private var positionMs    = 0L
    private var durationMs    = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        setupMediaSession()
        startForeground(NOTIFICATION_ID, buildNotification())
    }

    private fun setupMediaSession() {
        mediaSession = MediaSessionCompat(this, "RaddFlixSession").apply {
            setFlags(MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS)
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onPlay()             { broadcast(ACTION_PLAY_PAUSE) }
                override fun onPause()            { broadcast(ACTION_PLAY_PAUSE) }
                override fun onSkipToPrevious()   { broadcast(ACTION_SEEK_BACK) }
                override fun onSkipToNext()       { broadcast(ACTION_SEEK_FWD) }
                // Android 13+ swipe-to-seek on the notification progress bar
                override fun onSeekTo(pos: Long)  {
                    sendBroadcast(
                        Intent(ACTION_SEEK_TO).apply {
                            setPackage(packageName)
                            putExtra(EXTRA_SEEK_TO_MS, pos)
                        }
                    )
                }
            })
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.also {
            if (it.hasExtra(EXTRA_TITLE))      currentTitle = it.getStringExtra(EXTRA_TITLE)      ?: "Playing…"
            if (it.hasExtra(EXTRA_IS_PLAYING)) isPlaying    = it.getBooleanExtra(EXTRA_IS_PLAYING, true)
            if (it.hasExtra(EXTRA_POSITION))   positionMs   = it.getLongExtra(EXTRA_POSITION, 0L)
            if (it.hasExtra(EXTRA_DURATION))   durationMs   = it.getLongExtra(EXTRA_DURATION, 0L)
        }
        updateMediaSession()
        getSystemService(NotificationManager::class.java)
            ?.notify(NOTIFICATION_ID, buildNotification())
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        mediaSession?.apply { isActive = false; release() }
        mediaSession = null
        super.onDestroy()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    // ─── Media session ────────────────────────────────────────────────────────

    private fun updateMediaSession() {
        val stateVal = if (isPlaying) PlaybackStateCompat.STATE_PLAYING
                       else           PlaybackStateCompat.STATE_PAUSED
        mediaSession?.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(
                    PlaybackStateCompat.ACTION_PLAY_PAUSE       or
                    PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                    PlaybackStateCompat.ACTION_SKIP_TO_NEXT     or
                    PlaybackStateCompat.ACTION_SEEK_TO
                )
                .setState(stateVal, positionMs, if (isPlaying) 1f else 0f)
                .build()
        )
        mediaSession?.setMetadata(
            MediaMetadataCompat.Builder()
                .putString(MediaMetadataCompat.METADATA_KEY_TITLE,  currentTitle)
                .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, "RaddFlix")
                .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
                .build()
        )
    }

    // ─── Notification ─────────────────────────────────────────────────────────

    private fun buildNotification(): Notification {
        val openPending = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            },
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )

        val seekBackPending  = broadcastPending(ACTION_SEEK_BACK,  10)
        val playPausePending = broadcastPending(ACTION_PLAY_PAUSE, 11)
        val seekFwdPending   = broadcastPending(ACTION_SEEK_FWD,   12)

        val (playPauseIcon, playPauseLabel) = if (isPlaying)
            android.R.drawable.ic_media_pause to "Pause"
        else
            android.R.drawable.ic_media_play  to "Play"

        // Determinate progress — indeterminate when duration is unknown
        val hasDuration  = durationMs > 0
        val progressVal  = if (hasDuration)
            ((positionMs.toFloat() / durationMs) * PROGRESS_MAX).toInt().coerceIn(0, PROGRESS_MAX)
        else 0

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(currentTitle)
            .setContentText(if (isPlaying) "Playing on RaddFlix" else "Paused · RaddFlix")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(openPending)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            // Progress bar — determinate when duration is known, indeterminate otherwise
            .setProgress(PROGRESS_MAX, progressVal, !hasDuration)
            // Three transport actions shown in compact view
            .addAction(android.R.drawable.ic_media_rew,  "−10s",         seekBackPending)
            .addAction(playPauseIcon,                     playPauseLabel, playPausePending)
            .addAction(android.R.drawable.ic_media_ff,   "+30s",         seekFwdPending)
            .setStyle(
                MediaNotificationCompat.MediaStyle()
                    .setMediaSession(mediaSession?.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )
            .build()
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private fun broadcastPending(action: String, requestCode: Int): PendingIntent =
        PendingIntent.getBroadcast(
            this, requestCode,
            Intent(action).apply { setPackage(packageName) },
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        )

    private fun broadcast(action: String) =
        sendBroadcast(Intent(action).apply { setPackage(packageName) })

    private fun immutableFlag() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "RaddFlix Background Playback",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows while RaddFlix is playing audio in the background"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }
}
