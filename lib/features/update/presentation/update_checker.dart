import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/device_channel.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/update/app_update_service.dart';
import '../../../core/update/update_providers.dart';

/// Aviso de versión nueva y autoactualización.
///
/// Se monta por encima del Navigator (en el `builder` de `MaterialApp.router`),
/// por eso el aviso **no** se pierde cuando go_router refresca las páginas
/// (por ejemplo, al restaurar la sesión).
///
/// - Al abrir la app comprueba el manifiesto de versión (≈1 KB).
/// - Si hay una versión nueva muestra una banda superior con el aviso.
/// - Al pulsar "Actualizar" descarga el APK y abre el instalador del sistema.
class UpdateChecker extends ConsumerStatefulWidget {
  const UpdateChecker({
    super.key,
    this.checkOnStart = true,
    this.deep = false,
    this.child,
  });

  /// Comprobar automáticamente al abrir la app.
  final bool checkOnStart;

  /// Descargar el APK para leer su versión (plan B, sin manifiesto).
  final bool deep;

  /// Contenido que envuelve (normalmente la app).
  final Widget? child;

  @override
  ConsumerState<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends ConsumerState<UpdateChecker> {
  AppUpdateInfo? _info;
  bool _checking = false;
  bool _downloading = false;
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.checkOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check(silent: true));
    }
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });

    final service = ref.read(appUpdateServiceProvider);
    final result = await service.check(deep: widget.deep);

    if (!mounted) return;
    setState(() => _checking = false);

    switch (result.result) {
      case UpdateCheckResult.updateAvailable:
        setState(() => _info = result.info);
      case UpdateCheckResult.upToDate:
        if (!silent) _toast('Ya tienes la última versión.');
      case UpdateCheckResult.failed:
        if (!silent) _toast('No se pudo comprobar si hay actualizaciones.');
    }
  }

  /// Muestra el aviso de una versión concreta (usado por "Buscar
  /// actualizaciones" en Configuración).
  void _showInfo(AppUpdateInfo info) => setState(() => _info = info);

  /// Oculta el aviso.
  void _dismiss() => setState(() => _info = null);

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Lanza la descarga de la actualización.
  void _startDownload() {
    if (_info != null) _downloadAndInstall();
  }

  Future<void> _downloadAndInstall() async {
    final info = _info;
    if (info == null) return;

    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });

    try {
      final service = ref.read(appUpdateServiceProvider);
      final file = (info.isDownloaded && info.localPath != null)
          ? File(info.localPath!)
          : await service.download(
              info,
              onProgress: (received, total) {
                if (!mounted) return;
                setState(() {
                  _progress = total > 0 ? received / total : 0;
                });
              },
            );

      final installed = await service.install(file);
      if (!mounted) return;
      if (!installed) {
        setState(() {
          _downloading = false;
          _error =
              'Permite las instalaciones desde Ajustes → Apps → QvaTube → '
              '"Instalar apps desconocidas" y vuelve a intentarlo.';
        });
        return;
      }
      setState(() => _downloading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = 'No se pudo descargar la actualización. Revisa tu conexión.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;

    return Stack(
      children: [
        widget.child ?? const SizedBox.shrink(),
        if (info != null) _UpdateBanner(info: info),
        if (_downloading) _DownloadOverlay(progress: _progress, error: _error),
      ],
    );
  }
}

/// Banda superior con el aviso de versión nueva.
class _UpdateBanner extends ConsumerStatefulWidget {
  const _UpdateBanner({required this.info});

  final AppUpdateInfo info;

  @override
  ConsumerState<_UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<_UpdateBanner> {
  @override
  Widget build(BuildContext context) {
    final info = widget.info;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          color: AppColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppRadii.md),
          elevation: 8,
          shadowColor: Colors.black54,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: AppColors.accent),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.system_update,
                  color: AppColors.accent,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Nueva versión disponible'
                        '${info.versionName != null ? ' (${info.versionName})' : ''}',
                        style: AppTextStyles.body(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (info.notes != null && info.notes!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          info.notes!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final state = context
                        .findAncestorStateOfType<_UpdateCheckerState>();
                    state?._dismiss();
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Ahora no',
                    style: AppTextStyles.body(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: () => _startDownload(context),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    textStyle: AppTextStyles.body(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Text('Actualizar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _startDownload(BuildContext context) {
    final state = context.findAncestorStateOfType<_UpdateCheckerState>();
    state?._startDownload();
  }
}

/// Overlay de descarga (con el progreso) mientras se instala la actualización.
class _DownloadOverlay extends StatelessWidget {
  const _DownloadOverlay({this.progress, this.error});

  final double? progress;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.downloading,
                      color: AppColors.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Descargando la actualización',
                        style: AppTextStyles.body(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  progress == null
                      ? 'Preparando…'
                      : '${(progress! * 100).toStringAsFixed(0)} %',
                  style: AppTextStyles.body(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: AppTextStyles.body(
                      fontSize: 12,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Entrada de menú reutilizable (usada por Configuración).
class UpdateMenuEntry extends ConsumerStatefulWidget {
  const UpdateMenuEntry({super.key, this.deep = true});

  final bool deep;

  @override
  ConsumerState<UpdateMenuEntry> createState() => _UpdateMenuEntryState();
}

class _UpdateMenuEntryState extends ConsumerState<UpdateMenuEntry> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    final service = ref.read(appUpdateServiceProvider);
    final result = await service.check(deep: widget.deep);
    if (!mounted) return;
    setState(() => _checking = false);

    final messenger = ScaffoldMessenger.maybeOf(context);
    switch (result.result) {
      case UpdateCheckResult.updateAvailable:
        final info = result.info;
        if (info != null) {
          final state = context.findAncestorStateOfType<_UpdateCheckerState>();
          state?._showInfo(info);
        }
      case UpdateCheckResult.upToDate:
        messenger?.showSnackBar(
          const SnackBar(content: Text('Ya tienes la última versión.')),
        );
      case UpdateCheckResult.failed:
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('No se pudo comprobar si hay actualizaciones.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.system_update_alt,
            size: 20,
            color: AppColors.accent,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Buscar actualizaciones',
                  style: AppTextStyles.body(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _checking
                      ? 'Comprobando…'
                      : 'Ver si hay una versión más reciente',
                  style: AppTextStyles.body(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _checking ? null : _check,
            icon: const Icon(Icons.chevron_right),
            iconSize: 20,
            color: AppColors.textMuted,
          ),
        ],
      ),
    );
  }
}

/// Diálogo informativo con la versión instalada.
Future<void> showAppVersionDialog(
  BuildContext context, {
  ({int versionCode, String versionName})? installedVersion,
  bool justUpdated = false,
}) async {
  final version =
      installedVersion ?? await AppUpdateService().installedVersion();
  if (!context.mounted) return;

  final versionLabel = version.versionName.isEmpty
      ? 'la versión ${version.versionCode}'
      : 'la versión ${version.versionName}';
  final installedLabel = version.versionName.isEmpty
      ? 'Versión instalada: ${version.versionCode}'
      : 'Versión instalada: ${version.versionName} '
            '(${version.versionCode})';
  final title = justUpdated
      ? 'QvaTube actualizado'
      : version.versionName.isEmpty
      ? 'QvaTube'
      : 'QvaTube ${version.versionName}';

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      title: Text(title, style: Theme.of(context).textTheme.displaySmall),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (justUpdated) ...[
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'La app se actualizó a $versionLabel.',
                    style: AppTextStyles.body(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          Text(
            installedLabel,
            style: AppTextStyles.body(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            DeviceChannel.openUrl(
              'https://github.com/R0ger0l1va/qvatube_apk/releases/latest',
            );
          },
          child: Text(justUpdated ? 'Ver novedades' : 'Ver releases'),
        ),
      ],
    ),
  );
}
