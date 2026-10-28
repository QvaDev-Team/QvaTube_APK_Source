import 'dart:convert';
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
    this.changes = const [],
    this.sizeMb,
    this.publishedAt,
    this.localPath,
  });

  /// Lee el manifiesto JSON que publica el workflow de GitHub Actions.
  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final rawChanges = json['changes'];
    final parsedChanges = rawChanges is List
        ? rawChanges
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>[];

    return AppUpdateInfo(
      versionCode: (json['version_code'] as num?)?.toInt() ?? 0,
      versionName: json['version_name']?.toString(),
      url: json['url']?.toString() ?? '',
      notes: json['notes']?.toString(),
      changes: parsedChanges,
      sizeMb: (json['size_mb'] as num?)?.toDouble(),
      publishedAt: json['published_at']?.toString(),
    );
  }

  final int versionCode;
  final String url;
  final String? versionName;
  final String? notes;
  final List<String> changes;
  final double? sizeMb;
  final String? publishedAt;

  /// Ruta local del APK ya descargado (si se comprobó con una descarga).
  final String? localPath;

  bool get isDownloaded => localPath != null;

  AppUpdateInfo copyWith({
    int? versionCode,
    String? url,
    String? versionName,
    String? notes,
    List<String>? changes,
    double? sizeMb,
    String? publishedAt,
    String? localPath,
  }) {
    return AppUpdateInfo(
      versionCode: versionCode ?? this.versionCode,
      url: url ?? this.url,
      versionName: versionName ?? this.versionName,
      notes: notes ?? this.notes,
      changes: changes ?? this.changes,
      sizeMb: sizeMb ?? this.sizeMb,
      publishedAt: publishedAt ?? this.publishedAt,
      localPath: localPath ?? this.localPath,
    );
  }

  /// Devuelve la lista de novedades explicadas en lenguaje claro y no técnico
  /// para cualquier usuario.
  List<String> get userFriendlyChanges {
    final rawList = <String>[
      ...changes,
      if (notes != null && notes!.trim().isNotEmpty)
        ...notes!
            .split(RegExp(r'[\r\n]+|(?:\s*[•·]\s*)'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty),
    ];

    final friendly = <String>[];
    final seen = <String>{};

    for (final raw in rawList) {
      final converted = _humanizeChangeLine(raw);
      if (converted == null || converted.isEmpty) continue;
      final key = converted.toLowerCase();
      if (seen.add(key)) {
        friendly.add(converted);
      }
    }

    if (friendly.isNotEmpty) return friendly;

    return const [
      'Mejoras en la interfaz y fluidez general de la aplicación.',
      'Corrección de errores para una reproducción y descarga más estable.',
      'Nuevas funciones habilitadas en el catálogo y canales en vivo.',
    ];
  }

  /// Convierte mensajes técnicos o commits en explicaciones sencillas para el usuario.
  static String? _humanizeChangeLine(String input) {
    var line = input.trim();
    if (line.isEmpty) return null;

    // Ignorar tablas markdown, cabeceras técnicas, enlaces o hashes de commit.
    if (line.startsWith('#') ||
        line.startsWith('|') ||
        line.startsWith('http://') ||
        line.startsWith('https://') ||
        line.startsWith('`qvatube.apk`') ||
        line.startsWith('**Descarga') ||
        line.startsWith('Los símbolos')) {
      return null;
    }

    // Quitar viñetas iniciales (-, *, •).
    line = line.replaceFirst(RegExp(r'^[-*•·]+\s*'), '').trim();
    if (line.isEmpty) return null;

    final lower = line.toLowerCase();

    // Ignorar commits puramente técnicos de compilación, CI, análisis estático o archivos.
    if (lower.contains('analisis estatico') ||
        lower.contains('análisis estático') ||
        lower.contains('compilado de la app') ||
        lower.contains('compilacion en github') ||
        lower.contains('compilación en github') ||
        lower.contains('codigo comentado') ||
        lower.contains('código comentado') ||
        lower.startsWith('ci:') ||
        lower.startsWith('chore:') ||
        lower.startsWith('test:') ||
        lower.startsWith('build:') ||
        lower.startsWith('merge ') ||
        RegExp(r'^actualizar\s+\S+\.dart$', caseSensitive: false).hasMatch(line)) {
      return null;
    }

    // Traducciones directas de commits conocidos a lenguaje amigable.
    if (lower.contains('simplificar la pantalla de inicio') ||
        lower.contains('reorganizar la barra superior')) {
      return 'Diseño renovado en la pantalla de inicio y la barra superior.';
    }
    if (lower.contains('inicio como primera opción') ||
        lower.contains('navegación inferior')) {
      return 'Mejoras en la barra de navegación inferior para acceder más rápido a Inicio.';
    }
    if (lower.contains('información real del contenido y del plan')) {
      return 'Visualización completa de sinopsis, reparto, tráiler y estado de tu plan.';
    }
    if (lower.contains('detalle de contenido, descargas y estadísticas')) {
      return 'Nueva ficha de detalles para películas y series, mejoras en descargas y estadísticas en vivo.';
    }
    if (lower.contains('enlaces de descarga de actualizaciones')) {
      return 'Corrección en el sistema de descarga e instalación de actualizaciones.';
    }
    if (lower.contains('iconos temáticos')) {
      return 'Nuevos iconos y mejoras visuales en el menú principal.';
    }

    // Detectar prefijos tipo Conventional Commits (feat:, fix:, refactor:, etc.)
    final match = RegExp(
      r'^(feat|fix|refactor|perf|style|ui|update)(\([^)]+\))?:\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(line);

    String prefix = '';
    if (match != null) {
      final type = match.group(1)!.toLowerCase();
      line = match.group(3)!.trim();
      switch (type) {
        case 'feat':
          prefix = 'Novedad: ';
        case 'fix':
          prefix = 'Corrección: ';
        case 'refactor':
        case 'style':
        case 'ui':
          prefix = 'Mejora visual: ';
        case 'perf':
          prefix = 'Mejora de rendimiento: ';
      }
    }

    // Limpiar términos demasiado técnicos si quedaron en el texto.
    line = line
        .replaceAll(RegExp(r'\bendpoint(s)?\b', caseSensitive: false), 'conexión')
        .replaceAll(RegExp(r'\bopenapi(\.json)?\b', caseSensitive: false), 'catálogo')
        .replaceAll(RegExp(r'\bwidget(s)?\b', caseSensitive: false), 'elemento visual')
        .replaceAll(RegExp(r'\bprovider(s)?\b', caseSensitive: false), 'datos')
        .replaceAll(RegExp(r'\brefactor\b', caseSensitive: false), 'mejora');

    if (line.isEmpty) return null;

    final capitalized = line[0].toUpperCase() + line.substring(1);
    final result = '$prefix$capitalized';
    return result.endsWith('.') ? result : '$result.';
  }
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
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(minutes: 10),
              followRedirects: true,
              headers: const {
                'Accept': 'application/json',
                'Cache-Control': 'no-cache',
                'Pragma': 'no-cache',
              },
            ),
          );

  final Dio _dio;

  /// Normaliza el `versionCode` eliminando el prefijo ABI (`1000 * abiIndex`)
  /// que añade Flutter automáticamente al compilar con `--split-per-abi`
  /// (por ejemplo, `2001` en arm64-v8a equivale al build `1` de `pubspec.yaml`).
  static int normalizeVersionCode(int code) {
    if (code >= 1000 && code < 5000) {
      return code % 1000;
    }
    return code;
  }

  /// Compara dos `versionName` semánticos (ej. `1.1.0` vs `1.0.0`).
  static int compareVersionNames(String? a, String? b) {
    if (a == null || b == null || a.isEmpty || b.isEmpty) return 0;
    final cleanA = a.replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    final cleanB = b.replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    final partsA = cleanA
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final partsB = cleanB
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final len = partsA.length > partsB.length ? partsA.length : partsB.length;
    for (var i = 0; i < len; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  /// Versión instalada en el dispositivo.
  Future<({int versionCode, String versionName, int lastUpdateTime})>
      installedVersion() async {
    return DeviceChannel.getInstalledVersion();
  }

  /// Comprueba si hay una versión nueva en el repositorio.
  Future<({UpdateCheckResult result, AppUpdateInfo? info})> check({
    bool deep = false,
    void Function(int received, int total)? onDownloadProgress,
  }) async {
    try {
      final installed = await installedVersion();

      // 1) Consultar tanto el manifiesto latest.json como la API de Releases
      //    de GitHub para obtener la versión más reciente disponible.
      AppUpdateInfo? manifest;
      try {
        manifest = await _fetchManifest();
      } catch (_) {
        manifest = null;
      }

      AppUpdateInfo? ghRelease;
      try {
        ghRelease = await _fetchGithubRelease();
      } catch (_) {
        ghRelease = null;
      }

      final candidate = _pickBestCandidate(manifest, ghRelease);
      if (candidate != null) {
        if (_isNewer(candidate, installed)) {
          return (result: UpdateCheckResult.updateAvailable, info: candidate);
        }
        if (!deep) {
          return (result: UpdateCheckResult.upToDate, info: null);
        }
      }

      // 2) Comprobación profunda (plan B si no hubo manifiesto ni API):
      if (!deep) {
        return (
          result: candidate != null
              ? UpdateCheckResult.upToDate
              : UpdateCheckResult.failed,
          info: null,
        );
      }

      final downloadUrl = candidate?.url.isNotEmpty == true
          ? candidate!.url
          : AppConfig.updateApkUrl;
      final file = await download(
        AppUpdateInfo(versionCode: 0, url: downloadUrl),
        onProgress: onDownloadProgress,
      );
      final apkVersion = await DeviceChannel.getApkVersion(file.path);
      final info = AppUpdateInfo(
        versionCode: apkVersion.versionCode,
        versionName: apkVersion.versionName.isNotEmpty
            ? apkVersion.versionName
            : candidate?.versionName,
        url: downloadUrl,
        notes: candidate?.notes,
        changes: candidate?.changes ?? const [],
        sizeMb: candidate?.sizeMb,
        publishedAt: candidate?.publishedAt,
        localPath: file.path,
      );
      if (_isNewer(info, installed)) {
        return (result: UpdateCheckResult.updateAvailable, info: info);
      }
      return (result: UpdateCheckResult.upToDate, info: null);
    } catch (_) {
      return (result: UpdateCheckResult.failed, info: null);
    }
  }

  bool _isNewer(
    AppUpdateInfo remote,
    ({int versionCode, String versionName, int lastUpdateTime}) installed,
  ) {
    final remoteNorm = normalizeVersionCode(remote.versionCode);
    final installedNorm = normalizeVersionCode(installed.versionCode);

    // 1) Si el versionCode normalizado del repo es mayor.
    if (remoteNorm > 0 && installedNorm > 0 && remoteNorm > installedNorm) {
      return true;
    }

    // 2) Si el versionName semántico es mayor (ej. 1.1.0 > 1.0.0).
    final nameCmp = compareVersionNames(
      remote.versionName,
      installed.versionName,
    );
    if (nameCmp > 0) {
      return true;
    }

    // 3) Si el repo publicó un nuevo release en la etiqueta rodante `latest`
    //    después de la fecha en que se instaló el APK actual (con margen de 2 min),
    //    aunque no se haya incrementado manualmente el número en pubspec.yaml.
    if (remoteNorm >= installedNorm &&
        nameCmp >= 0 &&
        remote.publishedAt != null &&
        installed.lastUpdateTime > 0) {
      final publishedDate = DateTime.tryParse(remote.publishedAt!);
      if (publishedDate != null) {
        final publishedMs = publishedDate.millisecondsSinceEpoch;
        if (publishedMs > installed.lastUpdateTime + 120000) {
          return true;
        }
      }
    }

    return false;
  }

  AppUpdateInfo? _pickBestCandidate(
    AppUpdateInfo? manifest,
    AppUpdateInfo? ghRelease,
  ) {
    if (manifest == null) return ghRelease;
    if (ghRelease == null) return manifest;

    final manifestNorm = normalizeVersionCode(manifest.versionCode);
    final ghNorm = normalizeVersionCode(ghRelease.versionCode);

    if (ghNorm > manifestNorm) return ghRelease;

    // Combinar cambios/notas si el release de GitHub tiene más detalles.
    final mergedChanges = <String>[
      ...manifest.changes,
      ...ghRelease.changes,
    ];
    final mergedNotes = [
      if (manifest.notes != null && manifest.notes!.isNotEmpty) manifest.notes!,
      if (ghRelease.notes != null &&
          ghRelease.notes!.isNotEmpty &&
          ghRelease.notes != manifest.notes)
        ghRelease.notes!,
    ].join('\n');

    return AppUpdateInfo(
      versionCode: manifest.versionCode,
      versionName: manifest.versionName ?? ghRelease.versionName,
      url: manifest.url.isNotEmpty ? manifest.url : ghRelease.url,
      notes: mergedNotes.isNotEmpty ? mergedNotes : manifest.notes,
      changes: mergedChanges,
      sizeMb: manifest.sizeMb ?? ghRelease.sizeMb,
      publishedAt: manifest.publishedAt ?? ghRelease.publishedAt,
    );
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

    final downloadUrl =
        '${info.url}${info.url.contains('?') ? '&' : '?'}t=${DateTime.now().millisecondsSinceEpoch}';

    await _dio.download(
      downloadUrl,
      target.path,
      onReceiveProgress: onProgress,
      options: Options(responseType: ResponseType.bytes),
    );
    return target;
  }

  /// Abre el instalador del sistema para instalar el APK descargado.
  Future<bool> install(File apk) async {
    return DeviceChannel.installApk(apk.path);
  }

  Future<AppUpdateInfo?> _fetchManifest() async {
    final baseUrl = AppConfig.updateManifestUrl;
    if (baseUrl.isEmpty) return null;

    final url =
        '$baseUrl${baseUrl.contains('?') ? '&' : '?'}t=${DateTime.now().millisecondsSinceEpoch}';

    final response = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
      ),
    );
    final raw = response.data;
    if (raw == null || raw.trim().isEmpty) return null;

    final decoded = jsonDecode(raw);
    final data = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (data.isEmpty) return null;

    final payload = data['update'] is Map
        ? Map<String, dynamic>.from(data['update'] as Map)
        : data;
    final info = AppUpdateInfo.fromJson(payload);
    if (info.versionCode <= 0 || info.url.isEmpty) return null;
    return info.url.contains(_latestDownload)
        ? AppUpdateInfo(
            versionCode: info.versionCode,
            versionName: info.versionName,
            url: info.url.replaceFirst(_latestDownload, _tagDownload),
            notes: info.notes,
            changes: info.changes,
            sizeMb: info.sizeMb,
            publishedAt: info.publishedAt,
          )
        : info;
  }

  /// Consulta la API de Releases de GitHub como respaldo y para enriquecer
  /// las notas de la versión.
  Future<AppUpdateInfo?> _fetchGithubRelease() async {
    final apiUrl = AppConfig.updateReleasesApiUrl;
    if (apiUrl.isEmpty) return null;

    final response = await _dio.get<String>(
      '$apiUrl?per_page=5&t=${DateTime.now().millisecondsSinceEpoch}',
      options: Options(
        responseType: ResponseType.plain,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'Cache-Control': 'no-cache',
        },
      ),
    );
    final raw = response.data;
    if (raw == null || raw.trim().isEmpty) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.isEmpty) return null;

    Map<String, dynamic>? chosen;
    for (final item in decoded) {
      if (item is! Map) continue;
      if (item['draft'] == true) continue;
      chosen = Map<String, dynamic>.from(item);
      break;
    }
    if (chosen == null) return null;

    String apkUrl = AppConfig.updateApkUrl;
    double? sizeMb;
    final assets = chosen['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name']?.toString() ?? '';
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url']?.toString() ?? apkUrl;
          final sizeBytes = (asset['size'] as num?)?.toDouble();
          if (sizeBytes != null && sizeBytes > 0) {
            sizeMb = double.parse((sizeBytes / 1048576).toStringAsFixed(1));
          }
          break;
        }
      }
    }

    final tagName = chosen['tag_name']?.toString() ?? '';
    final title = chosen['name']?.toString() ?? '';
    final body = chosen['body']?.toString() ?? '';
    final publishedAt = chosen['published_at']?.toString();

    String? versionName;
    final verMatch = RegExp(r'v?(\d+\.\d+\.\d+)').firstMatch('$tagName $title');
    if (verMatch != null) {
      versionName = verMatch.group(1);
    }

    return AppUpdateInfo(
      versionCode: 1,
      versionName: versionName,
      url: apkUrl,
      notes: body,
      sizeMb: sizeMb,
      publishedAt: publishedAt,
    );
  }

  static const String _latestDownload = '/releases/latest/download/';
  static const String _tagDownload = '/releases/download/latest/';

  Future<Directory> _cacheDir() async {
    final path = await DeviceChannel.cacheDirectory();
    return Directory(path);
  }
}
