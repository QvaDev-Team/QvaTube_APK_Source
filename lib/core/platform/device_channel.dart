import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Puente con el canal nativo `qvatube/device` (MainActivity.kt).
///
/// - `pickImage()`: abre la galería y devuelve la ruta local de la imagen
///   (usada por `POST /api/auth/avatar`).
/// - `openUrl(url)`: abre un enlace externo (bot de Telegram, WhatsApp).
///
/// En escritorio (Windows, Linux, macOS) no hay canal nativo propio: abrir
/// enlaces, elegir imágenes y leer la versión se resuelven aquí en Dart; lo
/// exclusivo de Android (APK, parches, icono, WorkManager, PdfRenderer) se
/// omite o devuelve "no disponible".
abstract final class DeviceChannel {
  const DeviceChannel._();

  static const MethodChannel _channel = MethodChannel('qvatube/device');
  static bool _handlerInitialized = false;
  static void Function(String action, int? positionMs)? _mediaActionListener;
  static void Function()? _updateTapListener;

  /// Registra el listener que recibe acciones desde la barra de notificaciones
  /// multimedia (`playPause`, `next`, `previous`, `stop`, `seek`).
  static void setMediaActionListener(
    void Function(String action, int? positionMs)? listener,
  ) {
    _mediaActionListener = listener;
    _ensureHandler();
  }

  /// Registra quién reacciona al tocar la notificación de "nueva versión"
  /// con la app ya abierta (el aviso de actualización vuelve a comprobar).
  static void setUpdateNotificationTapListener(void Function()? listener) {
    _updateTapListener = listener;
    _ensureHandler();
  }

  static void Function()? _shareStopListener;

  /// "Dejar de compartir" desde la notificación de Compartir por Wi-Fi.
  static void setShareStopListener(void Function()? listener) {
    _shareStopListener = listener;
    _ensureHandler();
  }

  /// Notificación fija mientras se comparte por Wi-Fi ([on] false la quita).
  static Future<void> shareNotification({
    required bool on,
    String? network,
    String? text,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('shareNotification', {
        'on': on,
        'network': network,
        'text': text,
      });
    } on PlatformException {
      // ignorar
    } on MissingPluginException {
      // ignorar
    }
  }

  static void _ensureHandler() {
    if (!_handlerInitialized) {
      _handlerInitialized = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onUpdateNotificationTap') {
          _updateTapListener?.call();
        } else if (call.method == 'onShareStop') {
          _shareStopListener?.call();
        } else if (call.method == 'onMediaAction') {
          final args = call.arguments;
          if (args is Map) {
            final action = args['action']?.toString() ?? '';
            final pos = (args['positionMs'] as num?)?.toInt();
            _mediaActionListener?.call(action, pos);
          }
        }
      });
    }
  }

  /// Activa el icono del launcher de [season] (`default`, `halloween`…).
  /// `true` si quedó aplicado (también si ya lo estaba).
  static Future<bool> applyLauncherIcon(String season) async {
    if (!Platform.isAndroid) return false;
    try {
      await _channel.invokeMethod<bool>('applyLauncherIcon', {
        'season': season,
      });
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Quita la comprobación periódica de actualizaciones: con push, el aviso
  /// llega por FCM y así no sale dos veces.
  static Future<void> cancelUpdateCheck() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('cancelUpdateCheck');
    } on PlatformException {
      // ignorar
    } on MissingPluginException {
      // ignorar
    }
  }

  /// Abre el menú "Compartir" de Android con [text]. `false` si no se pudo.
  static Future<bool> shareText(String text) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('shareText', {'text': text}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Abre un PDF con el `PdfRenderer` de Android y devuelve el tamaño
  /// (ancho, alto en puntos) de cada página.
  static Future<List<Size>> pdfOpen(String path) async {
    final pages = await _channel.invokeListMethod<dynamic>('pdfOpen', {
      'path': path,
    });
    return [
      for (final p in pages ?? const [])
        Size((p[0] as num).toDouble(), (p[1] as num).toDouble()),
    ];
  }

  /// Dibuja una página del PDF abierto con [pdfOpen] (PNG de [width] px).
  static Future<Uint8List?> pdfRenderPage(int index, int width) {
    return _channel.invokeMethod<Uint8List>('pdfRenderPage', {
      'index': index,
      'width': width,
    });
  }

  static Future<void> pdfClose() async {
    try {
      await _channel.invokeMethod<bool>('pdfClose');
    } on PlatformException {
      // ignorar
    }
  }

  /// Programa en Android la comprobación periódica de actualizaciones en
  /// segundo plano (WorkManager), que avisa con una notificación.
  static Future<void> scheduleUpdateCheck(String manifestUrl) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('scheduleUpdateCheck', {
        'manifestUrl': manifestUrl,
      });
    } on PlatformException {
      // sin WorkManager no hay aviso en segundo plano; el banner sigue igual
    } on MissingPluginException {
      // ignorar
    }
  }

  /// Actualiza o muestra los controles del reproductor en la barra de
  /// notificaciones del sistema y en la pantalla de bloqueo.
  static Future<void> updateMediaNotification({
    required String title,
    String? subtitle,
    required bool isPlaying,
    bool hasNext = false,
    bool hasPrevious = false,
    int positionMs = 0,
    int durationMs = 0,
    String? artworkUrl,
  }) async {
    try {
      await _channel.invokeMethod<bool>('updateMediaNotification', {
        'artworkUrl': artworkUrl ?? '',
        'title': title,
        'subtitle': subtitle ?? '',
        'isPlaying': isPlaying,
        'hasNext': hasNext,
        'hasPrevious': hasPrevious,
        'positionMs': positionMs,
        'durationMs': durationMs,
      });
    } on PlatformException {
      // ignorar en plataformas no compatibles
    } on MissingPluginException {
      // ignorar en plataformas no compatibles
    }
  }

  /// Mantiene la pantalla encendida (`true`) mientras se ve un video, o
  /// devuelve el comportamiento normal (`false`). Solo Android.
  /// Compartir por Wi-Fi: deja pasar los anuncios UDP de la red. Solo
  /// Android.
  // ── Compartir por Wi-Fi: punto de acceso local + conexión por QR ──────

  /// Pide el permiso para crear el punto de acceso (ubicación hasta
  /// Android 12, "Dispositivos cercanos" desde Android 13).
  static Future<bool> shareHotspotPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('shareHotspotPermission') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Crea el punto de acceso local. `ssid`/`password` o `error`
  /// (`permission`, `location_off`, `unsupported`, `failed_N`).
  static Future<({String? ssid, String? password, String? error})>
  startShareHotspot() async {
    if (!Platform.isAndroid) {
      return (ssid: null, password: null, error: 'unsupported');
    }
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>(
        'startShareHotspot',
      );
      return (
        ssid: r?['ssid'] as String?,
        password: r?['password'] as String?,
        error: r?['error'] as String?,
      );
    } on PlatformException catch (e) {
      return (ssid: null, password: null, error: e.message ?? 'error');
    } on MissingPluginException {
      return (ssid: null, password: null, error: 'unsupported');
    }
  }

  static Future<void> stopShareHotspot() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('stopShareHotspot');
    } on PlatformException {
      // ignorar
    } on MissingPluginException {
      // ignorar
    }
  }

  /// Se conecta a la red Wi-Fi del QR. `connected`, `unavailable`
  /// (el usuario no aceptó o no está cerca), `unsupported` (< Android 10).
  static Future<String> connectShareWifi(String ssid, String password) async {
    if (!Platform.isAndroid) return 'unsupported';
    try {
      return await _channel.invokeMethod<String>('connectShareWifi', {
            'ssid': ssid,
            'password': password,
          }) ??
          'error';
    } on PlatformException {
      return 'error';
    } on MissingPluginException {
      return 'unsupported';
    }
  }

  static Future<void> disconnectShareWifi() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('disconnectShareWifi');
    } on PlatformException {
      // ignorar
    } on MissingPluginException {
      // ignorar
    }
  }

  static Future<void> wifiMulticastLock(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('wifiMulticastLock', {'on': on});
    } on PlatformException {
      // ignorar
    } on MissingPluginException {
      // ignorar
    }
  }

  static Future<void> setKeepScreenOn(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('setKeepScreenOn', {'on': on});
    } on PlatformException {
      // ignorar
    } on MissingPluginException {
      // ignorar
    }
  }

  /// Progreso de las descargas de Telegram en la notificación (y servicio
  /// en primer plano para que sigan con la app cerrada). Solo Android.
  static Future<void> telegramDownloadProgress({
    required int percent,
    String? title,
    String? text,
  }) => _invokeAndroid('telegramDownloadProgress', {
    'percent': percent,
    'title': title,
    'text': text,
  });

  /// Quita la notificación de progreso de Telegram.
  static Future<void> telegramDownloadStop() =>
      _invokeAndroid('telegramDownloadStop');

  /// Aviso "Descarga lista" de un archivo de Telegram.
  static Future<void> telegramDownloadDone(String title) =>
      _invokeAndroid('telegramDownloadDone', {'title': title});

  /// Oculta la notificación de reproducción multimedia.
  static Future<void> clearMediaNotification() async {
    try {
      await _channel.invokeMethod<bool>('clearMediaNotification');
    } on PlatformException {
      // ignorar
    } on MissingPluginException {
      // ignorar
    }
  }

  /// `true` en un televisor (Google TV / Android TV), que se maneja con el
  /// mando. Se rellena con [detectTelevision] al arrancar.
  static bool isTelevision = false;

  /// Pregunta a Android si es un televisor y guarda el resultado en
  /// [isTelevision].
  static Future<bool> detectTelevision() async {
    if (!Platform.isAndroid) return false;
    try {
      isTelevision = await _channel.invokeMethod<bool>('isTelevision') ?? false;
    } on PlatformException {
      isTelevision = false;
    } on MissingPluginException {
      isTelevision = false;
    }
    return isTelevision;
  }

  /// `true` en Windows, Linux y macOS.
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// Devuelve la ruta local de la imagen elegida, o `null` si el usuario
  /// cancela la selección.
  static Future<String?> pickImage() async {
    if (isDesktop) {
      const images = XTypeGroup(
        label: 'Imágenes',
        extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'heic'],
        uniformTypeIdentifiers: ['public.image'],
      );
      try {
        final file = await openFile(acceptedTypeGroups: const [images]);
        return file?.path;
      } catch (_) {
        return null;
      }
    }
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
    if (isDesktop) {
      try {
        final info = await PackageInfo.fromPlatform();
        return (
          versionCode: int.tryParse(info.buildNumber) ?? 0,
          versionName: info.version,
          lastUpdateTime: 0,
        );
      } catch (_) {
        return (versionCode: 0, versionName: '', lastUpdateTime: 0);
      }
    }
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

  /// Arranca el servicio en primer plano que mantiene viva la descarga de
  /// una actualización aunque el usuario salga de la app (con su
  /// notificación de progreso).
  static Future<void> startUpdateDownload({String? text}) =>
      _invokeAndroid('startUpdateDownload', {'text': text});

  /// Progreso de la descarga en la notificación (`percent` 0-100, o `null`
  /// para la barra indeterminada).
  static Future<void> updateDownloadProgress({int? percent, String? text}) =>
      _invokeAndroid('updateDownloadProgress', {
        'percent': percent ?? -1,
        'text': text,
      });

  /// Para el servicio de descarga y quita su notificación.
  static Future<void> stopUpdateDownload() =>
      _invokeAndroid('stopUpdateDownload');

  /// Avisa con una notificación de que la actualización ya se descargó; al
  /// tocarla se abre la app con el instalador.
  static Future<void> notifyUpdateReady({
    required String path,
    String? versionName,
  }) => _invokeAndroid('notifyUpdateReady', {
    'path': path,
    'versionName': versionName,
  });

  /// Avisa con una notificación de que la descarga falló.
  static Future<void> notifyUpdateFailed() =>
      _invokeAndroid('notifyUpdateFailed');

  static Future<void> _invokeAndroid(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<Object?>(method, args);
    } on PlatformException {
      // La notificación es un extra: la descarga sigue igual.
    } on MissingPluginException {
      // ignorar
    }
  }

  /// Ruta del APK instalado (`applicationInfo.sourceDir`), base de los
  /// parches de actualización diferencial. `null` si no está disponible.
  static Future<String?> installedApkPath() async {
    try {
      final path = await _channel.invokeMethod<String>('getInstalledApkPath');
      return path == null || path.isEmpty ? null : path;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Carpeta de datos de la app en escritorio (no la temporal: ahí van la
  /// sesión de Telegram, las descargas y lo recibido por Wi-Fi, que el
  /// sistema podría borrar).
  ///   Windows: %APPDATA%\QvaTube · Linux: ~/.local/share/QvaTube
  ///   macOS: ~/Library/Application Support/QvaTube
  static String? _desktopDataDir;

  static String? desktopDataDirectory() {
    if (!isDesktop) return null;
    final cached = _desktopDataDir;
    if (cached != null) return cached;
    final env = Platform.environment;
    String? base;
    if (Platform.isWindows) {
      base = env['APPDATA'] ?? env['LOCALAPPDATA'];
      if (base != null) base = '$base\\QvaTube';
    } else if (Platform.isMacOS) {
      final home = env['HOME'];
      if (home != null) base = '$home/Library/Application Support/QvaTube';
    } else {
      final xdg = env['XDG_DATA_HOME'];
      final home = env['HOME'];
      if (xdg != null && xdg.isNotEmpty) {
        base = '$xdg/QvaTube';
      } else if (home != null) {
        base = '$home/.local/share/QvaTube';
      }
    }
    if (base == null) return null;
    try {
      Directory(base).createSync(recursive: true);
    } catch (_) {
      return null;
    }
    return _desktopDataDir = base;
  }

  /// Carpeta de caché de la app (donde se descargan las actualizaciones).
  static Future<String> cacheDirectory() async {
    final desktop = desktopDataDirectory();
    if (desktop != null) return desktop;
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

  /// Lugares donde el gestor de descargas puede guardar los archivos: la
  /// memoria interna y cada tarjeta SD montada (Android). Lista vacía en
  /// escritorio o si no se pudo consultar.
  static Future<List<StorageVolume>> storageVolumes() async {
    if (!Platform.isAndroid) return const [];
    try {
      final list = await _channel.invokeListMethod<Object?>('storageVolumes');
      return [
        for (final e in list ?? const [])
          if (e is Map) StorageVolume.fromMap(Map<String, Object?>.from(e)),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Cierra y vuelve a abrir la app (Android). `false` si no se pudo.
  static Future<bool> restartApp() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('restartApp') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Abre una URL (o un archivo local) con la aplicación del sistema.
  static Future<bool> openUrl(String url) async {
    if (isDesktop) return _openWithSystem(url);
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Escritorio: abre [target] (URL o ruta de archivo) con el programa
  /// predeterminado: `xdg-open` (Linux), `open` (macOS) o el shell de
  /// Windows (`rundll32 url.dll`, que no pasa por `cmd` y así no interpreta
  /// los `&` de las URL).
  static Future<bool> _openWithSystem(String target) async {
    try {
      final ProcessResult result;
      if (Platform.isWindows) {
        result = await Process.run('rundll32', [
          'url.dll,FileProtocolHandler',
          target,
        ]);
      } else if (Platform.isMacOS) {
        result = await Process.run('open', [target]);
      } else {
        result = await Process.run('xdg-open', [target]);
      }
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

/// Un almacenamiento del teléfono (memoria interna o tarjeta SD).
@immutable
class StorageVolume {
  const StorageVolume({
    required this.id,
    required this.path,
    required this.label,
    required this.removable,
    required this.freeBytes,
    required this.totalBytes,
  });

  factory StorageVolume.fromMap(Map<String, Object?> m) => StorageVolume(
    id: m['id']?.toString() ?? '',
    path: m['path']?.toString() ?? '',
    label: m['label']?.toString() ?? '',
    removable: m['removable'] == true,
    freeBytes: (m['freeBytes'] as num?)?.toInt() ?? 0,
    totalBytes: (m['totalBytes'] as num?)?.toInt() ?? 0,
  );

  /// `internal`, `sd1`, `sd2`…
  final String id;

  /// Carpeta de la app en ese almacenamiento (sin permisos extra).
  final String path;
  final String label;
  final bool removable;
  final int freeBytes;
  final int totalBytes;
}
