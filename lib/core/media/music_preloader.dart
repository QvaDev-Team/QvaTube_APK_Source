import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../platform/device_channel.dart';

/// Precarga de la siguiente pista de música (reproducción sin cortes), igual
/// que el mini-reproductor de la web (`maybeStartPreload` en `js/app.js`):
/// cuando la pista actual lleva unos segundos sonando se descarga ENTERA la
/// siguiente a un archivo local y, al cambiar de pista, se reproduce desde
/// ahí al instante, sin esperar a la red.
///
/// Como en la web, `/watch` descuenta el cupo de reproducciones al servir la
/// pista, así que la precarga lo gasta aunque luego no se escuche (mismo
/// trade-off que Spotify/YouTube Music).
class MusicPreloader {
  MusicPreloader();

  /// Segundos de la pista actual antes de empezar a precargar la siguiente.
  static const double startAfterSeconds = 2.5;

  static const int _maxFiles = 12;
  static const int _maxBytes = 400 * 1024 * 1024;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );

  String? _inFlightKey;
  CancelToken? _cancelToken;
  Directory? _dir;

  static String _key(int chatId, int msgId) => '${chatId}_$msgId';

  Future<Directory> _cacheDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final dir = Directory('${await DeviceChannel.cacheDirectory()}/musica');
    await dir.create(recursive: true);
    return _dir = dir;
  }

  /// Archivo local completo de la pista, o `null` si no está precargada.
  Future<File?> completedFile(int chatId, int msgId) async {
    final file = File('${(await _cacheDir()).path}/${_key(chatId, msgId)}');
    if (await file.exists() && await file.length() > 0) {
      // Se toca la fecha para que la limpieza conserve las recientes.
      try {
        await file.setLastModified(DateTime.now());
      } catch (_) {}
      return file;
    }
    return null;
  }

  /// Empieza a descargar la pista si no está ya descargada o en curso.
  /// Cancela la precarga anterior si era de otra pista.
  Future<void> preload({
    required int chatId,
    required int msgId,
    required String url,
    required Map<String, String> headers,
  }) async {
    final key = _key(chatId, msgId);
    if (_inFlightKey == key) return;
    if (await completedFile(chatId, msgId) != null) return;

    cancel();
    final token = CancelToken();
    _cancelToken = token;
    _inFlightKey = key;

    final dir = await _cacheDir();
    final part = File('${dir.path}/$key.part');
    final done = File('${dir.path}/$key');
    try {
      final response = await _dio.download(
        url,
        part.path,
        cancelToken: token,
        options: Options(headers: headers),
      );
      final status = response.statusCode ?? 0;
      if (status != 200 && status != 206) {
        throw StateError('HTTP $status');
      }
      await part.rename(done.path);
      unawaited(_prune(keep: done.path));
    } catch (e) {
      final cancelled = e is DioException && CancelToken.isCancel(e);
      if (!cancelled) debugPrint('[Música] Precarga fallida ($key): $e');
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
    } finally {
      if (_inFlightKey == key) {
        _inFlightKey = null;
        _cancelToken = null;
      }
    }
  }

  /// Cancela la precarga en curso (cambio de lista, cerrar el reproductor).
  void cancel() {
    _cancelToken?.cancel();
    _cancelToken = null;
    _inFlightKey = null;
  }

  /// Deja como mucho [_maxFiles] pistas y [_maxBytes] en caché, borrando las
  /// usadas hace más tiempo.
  Future<void> _prune({required String keep}) async {
    try {
      final dir = await _cacheDir();
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && !entity.path.endsWith('.part')) files.add(entity);
      }
      final stats = {for (final f in files) f: await f.stat()};
      files.sort((a, b) => stats[b]!.modified.compareTo(stats[a]!.modified));
      var total = 0;
      for (var i = 0; i < files.length; i++) {
        total += stats[files[i]]!.size;
        final over = i >= _maxFiles || total > _maxBytes;
        if (over && files[i].path != keep) await files[i].delete();
      }
    } catch (_) {}
  }
}
