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
 * Mantiene viva la descarga de una actualización cuando el usuario sale de
 * la app.
 *
 * La descarga (y el parche diferencial) la hace Dart; este servicio en primer
 * plano solo evita que Android congele o mate el proceso mientras tanto y
 * enseña el progreso en la barra de notificaciones. Al terminar, si la app no
 * está delante, se publica el aviso "Actualización lista": al tocarlo se abre
 * la app y lanza el instalador ([EXTRA_INSTALL_PATH]).
 */
class UpdateDownloadService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelfCompat()
            return START_NOT_STICKY
        }
        val notification = buildProgressNotification(
            this,
            intent?.getIntExtra(EXTRA_PERCENT, -1) ?: -1,
            intent?.getStringExtra(EXTRA_TEXT)
        )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    PROGRESS_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else {
                startForeground(PROGRESS_ID, notification)
            }
        } catch (_: Exception) {
            // Android puede negar el servicio (límite diario de dataSync,
            // app en segundo plano…): la descarga sigue mientras el proceso
            // viva, solo sin la garantía extra.
            stopSelf()
        }
        // Si el sistema mata el proceso, la descarga de Dart murió con él:
        // no tiene sentido recrear el servicio vacío.
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int) {
        stopSelfCompat()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        // Android 15+: se acabó el tiempo diario permitido para dataSync.
        stopSelfCompat()
    }

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
        const val EXTRA_INSTALL_PATH = "install_update_path"
        private const val ACTION_STOP = "net.qvatube.app.UPDATE_DOWNLOAD_STOP"
        private const val EXTRA_PERCENT = "percent"
        private const val EXTRA_TEXT = "text"
        private const val CHANNEL_PROGRESS = "qvatube_update_download"
        private const val CHANNEL_READY = "qvatube_updates"
        private const val PROGRESS_ID = 7302
        private const val READY_ID = 7303

        @Volatile
        private var running = false

        /** Arranca el servicio en primer plano con la notificación de progreso. */
        fun start(context: Context, text: String?) {
            ensureChannels(context)
            NotificationManagerCompat.from(context).cancel(READY_ID)
            val intent = Intent(context, UpdateDownloadService::class.java)
                .putExtra(EXTRA_PERCENT, -1)
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
        }

        /** Actualiza el porcentaje (`-1` = indeterminado) y el texto. */
        fun progress(context: Context, percent: Int, text: String?) {
            if (!running || !canNotify(context)) return
            try {
                NotificationManagerCompat.from(context)
                    .notify(PROGRESS_ID, buildProgressNotification(context, percent, text))
            } catch (_: SecurityException) {
            }
        }

        /** Para el servicio y quita la notificación de progreso. */
        fun stop(context: Context) {
            if (running) {
                running = false
                // stopService también quita el servicio del primer plano y
                // no choca con las restricciones de arrancar servicios desde
                // segundo plano (a diferencia de startService).
                try {
                    context.stopService(Intent(context, UpdateDownloadService::class.java))
                } catch (_: Exception) {
                }
            }
            NotificationManagerCompat.from(context).cancel(PROGRESS_ID)
        }

        /** Aviso "Actualización lista": al tocarlo se abre el instalador. */
        fun notifyReady(context: Context, path: String, versionName: String?) {
            stop(context)
            if (!canNotify(context)) return
            ensureChannels(context)
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_INSTALL_PATH, path)
            }
            val pending = PendingIntent.getActivity(
                context,
                READY_ID,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val title = if (versionName.isNullOrBlank()) {
                "Actualización de QvaTube lista"
            } else {
                "QvaTube $versionName está lista"
            }
            val notification = NotificationCompat.Builder(context, CHANNEL_READY)
                .setSmallIcon(R.drawable.ic_stat_qvatube)
                .setColor(0xFFFF3D1A.toInt())
                .setContentTitle(title)
                .setContentText("La descarga terminó. Toca para instalar.")
                .setContentIntent(pending)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build()
            try {
                NotificationManagerCompat.from(context).notify(READY_ID, notification)
            } catch (_: SecurityException) {
            }
        }

        /** Aviso de que la descarga falló con la app en segundo plano. */
        fun notifyFailed(context: Context) {
            stop(context)
            if (!canNotify(context)) return
            ensureChannels(context)
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(UpdateCheckWorker.EXTRA_OPEN_UPDATE, true)
            }
            val pending = PendingIntent.getActivity(
                context,
                READY_ID,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val notification = NotificationCompat.Builder(context, CHANNEL_READY)
                .setSmallIcon(R.drawable.ic_stat_qvatube)
                .setColor(0xFFFF3D1A.toInt())
                .setContentTitle("No se pudo descargar la actualización")
                .setContentText("Revisa tu conexión y toca para intentarlo de nuevo.")
                .setContentIntent(pending)
                .setAutoCancel(true)
                .build()
            try {
                NotificationManagerCompat.from(context).notify(READY_ID, notification)
            } catch (_: SecurityException) {
            }
        }

        fun cancelReady(context: Context) {
            NotificationManagerCompat.from(context).cancel(READY_ID)
        }

        private fun canNotify(context: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED

        private fun ensureChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_PROGRESS) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_PROGRESS,
                        "Descarga de actualizaciones",
                        NotificationManager.IMPORTANCE_LOW
                    ).apply {
                        description = "Progreso de la actualización mientras se descarga"
                        setShowBadge(false)
                    }
                )
            }
            if (nm.getNotificationChannel(CHANNEL_READY) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL_READY,
                        "Actualizaciones",
                        NotificationManager.IMPORTANCE_DEFAULT
                    ).apply { description = "Aviso cuando hay una nueva versión de QvaTube" }
                )
            }
        }

        private fun buildProgressNotification(
            context: Context,
            percent: Int,
            text: String?
        ): Notification {
            ensureChannels(context)
            val open = PendingIntent.getActivity(
                context,
                PROGRESS_ID,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val indeterminate = percent !in 0..100
            return NotificationCompat.Builder(context, CHANNEL_PROGRESS)
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setColor(0xFFFF3D1A.toInt())
                .setContentTitle("Descargando actualización de QvaTube")
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
