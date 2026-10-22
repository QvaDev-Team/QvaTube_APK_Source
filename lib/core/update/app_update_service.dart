import 'dart:io';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../platform/device_channel.dart';

/// Información de una versión disponible para instalar.
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.versionCode,
    required this.url,
    this.versionName,
    this.notes,
    this.sizeMb,
    this.publishedAt,
    this.localPath,
  });

  /// Lee el manifiesto JSON que publica el workflow de GitHub Actions.
  ///
  /// ```json
  /// {
  ///   "version_code": 2002,
  ///   "version_name": "1.0.2",
  ///   "url": "https://.../qvatube.apk",
  ///   "notes": "Novedades de la versión",
  ///   "size_mb": 26.0,
  ///   "published_at": "2026-10-21T18:00:00Z"
  /// }
  /// ```
  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      versionCode: (json['version_code'] as num?)?.toInt() ?? 0,
      versionName: json['version_name']?.toString(),
      url: json['url']?.toString() ?? '',
      notes: json['notes']?.toString(),
      sizeMb: (json['size_mb'] as num?)?.toDouble(),
      publishedAt: json['published_at']?.toString(),
    );
  }

  final int versionCode;
  final String url;
  final String? versionName;
  final String? notes;
  final double? sizeMb;
  final String? publishedAt;

  /// Ruta local del APK ya descargado (si se comprobó con una descarga).
  final String? localPath;

  bool get isDownloaded => localPath != null;
}

/// Resultado de la comprobación de actualizaciones.
enum UpdateCheckResult {
  /// Ya estás en la última versión.
  upToDate,

  /// Hay una versión nueva disponible.
  updateAvailable,

  /// No se pudo comprobar (sin red, manifiesto inexistente…).
  failed,
}

/// Servicio que comprueba, descarga e instala las actualizaciones.
class AppUpdateService {
  AppUpdateService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(minutes: 10),
                followRedirects: true,
                headers: const {'Accept': 'application/json'},
              ),
            );

  final Dio _dio;

  /// Versión instalada en el dispositivo.
  Future<({int versionCode, String versionName})> installedVersion() async {
    final result = await DeviceChannel.getInstalledVersion();
    return (
      versionCode: result.versionCode,
      versionName: result.versionName,
    );
  }

  /// Comprueba si hay una versión nueva.
  ///
  /// Primero intenta el **manifiesto** (JSON,Weight ~1 KB). Si no existe,
  /// con [deep] se descarga el APK a la caché y se lee su `versionCode`
  /// directamente (así funciona aunque el backend no exponga el manifiesto).
  Future<({UpdateCheckResult result, AppUpdateInfo? info})> check({
    bool deep = false,
    void Function(int received, int total)? onDownloadProgress,
  }) async {
    try {
      final installed = await installedVersion();

      // 1) Manifiesto lightweight.
      final manifest = await _fetchManifest();
      if (manifest != null) {
        if (manifest.versionCode > installed.versionCode) {
          return (result: UpdateCheckResult.updateAvailable, info: manifest);
        }
        return (result: UpdateCheckResult.upToDate, info: null);
      }

      // 2) Comprobación profunda: se descarga el APK y se lee su versión.
      if (!deep) {
        return (result: UpdateCheckResult.upToDate, info: null);
      }

      final file = await download(
        AppUpdateInfo(versionCode: 0, url: AppConfig.updateApkUrl),
        onProgress: onDownloadProgress,
      );
      final apkVersion = await DeviceChannel.getApkVersion(file.path);
      final info = AppUpdateInfo(
        versionCode: apkVersion.versionCode,
        versionName: apkVersion.versionName,
        url: AppConfig.updateApkUrl,
        localPath: file.path,
      );
      if (apkVersion.versionCode > installed.versionCode) {
        return (result: UpdateCheckResult.updateAvailable, info: info);
      }
      return (result: UpdateCheckResult.upToDate, info: null);
    } catch (_) {
      return (result: UpdateCheckResult.failed, info: null);
    }
  }

  /// Descarga el APK de la actualización en la caché de la app.
  Future<File> download(
    AppUpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = Directory('${(await _cacheDir()).path}/updates');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final target = File('${dir.path}/qvatube-update.apk');
    if (target.existsSync()) {
      target.deleteSync();
    }

    await _dio.download(
      info.url,
      target.path,
      onReceiveProgress: onProgress,
      options: Options(responseType: ResponseType.bytes),
    );
    return target;
  }

  /// Abre el instalador del sistema para instalar el APK descargado.
  ///
  /// Devuelve `false` si el usuario todavía no ha autorizado a la app a
  /// instalar paquetes (en ese caso se abrió el ajuste correspondiente).
  Future<bool> install(File apk) async {
    return DeviceChannel.installApk(apk.path);
  }

  Future<AppUpdateInfo?> _fetchManifest() async {
    final url = AppConfig.updateManifestUrl;
    if (url.isEmpty) return null;
    final response = await _dio.get<Map<String, dynamic>>(url);
    final data = response.data;
    if (data == null) return null;
    // Se acepta tanto el objeto plano como envuelto en {"update": {...}}.
    final payload = data['update'] is Map
        ? Map<String, dynamic>.from(data['update'] as Map)
        : data;
    final info = AppUpdateInfo.fromJson(payload);
    if (info.versionCode <= 0 || info.url.isEmpty) return null;
    return info;
  }

  Future<Directory> _cacheDir() async {
    final path = await DeviceChannel.cacheDirectory();
    return Directory(path);
  }
}
