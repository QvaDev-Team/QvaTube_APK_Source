package net.qvatube.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Mantiene vivas las descargas de archivos de Telegram (TDLib) cuando el
 * usuario sale de la app.
 *
 * La descarga la hace TDLib dentro del proceso; este servicio en primer
 * plano solo evita que Android congele o mate el proceso mientras tanto y
 * enseña el progreso en la barra de notificaciones. Mismo patrón que
 * [UpdateDownloadService].
 */
class TelegramDownloadService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildProgressNotification(
            this,
            intent?.getIntExtra(EXTRA_PERCENT, -1) ?: -1,
            intent?.getStringExtra(EXTRA_TITLE),
            intent?.getStringExtra(EXTRA_TEXT)
        )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(PROGRESS_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(PROGRESS_ID, notification)
            }
        } catch (_: Exception) {
            // Android puede negar el servicio: la descarga sigue mientras el
            // proceso viva, solo sin la garantía extra.
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int) = stopSelfCompat()

    override fun onTimeout(startId: Int, fgsType: Int) = stopSelfCompat()

    private fun stopSelfCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    companion object {
        private const val EXTRA_PERCENT = "percent"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val CHANNEL = "qvatube_telegram_downloads"
        private const val PROGRESS_ID = 7402
        private const val DONE_ID = 7403

        @Volatile
        private var running = false

        /** Arranca o actualiza el servicio con el progreso de las descargas. */
        fun progress(context: Context, percent: Int, title: String?, text: String?) {
            if (!running) {
                val intent = Intent(context, TelegramDownloadService::class.java)
                    .putExtra(EXTRA_PERCENT, percent)
                    .putExtra(EXTRA_TITLE, title)
                    .putExtra(EXTRA_TEXT, text)
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                    running = true
                } catch (_: Exception) {
                    running = false
                }
                return
            }
            if (!canNotify(context)) return
            try {
                NotificationManagerCompat.from(context)
                    .notify(PROGRESS_ID, buildProgressNotification(context, percent, title, text))
            } catch (_: SecurityException) {
            }
        }

        /** Para el servicio y quita la notificación de progreso. */
        fun stop(context: Context) {
            if (running) {
                running = false
                try {
                    context.stopService(Intent(context, TelegramDownloadService::class.java))
                } catch (_: Exception) {
                }
            }
            NotificationManagerCompat.from(context).cancel(PROGRESS_ID)
        }

        /** Aviso "Descarga lista" al terminar un archivo. */
        fun notifyDone(context: Context, title: String) {
            if (!canNotify(context)) return
            ensureChannel(context)
            val open = PendingIntent.getActivity(
                context,
                DONE_ID,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val notification = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_qvatube)
                .setColor(0xFFFF3D1A.toInt())
                .setContentTitle("Descarga lista")
                .setContentText("$title ya se puede ver sin conexión.")
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
            try {
                NotificationManagerCompat.from(context).notify(DONE_ID, notification)
            } catch (_: SecurityException) {
            }
        }

        private fun canNotify(context: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL,
                        "Descargas de Telegram",
                        NotificationManager.IMPORTANCE_LOW
                    ).apply {
                        description = "Progreso de los archivos del bot que se descargan en QvaTube"
                        setShowBadge(false)
                    }
                )
            }
        }

        private fun buildProgressNotification(
            context: Context,
            percent: Int,
            title: String?,
            text: String?
        ): Notification {
            ensureChannel(context)
            val open = PendingIntent.getActivity(
                context,
                PROGRESS_ID,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val indeterminate = percent !in 0..100
            return NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setColor(0xFFFF3D1A.toInt())
                .setContentTitle(if (title.isNullOrBlank()) "Descargando de Telegram" else title)
                .setContentText(
                    when {
                        !text.isNullOrBlank() && !indeterminate -> "$text · $percent %"
                        !text.isNullOrBlank() -> text
                        !indeterminate -> "$percent %"
                        else -> "Preparando…"
                    }
                )
                .setProgress(100, if (indeterminate) 0 else percent, indeterminate)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setContentIntent(open)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()
        }
    }
}
