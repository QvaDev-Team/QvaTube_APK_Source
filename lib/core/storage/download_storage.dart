import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../platform/device_channel.dart';

/// Dónde guarda el gestor de descargas los archivos (lo que baja de
/// Telegram y lo recibido por Wi-Fi): la memoria interna de la app o la
/// tarjeta SD, para teléfonos con poco espacio interno.
///
/// Solo cambia la carpeta de los archivos: la base de datos de Telegram y
/// los índices siguen siempre en la memoria interna.
abstract final class DownloadStorage {
  const DownloadStorage._();

  /// Carpeta elegida (`StorageVolume.path`); sin valor = memoria interna.
  static const String _key = 'qvatube.download_storage_path';

  /// Carpeta con la que arrancó Telegram en esta sesión de la app (TDLib
  /// solo la lee al iniciar). `null` si Telegram aún no arrancó.
  static String? telegramRoot;

  /// Carpeta elegida por el usuario, aunque ahora no esté disponible.
  static Future<String?> selectedPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      return saved == null || saved.isEmpty ? null : saved;
    } catch (_) {
      // Sin preferencias (p. ej. en tests): memoria interna.
      return null;
    }
  }

  /// Guarda la elección (`null` = memoria interna).
  static Future<void> select(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    final internal = await DeviceChannel.cacheDirectory();
    if (path == null || path.isEmpty || path == internal) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, path);
    }
  }

  /// Carpeta donde guardar ahora. Si la tarjeta SD elegida no está (se
  /// quitó o no se puede escribir), se usa la memoria interna para no
  /// romper las descargas.
  static Future<String> root() async {
    final internal = await DeviceChannel.cacheDirectory();
    final saved = await selectedPath();
    if (saved == null || saved == internal) return internal;
    return await isWritable(saved) ? saved : internal;
  }

  /// `true` si se puede crear y escribir un archivo en [path].
  static Future<bool> isWritable(String path) async {
    try {
      final dir = Directory(path);
      await dir.create(recursive: true);
      final probe = File('${dir.path}/.qvatube_probe');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ubicaciones con las que alguna vez arrancó Telegram (y la memoria
  /// interna): ahí puede haber archivos ya descargados.
  static const String _historyKey = 'qvatube.download_storage_history';

  static Future<Set<String>> knownRoots() async {
    List<String>? history;
    try {
      final prefs = await SharedPreferences.getInstance();
      history = prefs.getStringList(_historyKey);
    } catch (_) {}
    return {await DeviceChannel.cacheDirectory(), ...?history};
  }

  static Future<void> addKnownRoot(String root) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey) ?? const <String>[];
    if (list.contains(root)) return;
    await prefs.setStringList(_historyKey, [...list, root]);
  }

  /// Carpeta de los archivos de Telegram dentro de [root].
  static String telegramFilesDir(String root) => '$root/tdlib/archivos';

  /// Carpeta de lo recibido por Wi-Fi dentro de [root].
  static String receivedDir(String root) => '$root/qvashare';
}
