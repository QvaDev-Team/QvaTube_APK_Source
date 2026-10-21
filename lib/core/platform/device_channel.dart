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
