import 'dart:io';

import 'package:flutter/services.dart';

/// Puente con el canal nativo `qvatube/device` (MainActivity.kt).
///
/// - `pickImage()`: abre la galería y devuelve la ruta local de la imagen
///   (usada por `POST /api/auth/avatar`).
/// - `openUrl(url)`: abre un enlace externo (bot de Telegram, WhatsApp).
abstract final class DeviceChannel {
  const DeviceChannel._();

  static const MethodChannel _channel = MethodChannel('qvatube/device');
  static bool _handlerInitialized = false;
  static void Function(String action, int? positionMs)? _mediaActionListener;
  static void Function()? _updateTapListener;

  /// Registra el listener que recibe acciones desde la barra de notificaciones
  /// multimedia (`playPause`, `next`, `previous`, `stop`, `seek`).
  static void setMediaActionListener(
    void Function(String action, int? positionMs)? listener,
  ) {
    _mediaActionListener = listener;
    _ensureHandler();
  }

  /// Registra quién reacciona al tocar la notificación de "nueva versión"
  /// con la app ya abierta (el aviso de actualización vuelve a comprobar).
  static void setUpdateNotificationTapListener(void Function()? listener) {
    _updateTapListener = listener;
    _ensureHandler();
  }

  static void _ensureHandler() {
    if (!_handlerInitialized) {
      _handlerInitialized = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onUpdateNotificationTap') {
          _updateTapListener?.call();
        } else if (call.method == 'onMediaAction') {
          final args = call.arguments;
          if (args is Map) {
            final action = args['action']?.toString() ?? '';
            final pos = (args['positionMs'] as num?)?.toInt();
            _mediaActionListener?.call(action, pos);
          }
        }
      });
    }
  }

  /// Programa en Android la comprobación periódica de actualizaciones en
  /// segundo plano (WorkManager), que avisa con una notificación.
  static Future<void> scheduleUpdateCheck(String manifestUrl) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('scheduleUpdateCheck', {
        'manifestUrl': manifestUrl,
      });
    } on PlatformException {
      // sin WorkManager no hay aviso en segundo plano; el banner sigue igual
    } on MissingPluginException {
      // ignorar
    }
  }

  /// Actualiza o muestra los controles del reproductor en la barra de
  /// notificaciones del sistema y en la pantalla de bloqueo.
  static Future<void> updateMediaNotification({
    required String title,
    String? subtitle,
    required bool isPlaying,
    bool hasNext = false,
    bool hasPrevious = false,
    int positionMs = 0,
    int durationMs = 0,
  }) async {
    try {
      await _channel.invokeMethod<bool>('updateMediaNotification', {
        'title': title,
        'subtitle': subtitle ?? '',
        'isPlaying': isPlaying,
        'hasNext': hasNext,
        'hasPrevious': hasPrevious,
        'positionMs': positionMs,
        'durationMs': durationMs,
      });
    } on PlatformException {
      // ignorar en plataformas no compatibles
    } on MissingPluginException {
      // ignorar en plataformas no compatibles
    }
  }

  /// Oculta la notificación de reproducción multimedia.
  static Future<void> clearMediaNotification() async {
    try {
      await _channel.invokeMethod<bool>('clearMediaNotification');
    } on PlatformException {
      // ignorar
    } on MissingPluginException {
      // ignorar
    }
  }

  /// Devuelve la ruta local de la imagen elegida, o `null` si el usuario
  /// cancela la selección.
  static Future<String?> pickImage() async {
    try {
      return await _channel.invokeMethod<String>('pickImage');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Versión instalada de la app (`versionCode` / `versionName` / `lastUpdateTime`).
  static Future<({int versionCode, String versionName, int lastUpdateTime})>
      getInstalledVersion() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getInstalledVersion',
      );
      final code = (result?['versionCode'] as num?)?.toInt() ?? 0;
      final name = result?['versionName']?.toString() ?? '';
      final updated = (result?['lastUpdateTime'] as num?)?.toInt() ?? 0;
      return (versionCode: code, versionName: name, lastUpdateTime: updated);
    } on PlatformException {
      return (versionCode: 0, versionName: '', lastUpdateTime: 0);
    } on MissingPluginException {
      return (versionCode: 0, versionName: '', lastUpdateTime: 0);
    }
  }

  /// Versión de un APK descargado (para comprobar actualizaciones).
  static Future<({int versionCode, String versionName})> getApkVersion(
    String path,
  ) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getApkVersion',
        {'path': path},
      );
      final code = (result?['versionCode'] as num?)?.toInt() ?? 0;
      final name = result?['versionName']?.toString() ?? '';
      return (versionCode: code, versionName: name);
    } on PlatformException {
      return (versionCode: 0, versionName: '');
    } on MissingPluginException {
      return (versionCode: 0, versionName: '');
    }
  }

  /// Abre el instalador del sistema con el APK descargado.
  ///
  /// Devuelve `false` si el usuario tiene que autorizar antes la instalación
  /// (en ese caso se abrió el ajuste del sistema).
  static Future<bool> installApk(String path) async {
    try {
      return await _channel.invokeMethod<bool>('installApk', {'path': path}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Ruta del APK instalado (`applicationInfo.sourceDir`), base de los
  /// parches de actualización diferencial. `null` si no está disponible.
  static Future<String?> installedApkPath() async {
    try {
      final path = await _channel.invokeMethod<String>('getInstalledApkPath');
      return path == null || path.isEmpty ? null : path;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Carpeta de caché de la app (donde se descargan las actualizaciones).
  static Future<String> cacheDirectory() async {
    try {
      final path = await _channel.invokeMethod<String>('cacheDirectory');
      if (path != null && path.isNotEmpty) return path;
    } on PlatformException {
      // se usa la carpeta temporal
    } on MissingPluginException {
      // se usa la carpeta temporal
    }
    return Directory.systemTemp.path;
  }

  /// Abre una URL en el navegador del sistema.
  static Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
