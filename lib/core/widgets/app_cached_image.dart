import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../platform/device_channel.dart';
import '../theme/app_colors.dart';

/// Servicio de caché local para imágenes de red (portadas, pósters, avatares).
///
/// Descarga la imagen una sola vez usando `HttpClient` de Dart y la almacena
/// en el almacenamiento en disco de la app (`cacheDir/image_cache/`).
/// En las siguientes lecturas, carga directamente el archivo local desde disco,
/// ahorrando datos móviles (megas) y permitiendo funcionamiento offline.
abstract final class AppImageCache {
  static Directory? _cacheDir;
  static final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  /// Inicializa el directorio de caché de imágenes.
  static Future<Directory> get cacheDirectory async {
    if (_cacheDir != null) return _cacheDir!;
    final base = await DeviceChannel.cacheDirectory();
    final dir = Directory('$base/image_cache');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// Genera un nombre de archivo seguro basado en el hash o sanitización de la URL.
  static String _fileNameForUrl(String url) {
    // Generar nombre determinista y único sin caracteres inválidos de ruta
    final hash = url.hashCode.toRadixString(16);
    final clean = url
        .replaceAll(RegExp(r'https?://'), '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final suffix = clean.length > 40
        ? clean.substring(clean.length - 40)
        : clean;
    return 'img_${hash}_$suffix';
  }

  /// Obtiene el archivo local en caché si existe y no está vacío.
  static Future<File?> getCachedFile(String url) async {
    if (url.isEmpty || kIsWeb) return null;
    try {
      final dir = await cacheDirectory;
      final file = File('${dir.path}/${_fileNameForUrl(url)}');
      if (file.existsSync() && file.lengthSync() > 0) {
        return file;
      }
    } catch (_) {
      // Ignorar fallos de acceso a disco
    }
    return null;
  }

  /// Descarga y guarda la imagen en disco de forma atómica.
  static Future<File?> downloadAndCache(String url) async {
    if (url.isEmpty || kIsWeb) return null;
    try {
      final dir = await cacheDirectory;
      final file = File('${dir.path}/${_fileNameForUrl(url)}');
      if (file.existsSync() && file.lengthSync() > 0) {
        return file;
      }

      final uri = Uri.tryParse(url);
      if (uri == null) return null;

      final request = await _httpClient.getUrl(uri);
      final response = await request.close();
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final tempFile = File('${file.path}.tmp');
        final sink = tempFile.openWrite();
        await response.pipe(sink);
        await sink.close();

        if (tempFile.existsSync() && tempFile.lengthSync() > 0) {
          if (file.existsSync()) file.deleteSync();
          await tempFile.rename(file.path);
          return file;
        }
      }
    } catch (_) {
      // Si falla la descarga, retorna null para que el widget maneje fallback
    }
    return null;
  }
}

/// Widget para mostrar imágenes de red con almacenamiento en caché persistente en disco.
///
/// Si la imagen ya fue descargada anteriormente, se muestra instantáneamente desde
/// el almacenamiento local sin gastar datos móviles ni conexión de red.
class AppCachedImage extends StatefulWidget {
  const AppCachedImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  State<AppCachedImage> createState() => _AppCachedImageState();
}

class _AppCachedImageState extends State<AppCachedImage> {
  File? _localFile;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant AppCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (widget.imageUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _localFile = null;
          _isLoading = false;
          _hasError = true;
        });
      }
      return;
    }

    if (widget.imageUrl.startsWith('file://')) {
      final file = File(Uri.parse(widget.imageUrl).toFilePath());
      final exists = file.existsSync() && file.lengthSync() > 0;
      if (mounted) {
        setState(() {
          _localFile = exists ? file : null;
          _isLoading = false;
          _hasError = !exists;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    // 1. Revisar si ya existe en caché local
    final cached = await AppImageCache.getCachedFile(widget.imageUrl);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _localFile = cached;
          _isLoading = false;
          _hasError = false;
        });
      }
      return;
    }

    // 2. Si no existe, descargar y almacenar en caché
    final downloaded = await AppImageCache.downloadAndCache(widget.imageUrl);
    if (!mounted) return;

    if (downloaded != null && downloaded.existsSync()) {
      setState(() {
        _localFile = downloaded;
        _isLoading = false;
        _hasError = false;
      });
    } else {
      // Fallback: intentar Image.network nativo directamente
      setState(() {
        _localFile = null;
        _isLoading = false;
        _hasError = false; // Se delega al errorBuilder de Image.network
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_isLoading) {
      content =
          widget.placeholder ??
          Container(
            color: AppColors.surfaceSecondary,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
            ),
          );
    } else if (_hasError) {
      content =
          widget.errorWidget ??
          Container(
            color: AppColors.surfaceSecondary,
            child: const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: AppColors.textMuted,
                size: 24,
              ),
            ),
          );
    } else if (_localFile != null && _localFile!.existsSync()) {
      content = Image.file(
        _localFile!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (context, error, stackTrace) =>
            widget.errorWidget ??
            Container(
              color: AppColors.surfaceSecondary,
              child: const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.textMuted,
                  size: 24,
                ),
              ),
            ),
      );
    } else {
      // Fallback directo a Image.network
      content = Image.network(
        widget.imageUrl,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (context, error, stackTrace) =>
            widget.errorWidget ??
            Container(
              color: AppColors.surfaceSecondary,
              child: const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.textMuted,
                  size: 24,
                ),
              ),
            ),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return widget.placeholder ??
              Container(
                color: AppColors.surfaceSecondary,
                child: const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ),
              );
        },
      );
    }

    if (widget.borderRadius != null) {
      content = ClipRRect(borderRadius: widget.borderRadius!, child: content);
    }

    if (widget.width != null || widget.height != null) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: content,
      );
    }

    return content;
  }
}
