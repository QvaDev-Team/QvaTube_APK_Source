package net.qvatube.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Canal nativo mínimo (sin dependencias externas) para:
 *  - elegir una imagen de la galería y copiarla a la caché de la app
 *    (se usa en POST /api/auth/avatar);
 *  - abrir enlaces externos (bot de Telegram, comunidad de WhatsApp).
 */
class MainActivity : FlutterActivity() {
    private val channelName = "qvatube/device"
    private val pickImageRequestCode = 4321
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                    else -> result.notImplemented()
                }
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
