package com.rochapps.flashbackcam

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service that displays a persistent notification when the video buffer is active.
 * This is required by Google Play policy for apps that use the camera continuously.
 * 
 * The notification:
 * - Shows in the status bar and notification shade
 * - Cannot be dismissed while buffer is running
 * - Informs users that the camera is actively buffering
 * - Tapping opens the app
 */
class BufferForegroundService : Service() {
    
    companion object {
        private const val TAG = "BufferForegroundService"
        const val CHANNEL_ID = "flashback_buffer_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "START_BUFFER_SERVICE"
        const val ACTION_STOP = "STOP_BUFFER_SERVICE"
        const val EXTRA_BUFFER_SECONDS = "buffer_seconds"
        
        @Volatile
        private var instance: BufferForegroundService? = null
        
        /**
         * Check if the foreground service is currently running
         */
        fun isRunning(): Boolean = instance != null
        
        /**
         * Start the foreground service with buffer notification
         */
        fun start(context: Context, bufferSeconds: Int) {
            try {
                val intent = Intent(context, BufferForegroundService::class.java).apply {
                    action = ACTION_START
                    putExtra(EXTRA_BUFFER_SECONDS, bufferSeconds)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                Log.d(TAG, "Started foreground service with buffer: ${bufferSeconds}s")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start foreground service", e)
            }
        }
        
        /**
         * Stop the foreground service and remove notification
         */
        fun stop(context: Context) {
            try {
                val intent = Intent(context, BufferForegroundService::class.java).apply {
                    action = ACTION_STOP
                }
                context.startService(intent)
                Log.d(TAG, "Stopping foreground service")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to stop foreground service", e)
            }
        }
        
        /**
         * Update the notification with new buffer duration
         */
        fun updateNotification(context: Context, bufferSeconds: Int) {
            instance?.updateBufferNotification(bufferSeconds)
        }
    }
    
    private var bufferSeconds: Int = 5
    
    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        Log.d(TAG, "BufferForegroundService created")
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                bufferSeconds = intent.getIntExtra(EXTRA_BUFFER_SECONDS, 5)
                startForegroundWithNotification()
            }
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }
    
    override fun onDestroy() {
        super.onDestroy()
        instance = null
        Log.d(TAG, "BufferForegroundService destroyed")
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    /**
     * Create notification channel for Android 8.0+
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Buffer Active",
                NotificationManager.IMPORTANCE_LOW  // Low = no sound, but visible
            ).apply {
                description = "Shows when the video buffer is actively recording"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
            }
            
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
            Log.d(TAG, "Notification channel created")
        }
    }
    
    /**
     * Start the service in foreground mode with a persistent notification
     */
    private fun startForegroundWithNotification() {
        val notification = buildNotification(bufferSeconds)
        
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            Log.d(TAG, "Foreground service started with notification")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start foreground", e)
        }
    }
    
    /**
     * Build the notification that shows buffer is active
     */
    private fun buildNotification(seconds: Int): Notification {
        // Intent to open the app when notification is tapped
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        // Build notification - setOngoing(true) makes it non-dismissible for foreground services
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Buffer Active")
            .setContentText("Recording last ${seconds}s • Tap record to save")
            .setSmallIcon(R.drawable.ic_buffer_notification)
            .setOngoing(true)  // CRITICAL: Cannot be swiped away
            .setAutoCancel(false)  // Don't dismiss when tapped
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .setColor(0xFF2196F3.toInt())  // Material blue
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
        
        // Explicitly set flags to ensure non-dismissible behavior
        notification.flags = notification.flags or 
            Notification.FLAG_ONGOING_EVENT or 
            Notification.FLAG_NO_CLEAR or
            Notification.FLAG_FOREGROUND_SERVICE
        
        return notification
    }
    
    /**
     * Update notification with new buffer duration
     */
    fun updateBufferNotification(seconds: Int) {
        bufferSeconds = seconds
        val notification = buildNotification(seconds)
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)
    }
}
