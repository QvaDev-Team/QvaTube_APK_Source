package net.qvatube.app

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.graphics.Color
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.View
import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File

/**
 * Canal nativo (`qvatube/device`) para:
 *  - elegir una imagen de la galería y copiarla a la caché de la app;
 *  - abrir enlaces externos (bot de Telegram, comunidad de WhatsApp);
 *  - consultar la versión instalada y la de un APK descargado;
 *  - instalar una actualización (guardando el APK en `filesDir/updates` y
 *    reanudando automáticamente el instalador tras habilitar "Fuentes desconocidas");
 *  - controles multimedia en la barra de notificaciones (`MediaSession` +
 *    `MediaStyle`) para continuar o controlar la reproducción en segundo plano;
 *  - reproducir señales embebidas (TV y Radio en vivo) mediante WebView nativo.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "qvatube/device"
    private val pickImageRequestCode = 4321
    private val unknownSourcesRequestCode = 4322
    private val notificationPermissionRequestCode = 4323

    private var methodChannel: MethodChannel? = null
    private val pdfExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()
    private var pendingResult: MethodChannel.Result? = null

    // Estado para reanudar automáticamente la instalación del APK tras conceder permisos.
    private var pendingInstallFile: File? = null
    private var pendingInstallResult: MethodChannel.Result? = null

    // Estado de la notificación y sesión multimedia en segundo plano.
    private var mediaSession: MediaSession? = null
    private var mediaReceiverRegistered = false
    private val mediaNotificationId = 9801
    private val mediaChannelId = "qvatube_media_playback"

    private val actionPlayPause = "net.qvatube.app.MEDIA_PLAY_PAUSE"
    private val actionNext = "net.qvatube.app.MEDIA_NEXT"
    private val actionPrev = "net.qvatube.app.MEDIA_PREV"
    private val actionStop = "net.qvatube.app.MEDIA_STOP"

    private val mediaActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            val cmd = when (action) {
                actionPlayPause -> "playPause"
                actionNext -> "next"
                actionPrev -> "previous"
                actionStop -> "stop"
                else -> return
            }
            methodChannel?.invokeMethod("onMediaAction", mapOf("action" to cmd))
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerMediaReceiver()
        ensureGeneralChannel()
    }

    /** Canal de las notificaciones push (avisos de QvaTube). */
    private fun ensureGeneralChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel("qvatube_general") != null) return
        nm.createNotificationChannel(
            NotificationChannel(
                "qvatube_general",
                "Avisos de QvaTube",
                NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "Notificaciones de tu cuenta: estrenos, pagos, planes y más" }
        )
    }

    /**
     * Activa el icono del launcher de la temporada ([season] de
     * `GET /api/season`; `null` o desconocida = normal) con los
     * `<activity-alias>` del manifiesto. Devuelve `true` si cambió algo.
     */
    private fun applyLauncherIcon(season: String?): Boolean {
        val target = if (season != null && season in launcherAliases) season else "default"
        val targetComponent = ComponentName(this, "$packageName.icon.$target")
        val current = packageManager.getComponentEnabledSetting(targetComponent)
        val enabled = current == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
            (current == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && target == "default")
        val othersOff = launcherAliases.filter { it != target }.all { id ->
            val state = packageManager.getComponentEnabledSetting(
                ComponentName(this, "$packageName.icon.$id")
            )
            state == PackageManager.COMPONENT_ENABLED_STATE_DISABLED ||
                (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && id != "default")
        }
        if (enabled && othersOff) return false
        // Primero el nuevo (para no quedar nunca sin icono) y luego los demás.
        packageManager.setComponentEnabledSetting(
            targetComponent,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP
        )
        launcherAliases.filter { it != target }.forEach { id ->
            packageManager.setComponentEnabledSetting(
                ComponentName(this, "$packageName.icon.$id"),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
        }
        return true
    }

    private val launcherAliases = listOf("default", "halloween", "navidad", "sanvalentin")

    /** Salida de la pantalla completa de un video web (TV embebida), si está activa. */
    var exitWebFullscreen: (() -> Unit)? = null

    // "Atrás" en pantalla completa solo sale de ella (no cierra el canal).
    @Deprecated("FlutterActivity aún enruta el botón atrás por aquí")
    override fun onBackPressed() {
        val exit = exitWebFullscreen
        if (exit != null) {
            exit()
            return
        }
        @Suppress("DEPRECATION")
        super.onBackPressed()
    }

    // App ya abierta y el usuario toca la notificación de actualización:
    // Flutter vuelve a comprobar para enseñar el banner.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra(UpdateCheckWorker.EXTRA_OPEN_UPDATE, false)) {
            UpdateCheckWorker.cancelNotification(this)
            methodChannel?.invokeMethod("onUpdateNotificationTap", null)
        }
    }

    override fun onDestroy() {
        pdfExecutor.execute { PdfPages.close() }
        clearMediaNotification()
        unregisterMediaReceiver()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory("qvatube/webview", EmbeddedWebViewFactory(this))

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickImage" -> pickImage(result)
                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.error("bad_args", "URL vacía", null)
                    } else {
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("open_url", e.message, null)
                        }
                    }
                }
                "getInstalledVersion" -> {
                    try {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            info.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            info.versionCode.toLong()
                        }
                        result.success(
                            mapOf(
                                "versionCode" to code,
                                "versionName" to (info.versionName ?: ""),
                                "lastUpdateTime" to info.lastUpdateTime
                            )
                        )
                    } catch (e: Exception) {
                        result.error("version", e.message, null)
                    }
                }
                "getApkVersion" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("bad_args", "Ruta vacía", null)
                    } else {
                        try {
                            result.success(readApkVersion(File(path)))
                        } catch (e: Exception) {
                            result.error("version", e.message, null)
                        }
                    }
                }
                // APK instalado (base.apk): punto de partida de los parches
                // diferenciales. Se puede leer sin permisos especiales.
                "getInstalledApkPath" -> result.success(applicationInfo.sourceDir)
                "applyLauncherIcon" -> {
                    try {
                        result.success(applyLauncherIcon(call.argument<String>("season")))
                    } catch (e: Exception) {
                        result.error("launcher_icon", e.message, null)
                    }
                }
                "shareText" -> {
                    val text = call.argument<String>("text")
                    if (text.isNullOrBlank()) {
                        result.success(false)
                    } else {
                        try {
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, text)
                            }
                            startActivity(Intent.createChooser(send, "Compartir"))
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                }
                // Lector de PDF: Android ya trae PdfRenderer, sin librerías extra.
                "pdfOpen" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("bad_args", "Ruta vacía", null)
                    } else {
                        pdfExecutor.execute {
                            try {
                                val sizes = PdfPages.open(path)
                                runOnUiThread { result.success(sizes) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("pdf", e.message, null) }
                            }
                        }
                    }
                }
                "pdfRenderPage" -> {
                    val index = call.argument<Int>("index") ?: 0
                    val width = call.argument<Int>("width") ?: 1080
                    pdfExecutor.execute {
                        try {
                            val png = PdfPages.render(index, width)
                            runOnUiThread { result.success(png) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("pdf", e.message, null) }
                        }
                    }
                }
                "pdfClose" -> {
                    pdfExecutor.execute { PdfPages.close() }
                    result.success(true)
                }
                "scheduleUpdateCheck" -> {
                    val url = call.argument<String>("manifestUrl")
                    if (url.isNullOrBlank()) {
                        result.error("bad_args", "URL vacía", null)
                    } else {
                        UpdateCheckWorker.schedule(applicationContext, url)
                        // Al abrir la app el banner ya avisa: fuera la notificación.
                        UpdateCheckWorker.cancelNotification(this)
                        requestNotificationPermissionOnce()
                        result.success(true)
                    }
                }
                "cacheDirectory" -> result.success(filesDir.absolutePath)
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("bad_args", "Ruta vacía", null)
                    } else {
                        installApk(File(path), result)
                    }
                }
                "updateMediaNotification" -> {
                    val title = call.argument<String>("title") ?: "QvaTube"
                    val subtitle = call.argument<String>("subtitle") ?: ""
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    val hasNext = call.argument<Boolean>("hasNext") ?: false
                    val hasPrevious = call.argument<Boolean>("hasPrevious") ?: false
                    val positionMs = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                    val durationMs = (call.argument<Number>("durationMs"))?.toLong() ?: 0L
                    updateMediaNotification(
                        title = title,
                        subtitle = subtitle,
                        isPlaying = isPlaying,
                        hasNext = hasNext,
                        hasPrevious = hasPrevious,
                        positionMs = positionMs,
                        durationMs = durationMs
                    )
                    result.success(true)
                }
                "clearMediaNotification" -> {
                    clearMediaNotification()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Lee el versionCode / versionName de un APK en disco. */
    private fun readApkVersion(file: File): Map<String, Any> {
        val pm = packageManager
        val info = pm.getPackageArchiveInfo(file.absolutePath, 0)
            ?: throw IllegalStateException("El archivo no es un APK válido")
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return mapOf(
            "versionCode" to code,
            "versionName" to (info.versionName ?: "")
        )
    }

    /**
     * Abre el instalador del sistema para el APK descargado.
     *
     * Si el usuario todavía no ha autorizado a esta app a instalar paquetes,
     * guarda el archivo e inicia la pantalla de Ajustes con `startActivityForResult`.
     * En cuanto el usuario activa "Permitir desde esta fuente" y regresa,
     * se lanza automáticamente el instalador sin pedir descargar ni tocar de nuevo.
     */
    private fun installApk(file: File, result: MethodChannel.Result) {
        if (!file.exists()) {
            result.error("missing_file", "No se encontró el APK descargado", null)
            return
        }
        try {
            // Asegurar que el archivo resida en filesDir/updates para que el sistema
            // nunca lo limpie mientras el usuario está en Ajustes.
            val persistentFile = ensurePersistentUpdateFile(file)

            val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                packageManager.canRequestPackageInstalls()
            } else {
                true
            }
            if (!canInstall) {
                pendingInstallFile = persistentFile
                pendingInstallResult = result
                val settings = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
                @Suppress("DEPRECATION")
                startActivityForResult(settings, unknownSourcesRequestCode)
                return
            }

            launchSystemPackageInstaller(persistentFile)
            result.success(true)
        } catch (e: Exception) {
            result.error("install", e.message, null)
        }
    }

    private fun ensurePersistentUpdateFile(source: File): File {
        val updatesDir = File(filesDir, "updates")
        if (!updatesDir.exists()) {
            updatesDir.mkdirs()
        }
        val dest = File(updatesDir, source.name)
        if (source.absolutePath != dest.absolutePath) {
            source.copyTo(dest, overwrite = true)
        }
        return dest
    }

    private fun launchSystemPackageInstaller(file: File) {
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    override fun onResume() {
        super.onResume()
        checkPendingApkInstall()
    }

    private fun checkPendingApkInstall() {
        val file = pendingInstallFile ?: return
        val res = pendingInstallResult
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && packageManager.canRequestPackageInstalls()) {
            pendingInstallFile = null
            pendingInstallResult = null
            if (file.exists()) {
                try {
                    launchSystemPackageInstaller(file)
                    res?.success(true)
                } catch (e: Exception) {
                    res?.error("install", e.message, null)
                }
            } else {
                res?.error("missing_file", "No se encontró el APK descargado", null)
            }
        }
    }

    private fun registerMediaReceiver() {
        if (mediaReceiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(actionPlayPause)
            addAction(actionNext)
            addAction(actionPrev)
            addAction(actionStop)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(mediaActionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(mediaActionReceiver, filter)
        }
        mediaReceiverRegistered = true
    }

    private fun unregisterMediaReceiver() {
        if (!mediaReceiverRegistered) return
        try {
            unregisterReceiver(mediaActionReceiver)
        } catch (_: Exception) {
        }
        mediaReceiverRegistered = false
    }

    /**
     * Android 13+: pide permiso de notificaciones la primera vez (para el
     * aviso de actualizaciones). Si lo deniega no se vuelve a insistir aquí.
     */
    private fun requestNotificationPermissionOnce() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) return
        val prefs = getSharedPreferences("qvatube_update_check", Context.MODE_PRIVATE)
        if (prefs.getBoolean("asked_notification_permission", false)) return
        prefs.edit().putBoolean("asked_notification_permission", true).apply()
        requestPermissions(
            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode
        )
    }

    private fun ensureMediaChannel(nm: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val existing = nm.getNotificationChannel(mediaChannelId)
            if (existing == null) {
                val channel = NotificationChannel(
                    mediaChannelId,
                    "Reproducción multimedia",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Controles de reproducción de QvaTube en segundo plano"
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
                nm.createNotificationChannel(channel)
            }
        }
    }

    private fun updateMediaNotification(
        title: String,
        subtitle: String,
        isPlaying: Boolean,
        hasNext: Boolean,
        hasPrevious: Boolean,
        positionMs: Long,
        durationMs: Long
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(
                    arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                    notificationPermissionRequestCode
                )
            }
        }

        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureMediaChannel(nm)

        val session = mediaSession ?: MediaSession(this, "QvaTubeMediaSession").also {
            it.setCallback(object : MediaSession.Callback() {
                override fun onPlay() {
                    methodChannel?.invokeMethod("onMediaAction", mapOf("action" to "playPause"))
                }

                override fun onPause() {
                    methodChannel?.invokeMethod("onMediaAction", mapOf("action" to "playPause"))
                }

                override fun onSkipToNext() {
                    methodChannel?.invokeMethod("onMediaAction", mapOf("action" to "next"))
                }

                override fun onSkipToPrevious() {
                    methodChannel?.invokeMethod("onMediaAction", mapOf("action" to "previous"))
                }

                override fun onStop() {
                    methodChannel?.invokeMethod("onMediaAction", mapOf("action" to "stop"))
                }

                override fun onSeekTo(pos: Long) {
                    methodChannel?.invokeMethod(
                        "onMediaAction",
                        mapOf("action" to "seek", "positionMs" to pos)
                    )
                }
            })
            it.isActive = true
            mediaSession = it
        }

        val metadataBuilder = MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, title)
            .putString(
                MediaMetadata.METADATA_KEY_ARTIST,
                if (subtitle.isNotBlank()) subtitle else "QvaTube"
            )
        if (durationMs > 0L) {
            metadataBuilder.putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs)
        }
        session.setMetadata(metadataBuilder.build())

        var actions = PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_STOP or
            PlaybackState.ACTION_SEEK_TO
        if (hasNext) actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
        if (hasPrevious) actions = actions or PlaybackState.ACTION_SKIP_TO_PREVIOUS

        val stateBuilder = PlaybackState.Builder()
            .setActions(actions)
            .setState(
                if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                positionMs,
                if (isPlaying) 1.0f else 0.0f
            )
        session.setPlaybackState(stateBuilder.build())

        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val contentPendingIntent = PendingIntent.getActivity(
            this,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        fun buildActionIntent(action: String, reqCode: Int): PendingIntent {
            val intent = Intent(action).setPackage(packageName)
            return PendingIntent.getBroadcast(
                this,
                reqCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, mediaChannelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(if (subtitle.isNotBlank()) subtitle else "Reproduciendo en QvaTube")
            .setSubText("QvaTube")
            .setContentIntent(contentPendingIntent)
            .setDeleteIntent(buildActionIntent(actionStop, 4))
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(isPlaying)
            .setOnlyAlertOnce(true)

        val compactIndices = mutableListOf<Int>()
        var actionIndex = 0

        if (hasPrevious) {
            builder.addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_media_previous,
                    "Anterior",
                    buildActionIntent(actionPrev, 1)
                ).build()
            )
            compactIndices.add(actionIndex++)
        }

        builder.addAction(
            Notification.Action.Builder(
                if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (isPlaying) "Pausar" else "Reproducir",
                buildActionIntent(actionPlayPause, 2)
            ).build()
        )
        compactIndices.add(actionIndex++)

        if (hasNext) {
            builder.addAction(
                Notification.Action.Builder(
                    android.R.drawable.ic_media_next,
                    "Siguiente",
                    buildActionIntent(actionNext, 3)
                ).build()
            )
            compactIndices.add(actionIndex++)
        }

        builder.addAction(
            Notification.Action.Builder(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Detener",
                buildActionIntent(actionStop, 4)
            ).build()
        )

        val mediaStyle = Notification.MediaStyle()
            .setMediaSession(session.sessionToken)
            .setShowActionsInCompactView(*compactIndices.take(3).toIntArray())
        builder.style = mediaStyle

        nm.notify(mediaNotificationId, builder.build())
    }

    private fun clearMediaNotification() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(mediaNotificationId)
        } catch (_: Exception) {
        }
        try {
            mediaSession?.isActive = false
            mediaSession?.release()
        } catch (_: Exception) {
        }
        mediaSession = null
    }

    private fun pickImage(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("in_progress", "Ya hay una selección en curso", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "image/*"
            addCategory(Intent.CATEGORY_OPENABLE)
        }
        try {
            startActivityForResult(
                Intent.createChooser(intent, "Selecciona una imagen"),
                pickImageRequestCode
            )
        } catch (e: Exception) {
            pendingResult = null
            result.error("picker", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == unknownSourcesRequestCode) {
            val file = pendingInstallFile
            val res = pendingInstallResult
            pendingInstallFile = null
            pendingInstallResult = null
            if (file != null && file.exists()) {
                val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    packageManager.canRequestPackageInstalls()
                } else {
                    true
                }
                if (canInstall) {
                    try {
                        launchSystemPackageInstaller(file)
                        res?.success(true)
                    } catch (e: Exception) {
                        res?.error("install", e.message, null)
                    }
                } else {
                    res?.success(false)
                }
            } else {
                res?.error("missing_file", "No se encontró el APK descargado", null)
            }
            return
        }

        if (requestCode != pickImageRequestCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingResult
        pendingResult = null
        if (result == null) return
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }
        try {
            val path = copyToCache(data.data!!)
            result.success(path)
        } catch (e: Exception) {
            result.error("copy", e.message, null)
        }
    }

    private fun copyToCache(source: Uri): String {
        val target = File(cacheDir, "avatar_${System.currentTimeMillis()}.jpg")
        contentResolver.openInputStream(source).use { input ->
            if (input == null) throw IllegalStateException("No se pudo leer la imagen")
            target.outputStream().use { output -> input.copyTo(output) }
        }
        return target.absolutePath
    }
}

private class EmbeddedWebViewFactory(
    private val activity: MainActivity
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val url = params?.get("url")?.toString() ?: ""
        return EmbeddedWebViewPlatformView(context, url, activity)
    }
}

/**
 * Pantalla completa de los reproductores web (`<video>` / iframes de los
 * canales embebidos). Sin `onShowCustomView` el WebView dice que no admite
 * pantalla completa y el botón del reproductor sale deshabilitado.
 */
private class FullscreenChromeClient(private val activity: MainActivity) : WebChromeClient() {
    private var customView: View? = null
    private var callback: CustomViewCallback? = null
    private var previousOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED

    override fun onShowCustomView(view: View, callback: CustomViewCallback) {
        if (customView != null) {
            callback.onCustomViewHidden()
            return
        }
        customView = view
        this.callback = callback
        previousOrientation = activity.requestedOrientation

        val decor = activity.window.decorView as FrameLayout
        view.setBackgroundColor(Color.BLACK)
        decor.addView(
            view,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
        activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        WindowCompat.getInsetsController(activity.window, decor).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        activity.exitWebFullscreen = { onHideCustomView() }
    }

    override fun onHideCustomView() {
        val view = customView ?: return
        val decor = activity.window.decorView as FrameLayout
        decor.removeView(view)
        customView = null
        activity.exitWebFullscreen = null
        activity.requestedOrientation = previousOrientation
        WindowCompat.getInsetsController(activity.window, decor)
            .show(WindowInsetsCompat.Type.systemBars())
        val cb = callback
        callback = null
        cb?.onCustomViewHidden()
    }

    /** Al cerrar el canal estando en pantalla completa. */
    fun exitIfNeeded() {
        if (customView != null) onHideCustomView()
    }
}

@SuppressLint("SetJavaScriptEnabled")
private class EmbeddedWebViewPlatformView(
    context: Context,
    url: String,
    activity: MainActivity
) : PlatformView {
    private val chromeClient = FullscreenChromeClient(activity)

    private val webView: WebView = WebView(context).apply {
        setBackgroundColor(Color.parseColor("#0A0A0B"))
        settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            loadsImagesAutomatically = true
            mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
            useWideViewPort = true
            loadWithOverviewMode = true
        }
        webChromeClient = chromeClient
        webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean = false
        }
        if (url.isNotBlank()) {
            loadUrl(url)
        }
    }

    override fun getView(): View = webView

    override fun dispose() {
        chromeClient.exitIfNeeded()
        // Corta el audio/video antes de destruir: `destroy()` se ignora si la
        // vista sigue adjunta a la jerarquía, y el reproductor embebido seguía
        // sonando en segundo plano tras cerrar el overlay de TV/Radio.
        webView.evaluateJavascript(
            "document.querySelectorAll('video,audio').forEach(function(m){" +
                "try{m.pause();m.removeAttribute('src');m.load();}catch(e){}});",
            null
        )
        webView.onPause()
        webView.stopLoading()
        webView.loadUrl("about:blank")
        (webView.parent as? ViewGroup)?.removeView(webView)
        webView.removeAllViews()
        webView.destroy()
    }
}

/**
 * PDF abierto en el lector (uno a la vez). Se usa siempre desde el mismo
 * hilo (`pdfExecutor`), porque PdfRenderer no admite accesos concurrentes.
 */
private object PdfPages {
    private var fd: android.os.ParcelFileDescriptor? = null
    private var renderer: android.graphics.pdf.PdfRenderer? = null

    /** Abre el PDF y devuelve el tamaño (en puntos) de cada página. */
    fun open(path: String): List<List<Int>> {
        close()
        val descriptor = android.os.ParcelFileDescriptor.open(
            File(path),
            android.os.ParcelFileDescriptor.MODE_READ_ONLY
        )
        val pdf = android.graphics.pdf.PdfRenderer(descriptor)
        fd = descriptor
        renderer = pdf
        return (0 until pdf.pageCount).map { i ->
            pdf.openPage(i).use { listOf(it.width, it.height) }
        }
    }

    /** Dibuja la página [index] a [width] píxeles de ancho y la devuelve en PNG. */
    fun render(index: Int, width: Int): ByteArray {
        val pdf = renderer ?: throw IllegalStateException("PDF cerrado")
        pdf.openPage(index).use { page ->
            val w = width.coerceIn(200, 2400)
            val h = (w.toFloat() * page.height / page.width).toInt().coerceAtLeast(1)
            val bitmap = android.graphics.Bitmap.createBitmap(w, h, android.graphics.Bitmap.Config.ARGB_8888)
            bitmap.eraseColor(Color.WHITE)
            page.render(bitmap, null, null, android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
            val out = java.io.ByteArrayOutputStream()
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
            bitmap.recycle()
            return out.toByteArray()
        }
    }

    fun close() {
        try { renderer?.close() } catch (_: Exception) {}
        try { fd?.close() } catch (_: Exception) {}
        renderer = null
        fd = null
    }
}
