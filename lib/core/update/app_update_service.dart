import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../platform/device_channel.dart';
import 'bspatch.dart';

/// Parche diferencial (BSDIFF40) publicado junto a una versión.
///
/// Reconstruye el APK nuevo a partir del APK instalado cuyo SHA-256 es
/// [fromSha256]; así no hace falta volver a bajar el APK completo.
class UpdatePatch {
  const UpdatePatch({
    required this.fromSha256,
    required this.url,
    this.fromVersionCode,
    this.sizeBytes,
    this.sha256,
  });

  factory UpdatePatch.fromJson(Map<String, dynamic> json) {
    return UpdatePatch(
      fromSha256: json['from_sha256']?.toString().toLowerCase() ?? '',
      url: json['url']?.toString() ?? '',
      fromVersionCode: (json['from_version_code'] as num?)?.toInt(),
      sizeBytes: (json['size_bytes'] as num?)?.toInt(),
      sha256: json['sha256']?.toString().toLowerCase(),
    );
  }

  /// SHA-256 del APK de origen (el que tiene que estar instalado).
  final String fromSha256;
  final String url;
  final int? fromVersionCode;
  final int? sizeBytes;

  /// SHA-256 del propio archivo de parche.
  final String? sha256;

  double? get sizeMb => sizeBytes == null
      ? null
      : double.parse((sizeBytes! / 1048576).toStringAsFixed(1));

  UpdatePatch withUrl(String newUrl) => UpdatePatch(
    fromSha256: fromSha256,
    url: newUrl,
    fromVersionCode: fromVersionCode,
    sizeBytes: sizeBytes,
    sha256: sha256,
  );
}

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
    this.sha256,
    this.patches = const [],
    this.applicablePatch,
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
    final rawPatches = json['patches'];

    return AppUpdateInfo(
      versionCode: (json['version_code'] as num?)?.toInt() ?? 0,
      versionName: json['version_name']?.toString(),
      url: json['url']?.toString() ?? '',
      notes: json['notes']?.toString(),
      changes: parsedChanges,
      sizeMb: (json['size_mb'] as num?)?.toDouble(),
      publishedAt: json['published_at']?.toString(),
      sha256: json['sha256']?.toString().toLowerCase(),
      patches: rawPatches is List
          ? rawPatches
                .whereType<Map>()
                .map((e) => UpdatePatch.fromJson(Map<String, dynamic>.from(e)))
                .where((p) => p.fromSha256.isNotEmpty && p.url.isNotEmpty)
                .toList()
          : const [],
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

  /// SHA-256 del APK completo; se verifica antes de instalar.
  final String? sha256;

  /// Parches diferenciales disponibles (uno por versión de origen).
  final List<UpdatePatch> patches;

  /// Parche que encaja con el APK instalado en este dispositivo, si hay.
  final UpdatePatch? applicablePatch;

  bool get isDownloaded => localPath != null;

  /// Megas que de verdad se van a descargar (parche o APK completo).
  double? get downloadSizeMb => applicablePatch?.sizeMb ?? sizeMb;

  AppUpdateInfo copyWith({
    int? versionCode,
    String? url,
    String? versionName,
    String? notes,
    List<String>? changes,
    double? sizeMb,
    String? publishedAt,
    String? localPath,
    UpdatePatch? applicablePatch,
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
      sha256: sha256,
      patches: patches,
      applicablePatch: applicablePatch ?? this.applicablePatch,
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
          return (
            result: UpdateCheckResult.updateAvailable,
            info: await _withApplicablePatch(candidate),
          );
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
      sha256: manifest.sha256,
      patches: manifest.patches,
    );
  }

  String? _installedSha256;

  /// SHA-256 del APK instalado (se calcula una vez por sesión, fuera del
  /// hilo de la interfaz).
  Future<String?> _installedApkSha256() async {
    final cached = _installedSha256;
    if (cached != null) return cached;
    final path = await DeviceChannel.installedApkPath();
    if (path == null) return null;
    try {
      final hash = await Isolate.run(
        () => sha256.convert(File(path).readAsBytesSync()).toString(),
      );
      _installedSha256 = hash;
      return hash;
    } catch (_) {
      return null;
    }
  }

  /// Busca, entre los parches publicados, el que parte exactamente del APK
  /// instalado. Si el APK local no coincide con ninguno (instalado desde otra
  /// fuente, build local…), se descargará el APK completo.
  Future<AppUpdateInfo> _withApplicablePatch(AppUpdateInfo info) async {
    if (info.patches.isEmpty || info.sha256 == null) return info;
    final installedHash = await _installedApkSha256();
    if (installedHash == null) return info;
    for (final patch in info.patches) {
      if (patch.fromSha256 == installedHash) {
        return info.copyWith(applicablePatch: patch);
      }
    }
    return info;
  }

  /// Descarga la actualización en la caché de la app.
  ///
  /// Si hay un parche diferencial para el APK instalado, baja solo el parche
  /// y reconstruye el APK nuevo localmente; si el parche falla por cualquier
  /// motivo (red, hash distinto, parche corrupto) cae a la descarga completa.
  /// [onStatus] informa de la fase actual para mostrarla en la interfaz.
  Future<File> download(
    AppUpdateInfo info, {
    void Function(int received, int total)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    final dir = Directory('${(await _cacheDir()).path}/updates');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final target = File('${dir.path}/qvatube-update.apk');
    if (target.existsSync()) {
      target.deleteSync();
    }

    final patch = info.applicablePatch;
    final expectedSha = info.sha256;
    if (patch != null && expectedSha != null) {
      try {
        onStatus?.call(
          'Descargando solo los cambios'
          '${patch.sizeMb != null ? ' (${patch.sizeMb!.toStringAsFixed(1)} MB)' : ''}',
        );
        await _downloadAndApplyPatch(
          patch,
          expectedSha: expectedSha,
          target: target,
          dir: dir,
          onProgress: onProgress,
          onStatus: onStatus,
        );
        return target;
      } catch (_) {
        if (target.existsSync()) target.deleteSync();
        onProgress?.call(0, 0);
      }
    }

    onStatus?.call('Descargando la actualización completa');
    await _dio.download(
      _noCache(info.url),
      target.path,
      onReceiveProgress: onProgress,
      options: Options(responseType: ResponseType.bytes),
    );
    if (expectedSha != null) {
      onStatus?.call('Verificando el archivo');
      final actual = await Isolate.run(
        () => sha256.convert(File(target.path).readAsBytesSync()).toString(),
      );
      if (actual != expectedSha) {
        target.deleteSync();
        throw const FileSystemException(
          'El APK descargado no coincide con la versión publicada',
        );
      }
    }
    return target;
  }

  Future<void> _downloadAndApplyPatch(
    UpdatePatch patch, {
    required String expectedSha,
    required File target,
    required Directory dir,
    void Function(int received, int total)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    final oldPath = await DeviceChannel.installedApkPath();
    if (oldPath == null) {
      throw const FileSystemException('No se encontró el APK instalado');
    }
    final patchFile = File('${dir.path}/qvatube-update.patch');
    if (patchFile.existsSync()) patchFile.deleteSync();

    try {
      await _dio.download(
        _noCache(patch.url),
        patchFile.path,
        onReceiveProgress: onProgress,
        options: Options(responseType: ResponseType.bytes),
      );

      onStatus?.call('Aplicando los cambios');
      final patchPath = patchFile.path;
      final targetPath = target.path;
      final patchSha = patch.sha256;
      await Isolate.run(() {
        final patchBytes = File(patchPath).readAsBytesSync();
        if (patchSha != null &&
            sha256.convert(patchBytes).toString() != patchSha) {
          throw const BsPatchException('El parche llegó incompleto');
        }
        final result = bspatch(File(oldPath).readAsBytesSync(), patchBytes);
        // El APK reconstruido tiene que ser idéntico (y por tanto estar
        // firmado con la misma clave) al publicado; si no, no se instala.
        if (sha256.convert(result).toString() != expectedSha) {
          throw const BsPatchException(
            'El APK reconstruido no coincide con la versión publicada',
          );
        }
        File(targetPath).writeAsBytesSync(result, flush: true);
      });
    } finally {
      if (patchFile.existsSync()) patchFile.deleteSync();
    }
  }

  String _noCache(String url) =>
      '$url${url.contains('?') ? '&' : '?'}t=${DateTime.now().millisecondsSinceEpoch}';

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
    String fixUrl(String url) => url.replaceFirst(_latestDownload, _tagDownload);
    return AppUpdateInfo(
      versionCode: info.versionCode,
      versionName: info.versionName,
      url: fixUrl(info.url),
      notes: info.notes,
      changes: info.changes,
      sizeMb: info.sizeMb,
      publishedAt: info.publishedAt,
      sha256: info.sha256,
      patches: [for (final p in info.patches) p.withUrl(fixUrl(p.url))],
    );
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
      // `apk-archive` guarda versiones viejas solo para generar parches.
      if (item['prerelease'] == true || item['tag_name'] == 'apk-archive') {
        continue;
      }
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
