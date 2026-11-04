import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show FileImage;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../platform/device_channel.dart';
import 'app_assets.dart';

/// Arte de temporada decidido por el servidor (ver doc "Logos dinámicos").
///
/// El servidor elige la temporada por fecha (hora de Cuba) o por orden del
/// admin y sirve siempre en las mismas URLs el logo (`/assets/logo.png`) y el
/// icono cuadrado (`/assets/favicon.png`) que tocan. La app:
///  1. pregunta `GET /api/season` al abrir y al volver a primer plano;
///  2. si cambió (o no tiene copia), descarga el logo (en WebP) y el favicon
///     y los guarda en `filesDir/branding/` para usarlos sin conexión;
///  3. cambia el icono del launcher al alias de esa temporada.
/// Sin red ni copia guardada se usa el arte incluido en el APK.
class SeasonBranding {
  SeasonBranding._();

  static const _seasonKey = 'qvatube.season';
  static const _appliedIconKey = 'qvatube.season_icon';

  /// Temporadas con alias de icono en el APK (AndroidManifest.xml).
  static const launcherSeasons = {'halloween', 'navidad', 'sanvalentin'};

  static final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  /// Cambia cuando hay arte nuevo, para redibujar logos e iconos.
  static ValueListenable<int> get revision => _revision;

  static SharedPreferences? _prefs;
  static Directory? _dir;
  static String? _season;
  static bool _refreshing = false;

  /// Temporada activa según el servidor (`null` = arte normal).
  static String? get season => _season;

  /// Logo descargado del servidor, si hay copia guardada.
  static File? logoFile;

  /// Icono cuadrado (512) descargado del servidor, si hay copia guardada.
  static File? faviconFile;

  /// Carga la última temporada y el arte guardado (antes del primer frame).
  static Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    _season = prefs.getString(_seasonKey);
    await AppAssets.init(themeId: _season ?? AppAssets.fallbackThemeId);
    try {
      final dir = Directory('${await DeviceChannel.cacheDirectory()}/branding');
      await dir.create(recursive: true);
      _dir = dir;
      final logo = File('${dir.path}/logo');
      final favicon = File('${dir.path}/favicon.png');
      logoFile = await logo.exists() ? logo : null;
      faviconFile = await favicon.exists() ? favicon : null;
    } catch (_) {}
    _revision.value++;
  }

  /// Consulta la temporada y, si cambió, baja el arte nuevo y cambia el
  /// icono. [canChangeIcon] = la app está visible y sin reproducir nada
  /// (algunos launchers cierran la app al cambiar de alias).
  static Future<void> refresh({required bool canChangeIcon}) async {
    final prefs = _prefs;
    if (prefs == null || _refreshing) return;
    _refreshing = true;
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          headers: const {'Cache-Control': 'no-cache'},
        ),
      );
      final response = await dio.get<Map<String, dynamic>>('/api/season');
      final raw = response.data?['season'];
      final season = raw is String && raw.isNotEmpty ? raw : null;

      final changed = season != _season;
      if (changed || logoFile == null || faviconFile == null) {
        await _downloadArt(dio);
        _season = season;
        await prefs.setString(_seasonKey, season ?? '');
        if (season == null) await prefs.remove(_seasonKey);
        // Respaldo del APK de esa temporada (por si se borra la copia).
        await AppAssets.setTheme(season ?? AppAssets.fallbackThemeId) ||
            await AppAssets.setTheme(AppAssets.fallbackThemeId);
        _revision.value++;
      }
      if (canChangeIcon) await _applyLauncherIcon(prefs);
    } catch (error) {
      debugPrint('[SeasonBranding] Sin datos de temporada: $error');
    } finally {
      _refreshing = false;
    }
  }

  static Future<void> _downloadArt(Dio dio) async {
    final dir = _dir;
    if (dir == null) return;
    Future<File?> save(String path, String name, {String? accept}) async {
      try {
        final res = await dio.get<List<int>>(
          path,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {'Accept': ?accept},
          ),
        );
        final bytes = res.data;
        if (bytes == null || bytes.isEmpty) return null;
        // Se escribe aparte y se renombra para no dejar un archivo a medias.
        final tmp = File('${dir.path}/$name.tmp');
        await tmp.writeAsBytes(Uint8List.fromList(bytes), flush: true);
        final file = await tmp.rename('${dir.path}/$name');
        // Image.file cachea por ruta: hay que soltar la versión anterior.
        await FileImage(file).evict();
        return file;
      } catch (_) {
        return null;
      }
    }

    // Android decodifica WebP: ~1/6 del peso del PNG.
    logoFile = await save('/assets/logo.png', 'logo', accept: 'image/webp') ?? logoFile;
    faviconFile = await save('/assets/favicon.png', 'favicon.png') ?? faviconFile;
  }

  static Future<void> _applyLauncherIcon(SharedPreferences prefs) async {
    final target =
        launcherSeasons.contains(_season) ? _season! : 'default';
    if (prefs.getString(_appliedIconKey) == target) return;
    final ok = await DeviceChannel.applyLauncherIcon(target);
    if (ok) await prefs.setString(_appliedIconKey, target);
  }
}
