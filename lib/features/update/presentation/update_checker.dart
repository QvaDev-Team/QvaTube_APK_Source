import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/device_channel.dart';
import '../../../core/router/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/update/app_update_service.dart';
import '../../../core/update/update_providers.dart';

/// Aviso de versión nueva y autoactualización.
///
/// Se monta por encima del Navigator (en el `builder` de `MaterialApp.router`),
/// por eso el aviso **no** se pierde cuando go_router refresca las páginas
/// (por ejemplo, al restaurar la sesión).
/// Página de la última release, donde están los instaladores de escritorio.
const String desktopReleasesUrl =
    'https://github.com/QvaDev-Team/QvaTube_APK/releases/tag/escritorio';

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

/// Vuelve a comprobar y, si hay versión nueva, muestra el banner (al tocar
/// la notificación push de actualización con la app ya abierta).
void recheckForUpdates() => _UpdateCheckerState._instance?._check(silent: true);

class _UpdateCheckerState extends ConsumerState<UpdateChecker>
    with WidgetsBindingObserver {
  static _UpdateCheckerState? _instance;

  AppUpdateInfo? _info;
  bool _checking = false;
  bool _downloading = false;
  double? _progress;
  String? _status;
  String? _error;

  /// La descarga sigue, pero el aviso grande está plegado en una píldora
  /// para poder seguir usando la app.
  bool _minimized = false;

  /// La actualización terminó de bajarse con la app en segundo plano y
  /// espera a que el usuario vuelva para instalarla.
  bool _readyToInstall = false;

  /// Último porcentaje enviado a la notificación (para no saturar el canal).
  int? _notifiedPercent;
  String? _notifiedStatus;

  bool get _inForeground {
    // `inactive` (persiana de notificaciones bajada, diálogo del sistema)
    // sigue siendo visible: el instalador se puede abrir.
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  @override
  void initState() {
    super.initState();
    _instance = this;
    WidgetsBinding.instance.addObserver(this);
    if (widget.checkOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check(silent: true));
      // Aviso de la comprobación en segundo plano (respaldo sin push).
      DeviceChannel.setUpdateNotificationTapListener(
        () => _check(silent: true),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_instance == this) {
      _instance = null;
    }
    if (widget.checkOnStart) {
      DeviceChannel.setUpdateNotificationTapListener(null);
    }
    super.dispose();
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver a la app con la actualización ya descargada, se ofrece
    // instalarla (si no se abrió ya el instalador desde la notificación).
    if (state == AppLifecycleState.resumed && _readyToInstall && mounted) {
      setState(() {
        _readyToInstall = false;
        _minimized = false;
        _error = null;
      });
      _showReadyPrompt();
    }
  }

  /// Aviso "lista para instalar" con el botón "Instalar ahora".
  void _showReadyPrompt() {
    setState(() {
      _error =
          'La actualización ya se descargó. Toca en "Instalar ahora" para '
          'terminar.';
    });
  }

  /// Muestra el aviso de una versión concreta.
  void _showInfo(AppUpdateInfo info) => setState(() => _info = info);

  /// Oculta el aviso.
  void _dismiss() => setState(() => _info = null);

  void _toast(String message) {
    final navContext = rootNavigatorKey.currentContext ?? context;
    final messenger = ScaffoldMessenger.maybeOf(navContext);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Lanza la descarga de la actualización.
  void _startDownload([AppUpdateInfo? customInfo]) {
    if (_downloading) {
      setState(() => _minimized = false);
      return;
    }
    if (customInfo != null) {
      _info = customInfo;
    }
    if (_info != null) _downloadAndInstall();
  }

  Future<void> _downloadAndInstall() async {
    final info = _info;
    if (info == null) return;

    // Escritorio: no hay APK ni parches; se abre la release para bajar el
    // instalador de su sistema.
    if (DeviceChannel.isDesktop) {
      await DeviceChannel.openUrl(desktopReleasesUrl);
      _dismiss();
      return;
    }

    setState(() {
      _downloading = true;
      _minimized = false;
      _readyToInstall = false;
      _progress = 0;
      _status = null;
      _error = null;
    });
    _notifiedPercent = null;
    _notifiedStatus = null;

    // Servicio en primer plano: Android no congela ni mata el proceso si el
    // usuario sale de la app mientras se descarga, y el progreso se ve en
    // la barra de notificaciones.
    if (Platform.isAndroid && !info.isDownloaded) {
      await DeviceChannel.startUpdateDownload(text: 'Descargando');
    }

    try {
      final service = ref.read(appUpdateServiceProvider);
      File? existingFile;
      if (info.isDownloaded && info.localPath != null) {
        final candidate = File(info.localPath!);
        if (candidate.existsSync() && candidate.lengthSync() > 1024 * 100) {
          existingFile = candidate;
        }
      }

      final file =
          existingFile ??
          await service.download(
            info,
            onProgress: (received, total) {
              final progress = total > 0 ? received / total : 0.0;
              _reportProgress(total > 0 ? (progress * 100).floor() : null);
              if (!mounted) return;
              setState(() {
                _progress = progress;
              });
            },
            onStatus: (status) {
              _notifiedStatus = status;
              _reportProgress(
                status.startsWith('Aplicando') ||
                        status.startsWith('Verificando')
                    ? null
                    : _notifiedPercent,
                force: true,
              );
              if (!mounted) return;
              setState(() {
                _status = status;
                // Aplicar/verificar no tiene porcentaje: barra indeterminada.
                if (status.startsWith('Aplicando') ||
                    status.startsWith('Verificando')) {
                  _progress = null;
                }
              });
            },
          );

      // Guardar la ruta local del APK descargado en el estado para no volver
      // a descargarlo si el usuario tuvo que autorizar permisos del sistema.
      _info = info.copyWith(localPath: file.path);

      // Con la app en segundo plano Android no deja abrir el instalador:
      // se avisa con una notificación y se instala al tocarla (o al volver).
      if (!_inForeground) {
        await DeviceChannel.notifyUpdateReady(
          path: file.path,
          versionName: info.versionName,
        );
        if (!mounted) return;
        setState(() {
          _downloading = false;
          _minimized = false;
          _readyToInstall = true;
        });
        return;
      }

      await DeviceChannel.stopUpdateDownload();
      final installed = await service.install(file);
      if (!mounted) return;
      if (!installed) {
        setState(() {
          _downloading = false;
          _error =
              'Activa el permiso "Instalar apps desconocidas" para QvaTube '
              'y toca en "Instalar ahora" (el archivo ya está guardado).';
        });
        return;
      }
      setState(() {
        _downloading = false;
        _minimized = false;
      });
    } catch (_) {
      if (_inForeground) {
        await DeviceChannel.stopUpdateDownload();
      } else {
        await DeviceChannel.notifyUpdateFailed();
      }
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _minimized = false;
        _error = 'No se pudo descargar la actualización. Revisa tu conexión.';
      });
    }
  }

  /// Envía el progreso a la notificación solo cuando cambia el porcentaje
  /// (o el texto), para no mandar cientos de mensajes por segundo.
  void _reportProgress(int? percent, {bool force = false}) {
    if (!Platform.isAndroid) return;
    if (!force && percent == _notifiedPercent) return;
    _notifiedPercent = percent;
    DeviceChannel.updateDownloadProgress(
      percent: percent,
      text: _notifiedStatus,
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;

    return Stack(
      children: [
        widget.child ?? const SizedBox.shrink(),
        if (info != null && !_downloading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _RemoteFocus(child: _UpdateBanner(info: info)),
          ),
        if (_downloading && _minimized)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _DownloadPill(
              progress: _progress,
              status: _status,
              onTap: () => setState(() => _minimized = false),
            ),
          )
        else if (_downloading || _error != null)
          _RemoteFocus(
            child: _DownloadOverlay(
            progress: _progress,
            status: _status,
            error: _error,
            canRetryInstall: info?.isDownloaded ?? false,
            onRetryInstall: () {
              setState(() => _error = null);
              _downloadAndInstall();
            },
            onCloseError: () => setState(() => _error = null),
            onMinimize: _downloading
                ? () => setState(() => _minimized = true)
                : null,
            ),
          ),
      ],
    );
  }
}

/// En la tele (Google TV) lleva el foco del mando a [child] al aparecer.
///
/// El aviso de actualización está por encima del Navigator, fuera del
/// ámbito de foco de las pantallas: con las flechas del mando no se podía
/// llegar a sus botones. Aquí se le da su propio ámbito, se enfoca su botón
/// principal (`autofocus`) y, al cerrarse, el foco vuelve a donde estaba.
/// En el móvil no hace nada: no quita el teclado a quien está escribiendo.
class _RemoteFocus extends StatefulWidget {
  const _RemoteFocus({required this.child});

  final Widget child;

  @override
  State<_RemoteFocus> createState() => _RemoteFocusState();
}

class _RemoteFocusState extends State<_RemoteFocus> {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'update-remote');
  FocusNode? _previous;

  @override
  void initState() {
    super.initState();
    if (!DeviceChannel.isTelevision) return;
    _previous = FocusManager.instance.primaryFocus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scope.requestFocus();
      // Si el botón con `autofocus` aún no lo tomó, el primero que haya.
      if (_scope.focusedChild == null) _scope.nextFocus();
    });
  }

  @override
  void dispose() {
    final previous = _previous;
    if (DeviceChannel.isTelevision &&
        _scope.hasFocus &&
        previous != null &&
        previous.context != null &&
        previous.canRequestFocus) {
      previous.requestFocus();
    }
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!DeviceChannel.isTelevision) return widget.child;
    return FocusScope(node: _scope, child: widget.child);
  }
}

/// Banner superior automático con todas las novedades explicadas de forma
/// sencilla y no técnica para el usuario.
class _UpdateBanner extends ConsumerWidget {
  const _UpdateBanner({required this.info});

  final AppUpdateInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changes = info.userFriendlyChanges;
    final versionTag =
        (info.versionName != null && info.versionName!.isNotEmpty)
        ? 'v${info.versionName}'
        : null;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          color: AppColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          elevation: 12,
          shadowColor: Colors.black87,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: AppColors.accent, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accentSoft,
                      ),
                      child: const Icon(
                        Icons.system_update,
                        color: AppColors.accent,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '¡Nueva actualización disponible!',
                                  style: AppTextStyles.body(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (versionTag != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent,
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.pill,
                                    ),
                                  ),
                                  child: Text(
                                    versionTag,
                                    style: AppTextStyles.mono(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          // En escritorio no se baja el APK: su tamaño no
                          // aplica.
                          if (!DeviceChannel.isDesktop &&
                              info.downloadSizeMb != null &&
                              info.downloadSizeMb! > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                info.applicablePatch != null &&
                                        info.sizeMb != null
                                    ? 'Descarga: solo '
                                          '${info.downloadSizeMb!.toStringAsFixed(1)} MB '
                                          '(en vez de ${info.sizeMb!.toStringAsFixed(1)} MB)'
                                    : 'Tamaño de descarga: '
                                          '${info.downloadSizeMb!.toStringAsFixed(1)} MB',
                                style: AppTextStyles.body(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _dismiss(context),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 150),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Novedades de esta versión:',
                          style: AppTextStyles.body(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final item in changes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 5, right: 7),
                                  child: Icon(
                                    Icons.check_circle,
                                    size: 12,
                                    color: AppColors.accent,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    item,
                                    style: AppTextStyles.body(
                                      fontSize: 12,
                                      color: AppColors.textPrimary,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _dismiss(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 34),
                      ),
                      child: Text(
                        'Ahora no',
                        style: AppTextStyles.body(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      autofocus: true,
                      onPressed: () => _startDownload(context),
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Actualizar ahora'),
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
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _dismiss(BuildContext context) {
    final state =
        context.findAncestorStateOfType<_UpdateCheckerState>() ??
        _UpdateCheckerState._instance;
    state?._dismiss();
  }

  void _startDownload(BuildContext context) {
    final state =
        context.findAncestorStateOfType<_UpdateCheckerState>() ??
        _UpdateCheckerState._instance;
    state?._startDownload(info);
  }
}

/// Overlay de descarga (con el progreso) mientras se instala la actualización.
class _DownloadOverlay extends StatelessWidget {
  const _DownloadOverlay({
    this.progress,
    this.status,
    this.error,
    this.canRetryInstall = false,
    this.onRetryInstall,
    this.onCloseError,
    this.onMinimize,
  });

  final double? progress;
  final String? status;
  final String? error;
  final bool canRetryInstall;
  final VoidCallback? onRetryInstall;
  final VoidCallback? onCloseError;

  /// Pliega el aviso y deja la descarga en segundo plano.
  final VoidCallback? onMinimize;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: Container(
            width: 310,
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
                    Icon(
                      error != null ? Icons.error_outline : Icons.downloading,
                      color: error != null
                          ? AppColors.danger
                          : AppColors.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error != null
                            ? (canRetryInstall
                                  ? 'Actualización lista para instalar'
                                  : 'No se completó la actualización')
                            : status ?? 'Descargando la actualización',
                        style: AppTextStyles.body(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (error == null) ...[
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
                        ? (status?.startsWith('Aplicando') == true
                              ? 'Reconstruyendo la app con los cambios…'
                              : 'Preparando…')
                        : '${(progress! * 100).toStringAsFixed(0)} %',
                    style: AppTextStyles.body(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                  if (onMinimize != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Puedes salir de la app: la descarga sigue y te '
                      'avisamos con una notificación cuando termine.',
                      style: AppTextStyles.body(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        autofocus: true,
                        onPressed: onMinimize,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Seguir usando la app'),
                      ),
                    ),
                  ],
                ] else ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: AppTextStyles.body(
                      fontSize: 12,
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        autofocus: !canRetryInstall,
                        onPressed: onCloseError,
                        child: const Text('Cerrar'),
                      ),
                      if (canRetryInstall && onRetryInstall != null) ...[
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          autofocus: true,
                          onPressed: onRetryInstall,
                          icon: const Icon(Icons.install_mobile, size: 16),
                          label: const Text('Instalar ahora'),
                        ),
                      ],
                    ],
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

/// Píldora superior con el progreso cuando la descarga está plegada.
class _DownloadPill extends StatelessWidget {
  const _DownloadPill({this.progress, this.status, required this.onTap});

  final double? progress;
  final String? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final percent = progress == null
        ? null
        : '${(progress! * 100).toStringAsFixed(0)} %';
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Material(
            color: AppColors.surfaceSecondary,
            elevation: 8,
            shape: StadiumBorder(
              side: BorderSide(color: AppColors.accent.withValues(alpha: 0.7)),
            ),
            child: InkWell(
              onTap: onTap,
              customBorder: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      percent == null
                          ? 'Actualizando…'
                          : 'Actualizando · $percent',
                      style: AppTextStyles.body(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
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
    if (_checking) return;
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
          final state =
              context.findAncestorStateOfType<_UpdateCheckerState>() ??
              _UpdateCheckerState._instance;
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
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _checking ? null : _check,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                            ? 'Comprobando en el repositorio…'
                            : 'Ver si hay una versión más reciente disponible',
                        style: AppTextStyles.body(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_checking)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  )
                else
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Diálogo informativo con la versión instalada.
Future<void> showAppVersionDialog(
  BuildContext context, {
  ({int versionCode, String versionName, int lastUpdateTime})? installedVersion,
  bool justUpdated = false,
}) async {
  final version =
      installedVersion ?? await AppUpdateService().installedVersion();
  if (!context.mounted) return;

  final normalizedCode = AppUpdateService.normalizeVersionCode(
    version.versionCode,
  );
  final versionLabel = version.versionName.isEmpty
      ? 'la versión $normalizedCode'
      : 'la versión ${version.versionName}';
  final installedLabel = version.versionName.isEmpty
      ? 'Versión instalada: $normalizedCode'
      : 'Versión instalada: ${version.versionName} (build $normalizedCode)';
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
                    'La app se actualizó correctamente a $versionLabel.',
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
              'https://github.com/QvaDev-Team/QvaTube_APK/releases/latest',
            );
          },
          child: Text(justUpdated ? 'Ver novedades' : 'Ver releases'),
        ),
      ],
    ),
  );
}
