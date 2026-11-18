import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Estado de conexión con el servidor de QvaTube que ve la interfaz: pasa a
/// `true` cuando una petición falla por falta de red y a `false` en cuanto
/// otra responde.
abstract final class OfflineStatus {
  const OfflineStatus._();

  static final ValueNotifier<bool> offline = ValueNotifier(false);

  static void markOffline() {
    if (!offline.value) offline.value = true;
  }

  static void markOnline() {
    if (offline.value) offline.value = false;
  }
}

/// Copia en disco de las respuestas `GET` de la API para poder abrir la app
/// y ver el catálogo de cada sección sin conexión.
///
/// - Siempre se intenta la red primero; si responde, se guarda la respuesta.
/// - Si falla por falta de red, se devuelve la última copia guardada.
/// - La clave incluye la sesión: los datos personales (favoritos, plan,
///   seguir viendo) de una cuenta nunca se muestran en otra.
class ResponseCache {
  ResponseCache(this._directory);

  /// Carpeta donde se guardan las respuestas (se crea si no existe).
  final Future<Directory> Function() _directory;
  Directory? _dir;

  /// Rutas que NO se guardan: sesión, contadores en vivo y avisos efímeros.
  static const List<String> _excluded = [
    '/api/auth',
    '/api/tv/viewers',
    '/api/tv/heartbeat',
    '/api/progress',
    '/api/share-index',
    '/api/apk-info',
    '/api/sync-',
    '/api/push',
    '/watch/',
    '/read/',
  ];

  /// `true` si la respuesta de [path] se puede guardar y servir sin red.
  static bool isCacheable(String path) =>
      path.startsWith('/api/') && !_excluded.any(path.startsWith);

  /// Clave estable: ruta + parámetros ordenados + sesión.
  static String keyFor(
    String path,
    Map<String, dynamic>? query,
    String? session,
  ) {
    final params = (query ?? const <String, dynamic>{}).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final raw = StringBuffer(path);
    for (final p in params) {
      raw.write('&${p.key}=${p.value}');
    }
    raw.write('|${session ?? ''}');
    return sha1.convert(utf8.encode(raw.toString())).toString();
  }

  Future<Directory> _cacheDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final dir = await _directory();
    await dir.create(recursive: true);
    return _dir = dir;
  }

  Future<void> store(String key, Object? data) async {
    if (data == null) return;
    try {
      final dir = await _cacheDir();
      final tmp = File('${dir.path}/$key.tmp');
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename('${dir.path}/$key.json');
    } catch (e) {
      debugPrint('[Caché] No se pudo guardar $key: $e');
    }
  }

  Future<Object?> read(String key) async {
    try {
      final file = File('${(await _cacheDir()).path}/$key.json');
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }
}
