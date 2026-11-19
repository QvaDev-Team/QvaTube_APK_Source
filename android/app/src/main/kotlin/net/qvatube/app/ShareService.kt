package net.qvatube.app

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
import androidx.core.app.NotificationCompat

/**
 * "Compartir por Wi-Fi": notificación fija mientras el teléfono comparte.
 *
 * El punto de acceso local de Android no aparece en el panel rápido, así
 * que esta notificación indica que la red está activa, abre la app al
 * tocarla y trae "Dejar de compartir". Como servicio en primer plano evita
 * además que Android cierre la app (y con ella la red y el servidor) si el
 * usuario sale de QvaTube mientras el otro recibe.
 */
class ShareService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = build(
            this,
            intent?.getStringExtra(EXTRA_NETWORK),
            intent?.getStringExtra(EXTRA_TEXT)
        )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (_: Exception) {
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int) = stopSelf()

    override fun onTimeout(startId: Int, fgsType: Int) = stopSelf()

    companion object {
        const val ACTION_STOP_SHARE = "net.qvatube.app.SHARE_STOP"
        private const val EXTRA_NETWORK = "network"
        private const val EXTRA_TEXT = "text"
        // Importancia normal (sin sonido): con "baja", XOS y otras capas la
        // esconden en la fila de silenciosas y no se ve que se está compartiendo.
        private const val CHANNEL = "qvatube_wifi_share_v2"
        private const val NOTIFICATION_ID = 7410

        fun start(context: Context, network: String?, text: String?) {
            val intent = Intent(context, ShareService::class.java)
                .putExtra(EXTRA_NETWORK, network)
                .putExtra(EXTRA_TEXT, text)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Exception) {
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, ShareService::class.java))
            } catch (_: Exception) {
            }
        }

        private fun build(context: Context, network: String?, text: String?): Notification {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (nm.getNotificationChannel(CHANNEL) == null) {
                    nm.createNotificationChannel(
                        NotificationChannel(CHANNEL, "Compartir por Wi-Fi", NotificationManager.IMPORTANCE_DEFAULT).apply {
                            setSound(null, null)
                            enableVibration(false)
                            description = "Aviso mientras compartes contenido con otro teléfono"
                            setShowBadge(false)
                        }
                    )
                }
            }
            val open = PendingIntent.getActivity(
                context,
                NOTIFICATION_ID,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val stop = PendingIntent.getBroadcast(
                context,
                NOTIFICATION_ID + 1,
                Intent(ACTION_STOP_SHARE).setPackage(context.packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val title = if (network.isNullOrBlank()) {
                "Compartiendo por Wi-Fi"
            } else {
                "Compartiendo por Wi-Fi · Red $network"
            }
            return NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_qvatube)
                .setColor(0xFFFF3D1A.toInt())
                .setContentTitle(title)
                .setContentText(if (text.isNullOrBlank()) "Toca para volver a QvaTube" else text)
                .setContentIntent(open)
                .addAction(0, "Dejar de compartir", stop)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .build()
        }
    }
}
