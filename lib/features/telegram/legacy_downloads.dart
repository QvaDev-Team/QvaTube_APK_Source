import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/download_storage.dart';

/// Archivos de Telegram descargados en otra ubicación (antes de cambiar
/// entre memoria interna y tarjeta SD).
///
/// TDLib guarda en su base de datos la ruta de cada archivo *relativa* a
/// `files_directory`: al cambiar de carpeta deja de encontrar lo ya
/// descargado. Lo descargado se queda donde está, y aquí se recuerda su
/// ruta completa para que siga apareciendo como descargado y se pueda ver.
abstract final class LegacyDownloads {
  const LegacyDownloads._();

  /// `{messageId: ruta completa}` de los archivos ya descargados.
  static const String _pathsKey = 'qvatube.telegram_local_paths';

  static final Map<int, String> _paths = {};

  /// Archivos encontrados en las ubicaciones anteriores, por tamaño (para
  /// lo descargado antes de que existiera [_paths]).
  static final Map<int, List<String>> _bySize = {};

  static SharedPreferences? _prefs;
  static bool _dirty = false;

  /// Carga las rutas guardadas y revisa las carpetas de las ubicaciones
  /// que no son la actual. Se llama al arrancar Telegram, antes de leer la
  /// lista de archivos.
  static Future<void> init({
    required String currentRoot,
    required Iterable<String> otherRoots,
  }) async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    _paths.clear();
    try {
      final raw = prefs.getString(_pathsKey);
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map;
        map.forEach((k, v) {
          final id = int.tryParse(k.toString());
          if (id != null && v is String && v.isNotEmpty) _paths[id] = v;
        });
      }
    } catch (_) {}

    _bySize.clear();
    for (final root in {...otherRoots}..remove(currentRoot)) {
      await _scan(DownloadStorage.telegramFilesDir(root));
    }
  }

  static Future<void> _scan(String path) async {
    final dir = Directory(path);
    try {
      if (!await dir.exists()) return;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        // Partes a medias y miniaturas no cuentan como descargas.
        final rel = e.path.substring(path.length);
        if (rel.startsWith('/temp/') || rel.startsWith('/thumbnails/')) {
          continue;
        }
        final size = await e.length();
        if (size <= 0) continue;
        (_bySize[size] ??= []).add(e.path);
      }
    } catch (_) {}
  }

  /// TDLib dice que [messageId] está descargado en [path]: se recuerda.
  static void remember(int messageId, String path) {
    if (path.isEmpty || _paths[messageId] == path) return;
    _paths[messageId] = path;
    _scheduleSave();
  }

  /// Ruta de lo ya descargado de [messageId] en otra ubicación, o `null`.
  static String? find(int messageId, String name, int size) {
    final known = _paths[messageId];
    if (known != null && _matches(known, size)) return known;

    final candidates = size > 0 ? _bySize[size] : null;
    if (candidates == null || candidates.isEmpty) return null;
    final stem = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    String? pick;
    for (final c in candidates) {
      final base = c.substring(c.lastIndexOf('/') + 1);
      if (base == name || (stem.isNotEmpty && base.startsWith(stem))) {
        pick = c;
        break;
      }
    }
    // Sin coincidencia de nombre solo vale si el tamaño es único.
    pick ??= candidates.length == 1 ? candidates.first : null;
    if (pick == null || !File(pick).existsSync()) return null;
    candidates.remove(pick);
    remember(messageId, pick);
    return pick;
  }

  static bool _matches(String path, int size) {
    try {
      final f = File(path);
      if (!f.existsSync()) return false;
      return size <= 0 || f.lengthSync() == size;
    } catch (_) {
      return false;
    }
  }

  /// `true` si [path] está fuera de la carpeta con la que arrancó TDLib
  /// (TDLib no lo conoce y hay que borrarlo a mano).
  static bool isOutsideTelegram(String path) {
    final root = DownloadStorage.telegramRoot;
    if (root == null || path.isEmpty) return false;
    final dir = DownloadStorage.telegramFilesDir(root);
    if (path.startsWith('$dir/')) return false;
    // TDLib da rutas reales (p. ej. /data/data/… en vez de /data/user/0/…).
    try {
      final real = Directory(dir).resolveSymbolicLinksSync();
      if (path.startsWith('$real/')) return false;
    } catch (_) {}
    return true;
  }

  /// Olvida [messageId] (y borra el archivo si TDLib no lo gestiona).
  static Future<void> forget(int messageId, String path) async {
    if (isOutsideTelegram(path)) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    if (_paths.remove(messageId) != null) _scheduleSave();
  }

  static void _scheduleSave() {
    if (_dirty) return;
    _dirty = true;
    Future<void>.delayed(const Duration(seconds: 2), () async {
      _dirty = false;
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setString(
        _pathsKey,
        jsonEncode({for (final e in _paths.entries) '${e.key}': e.value}),
      );
    });
  }
}
