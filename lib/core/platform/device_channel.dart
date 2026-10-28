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
