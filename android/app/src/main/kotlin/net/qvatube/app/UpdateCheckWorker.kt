package net.qvatube.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

/**
 * Comprobación periódica de actualizaciones en segundo plano (aunque la app
 * esté cerrada). Descarga el `latest.json` que publica el CI y, si hay una
 * versión más nueva que la instalada, muestra una notificación una sola vez
 * por versión. Al tocarla se abre la app, que enseña su banner de siempre.
 */
class UpdateCheckWorker(context: Context, params: WorkerParameters) :
    Worker(context, params) {

    override fun doWork(): Result {
        val manifestUrl = inputData.getString(KEY_MANIFEST_URL) ?: return Result.success()
        return try {
            check(manifestUrl)
            Result.success()
        } catch (_: Exception) {
            // Sin red, GitHub caído, JSON inválido…: se reintenta en el
            // siguiente periodo, no hace falta forzar reintentos.
            Result.success()
        }
    }

    private fun check(manifestUrl: String) {
        val ctx = applicationContext
        val manifest = JSONObject(fetch("$manifestUrl?t=${System.currentTimeMillis()}"))
        val remoteCode = normalizeVersionCode(manifest.optLong("version_code", 0))
        if (remoteCode <= normalizeVersionCode(installedVersionCode(ctx))) return

        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getLong(KEY_NOTIFIED_CODE, 0) >= remoteCode) return

        val versionName = manifest.optString("version_name").ifBlank { remoteCode.toString() }
        val downloadBytes = applicablePatchSize(ctx, manifest) ?: manifest.optLong("size_bytes", 0)

        if (notify(ctx, versionName, downloadBytes)) {
            prefs.edit().putLong(KEY_NOTIFIED_CODE, remoteCode).apply()
        }
    }

    private fun fetch(url: String): String {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 15_000
        conn.readTimeout = 20_000
        conn.instanceFollowRedirects = true
        conn.setRequestProperty("Accept", "application/json")
        conn.setRequestProperty("Cache-Control", "no-cache")
        try {
            if (conn.responseCode !in 200..299) throw IllegalStateException("HTTP ${conn.responseCode}")
            return conn.inputStream.bufferedReader().use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }

    /** Tamaño del parche diferencial que sirve para el APK instalado, si hay. */
    private fun applicablePatchSize(ctx: Context, manifest: JSONObject): Long? {
        val patches = manifest.optJSONArray("patches") ?: return null
        if (patches.length() == 0) return null
        val installedSha = sha256(File(ctx.applicationInfo.sourceDir))
        for (i in 0 until patches.length()) {
            val p = patches.optJSONObject(i) ?: continue
            if (p.optString("from_sha256").equals(installedSha, ignoreCase = true)) {
                return p.optLong("size_bytes", 0).takeIf { it > 0 }
            }
        }
        return null
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun notify(ctx: Context, versionName: String, downloadBytes: Long): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ctx.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }

        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            nm.getNotificationChannel(CHANNEL_ID) == null
        ) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Actualizaciones",
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply { description = "Aviso cuando hay una nueva versión de QvaTube" }
            )
        }

        val intent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_OPEN_UPDATE, true)
        }
        val pending = PendingIntent.getActivity(
            ctx,
            NOTIFICATION_ID,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val sizeText = if (downloadBytes > 0) {
            " (solo %.1f MB)".format(downloadBytes / 1048576.0)
        } else {
            ""
        }
        val notification = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Nueva versión de QvaTube $versionName")
            .setContentText("Toca para actualizar$sizeText")
            .setContentIntent(pending)
            .apply {
                // Icono grande con el arte de la temporada que la app guardó
                // de /assets/favicon.png; el pequeño es siempre el del APK.
                val art = File(ctx.filesDir, "branding/favicon.png")
                if (art.isFile) {
                    android.graphics.BitmapFactory.decodeFile(art.path)?.let { setLargeIcon(it) }
                }
            }
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        return try {
            NotificationManagerCompat.from(ctx).notify(NOTIFICATION_ID, notification)
            true
        } catch (_: SecurityException) {
            false
        }
    }

    companion object {
        const val EXTRA_OPEN_UPDATE = "open_update"
        private const val KEY_MANIFEST_URL = "manifest_url"
        private const val KEY_NOTIFIED_CODE = "notified_version_code"
        private const val PREFS = "qvatube_update_check"
        private const val CHANNEL_ID = "qvatube_updates"
        private const val NOTIFICATION_ID = 7301
        private const val WORK_NAME = "qvatube_update_check"

        /** Programa (o actualiza) la comprobación cada 6 horas con red. */
        fun schedule(context: Context, manifestUrl: String) {
            val request = PeriodicWorkRequestBuilder<UpdateCheckWorker>(
                6, TimeUnit.HOURS,
                1, TimeUnit.HOURS
            )
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build()
                )
                .setInputData(workDataOf(KEY_MANIFEST_URL to manifestUrl))
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request
            )
        }

        /** Quita la notificación (p. ej. al abrir la app, que ya muestra el banner). */
        fun cancelNotification(context: Context) {
            NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
        }

        /**
         * Igual que `AppUpdateService.normalizeVersionCode` en Dart: con
         * `--split-per-abi` Flutter suma 1000 × ABI (arm64 → 2039 para la 39).
         */
        private fun normalizeVersionCode(code: Long): Long =
            if (code in 1000 until 5000) code % 1000 else code

        private fun installedVersionCode(ctx: Context): Long {
            val info = ctx.packageManager.getPackageInfo(ctx.packageName, 0)
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
        }
    }
}
