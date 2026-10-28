package net.qvatube.app

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.View
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File

/**
 * Canal nativo mínimo (sin dependencias externas) para:
 *  - elegir una imagen de la galería y copiarla a la caché de la app
 *    (se usa en POST /api/auth/avatar);
 *  - abrir enlaces externos (bot de Telegram, comunidad de WhatsApp);
 *  - consultar la versión instalada y la de un APK descargado;
 *  - instalar una actualización (autoactualización desde la app);
 *  - reproducir señales embebidas (TV y Radio en vivo) mediante WebView nativo.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "qvatube/device"
    private val pickImageRequestCode = 4321
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory("qvatube/webview", EmbeddedWebViewFactory())

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
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
                    "cacheDirectory" -> result.success(cacheDir.absolutePath)
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("bad_args", "Ruta vacía", null)
                        } else {
                            installApk(File(path), result)
                        }
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
     * Si el usuario todavía no ha autorizado a esta app a instalar
     * paquetes, se abre la pantalla de Ajustes correspondiente y se devuelve
     * un error para que la app lo explique.
     */
    private fun installApk(file: File, result: MethodChannel.Result) {
        if (!file.exists()) {
            result.error("missing_file", "No se encontró el APK descargado", null)
            return
        }
        try {
            @Suppress("DEPRECATION")
            val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                packageManager.canRequestPackageInstalls()
            } else {
                true
            }
            if (!canInstall) {
                val settings = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
                startActivity(settings)
                result.error(
                    "permission_required",
                    "Hay que permitir las instalaciones de esta app",
                    null
                )
                return
            }

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
            result.success(true)
        } catch (e: Exception) {
            result.error("install", e.message, null)
        }
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

private class EmbeddedWebViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val url = params?.get("url")?.toString() ?: ""
        return EmbeddedWebViewPlatformView(context, url)
    }
}

@SuppressLint("SetJavaScriptEnabled")
private class EmbeddedWebViewPlatformView(
    context: Context,
    url: String
) : PlatformView {
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
        webChromeClient = WebChromeClient()
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
        webView.stopLoading()
        webView.loadUrl("about:blank")
        webView.destroy()
    }
}
