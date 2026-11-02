import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/network/api_providers.dart';
import '../../../../core/network/endpoints/playback_endpoints.dart';
import '../../../../core/platform/device_channel.dart';
import '../../../../core/router/router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/app_cached_image.dart';
import '../../../catalog/application/catalog_providers.dart';
import '../../../catalog/domain/catalog_models.dart';

/// Elemento reproducible (película, episodio, pista musical o libro).
class PlayableMediaItem {
  const PlayableMediaItem({
    required this.chatId,
    required this.msgId,
    required this.title,
    this.subtitle,
    this.posterUrl,
    this.isAudio = false,
    this.isBook = false,
    this.initialPositionSeconds,
  });

  final int chatId;
  final int msgId;
  final String title;
  final String? subtitle;
  final String? posterUrl;
  final bool isAudio;
  final bool isBook;
  final double? initialPositionSeconds;

  String get streamUrl =>
      absoluteMediaUrl(PlaybackEndpoints.watch(chatId, msgId));

  String get readUrl => absoluteMediaUrl(PlaybackEndpoints.read(chatId, msgId));
}

/// Motivo por el que el servidor rechazó la reproducción antes de empezar
/// (comprobación previa con `HEAD /watch/...`, igual que `openPlayer` en la web).
enum PlaybackBlock {
  /// 403: se agotó el cupo de reproducciones online del plan.
  limit,

  /// 401: no hay sesión o caducó.
  auth,

  /// 503: el servicio de streaming está al máximo de capacidad.
  busy,
}

/// Controlador global de reproducción que permite mantener la música o película
/// activa en segundo plano (al salir de la pantalla del reproductor o minimizar
/// la app) y sincroniza las acciones con la barra de notificaciones del sistema.
class ActiveMediaSession extends ChangeNotifier {
  ActiveMediaSession._() {
    DeviceChannel.setMediaActionListener(_handleSystemMediaAction);
  }

  static final ActiveMediaSession instance = ActiveMediaSession._();

  VideoPlayerController? _controller;
  WidgetRef? _ref;
  List<PlayableMediaItem> _playlist = const [];
  int _currentIndex = 0;
  bool _loading = false;
  String? _error;
  String? _errorDetail;
  PlaybackBlock? _block;
  int _resetInSeconds = 0;
  bool _isMuted = false;
  double _playbackSpeed = 1.0;
  bool _markedWatched = false;
  bool _useWebViewFallback = false;
  bool _screenOpen = false;
  Timer? _progressSaveTimer;
  bool? _lastNotifiedPlaying;
  int? _lastNotifiedIndex;

  VideoPlayerController? get controller => _controller;
  List<PlayableMediaItem> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  bool get loading => _loading;
  String? get error => _error;

  /// Mensaje técnico del reproductor (ExoPlayer) para diagnosticar el fallo.
  String? get errorDetail => _errorDetail;
  PlaybackBlock? get block => _block;

  /// Segundos hasta que se reinicia el cupo (cabecera `X-Reset-In-Seconds`).
  int get resetInSeconds => _resetInSeconds;
  bool get isMuted => _isMuted;
  double get playbackSpeed => _playbackSpeed;
  bool get useWebViewFallback => _useWebViewFallback;
  bool get isScreenOpen => _screenOpen;

  bool get hasActiveMedia =>
      _playlist.isNotEmpty && (_controller != null || _loading);

  PlayableMediaItem? get currentItem =>
      (_playlist.isNotEmpty &&
          _currentIndex >= 0 &&
          _currentIndex < _playlist.length)
      ? _playlist[_currentIndex]
      : null;

  bool get hasPrevious => _currentIndex > 0;
  bool get hasNext => _currentIndex < _playlist.length - 1;

  bool get isPlaying =>
      _controller != null &&
      _controller!.value.isInitialized &&
      _controller!.value.isPlaying;

  void attachRef(WidgetRef ref) {
    _ref = ref;
  }

  void setScreenOpen(bool open) {
    if (_screenOpen == open) return;
    _screenOpen = open;
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }

  void setUseWebViewFallback(bool value) {
    _useWebViewFallback = value;
    notifyListeners();
  }

  Future<void> startPlaylist(
    List<PlayableMediaItem> items, {
    int initialIndex = 0,
  }) async {
    if (items.isEmpty) return;
    final targetIdx = initialIndex.clamp(0, items.length - 1);

    // Si ya se está reproduciendo exactamente el mismo ítem, reutilizar la sesión.
    final current = currentItem;
    final requested = items[targetIdx];
    if (current != null &&
        _controller != null &&
        _controller!.value.isInitialized &&
        current.chatId == requested.chatId &&
        current.msgId == requested.msgId) {
      _playlist = items;
      _currentIndex = targetIdx;
      notifyListeners();
      _syncNotification(force: true);
      return;
    }

    _saveCurrentProgress();
    _playlist = items;
    _currentIndex = targetIdx;
    await initCurrentItem();
  }

  Map<String, String> _buildAuthHeaders() {
    final ref = _ref;
    if (ref == null) return const <String, String>{};
    final cookie = ref.read(apiClientProvider).sessionCookie;
    if (cookie != null && cookie.isNotEmpty) {
      return <String, String>{'Cookie': 'qva_session=$cookie'};
    }
    return const <String, String>{};
  }

  Future<void> initCurrentItem() async {
    _progressSaveTimer?.cancel();
    _markedWatched = false;
    _useWebViewFallback = false;

    final prev = _controller;
    _controller = null;
    prev?.removeListener(_onControllerUpdate);
    await prev?.dispose();

    final item = currentItem;
    if (item == null) return;

    if (item.isBook) {
      _loading = false;
      _error = null;
      _block = null;
      _useWebViewFallback = true;
      await DeviceChannel.clearMediaNotification();
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    _errorDetail = null;
    _block = null;
    notifyListeners();

    final block = await _preflight(item);
    if (currentItem != item) return;
    if (block != null) {
      _loading = false;
      _block = block;
      await DeviceChannel.clearMediaNotification();
      notifyListeners();
      return;
    }

    try {
      var startSeconds = item.initialPositionSeconds ?? 0;
      final ref = _ref;
      if (startSeconds <= 0 && ref != null) {
        startSeconds = await ref.read(catalogApiProvider).getProgress(
              chatId: item.chatId,
              msgId: item.msgId,
            );
      }

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(item.streamUrl),
        httpHeaders: _buildAuthHeaders(),
        videoPlayerOptions: VideoPlayerOptions(
          allowBackgroundPlayback: true,
        ),
      );
      _controller = controller;
      await controller.initialize();
      await controller.setPlaybackSpeed(_playbackSpeed);
      await controller.setVolume(_isMuted ? 0 : 1);

      final durationSeconds = controller.value.duration.inSeconds.toDouble();
      if (startSeconds > 5 &&
          (durationSeconds <= 0 || startSeconds < durationSeconds - 15)) {
        await controller.seekTo(Duration(seconds: startSeconds.round()));
      }

      controller.addListener(_onControllerUpdate);
      await controller.play();

      _loading = false;
      notifyListeners();
      _syncNotification(force: true);

      _progressSaveTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) {
          _saveCurrentProgress();
          _syncNotification(force: true);
        },
      );
    } catch (e) {
      _loading = false;
      _error = 'No se pudo iniciar la reproducción directa de este formato.';
      _errorDetail = e is PlatformException
          ? [e.code, e.message, e.details]
              .whereType<Object>()
              .map((v) => v.toString())
              .where((v) => v.isNotEmpty)
              .join(' · ')
          : e.toString();
      debugPrint('Reproducción fallida (${item.streamUrl}): $_errorDetail');
      notifyListeners();
    }
  }

  /// Pregunta al servidor si se puede reproducir antes de abrir el
  /// reproductor: si no, ExoPlayer solo da un error genérico de "formato".
  /// Ante un fallo de red o un código no previsto se deja seguir y que el
  /// reproductor muestre su propio error.
  Future<PlaybackBlock?> _preflight(PlayableMediaItem item) async {
    final ref = _ref;
    if (ref == null) return null;
    try {
      final response = await ref.read(apiClientProvider).dio.head<void>(
            item.streamUrl,
            options: Options(
              validateStatus: (_) => true,
              receiveTimeout: const Duration(seconds: 15),
            ),
          );
      switch (response.statusCode) {
        case 403:
          _resetInSeconds =
              int.tryParse(response.headers.value('x-reset-in-seconds') ?? '') ??
                  0;
          return PlaybackBlock.limit;
        case 401:
          return PlaybackBlock.auth;
        case 503:
          return PlaybackBlock.busy;
      }
    } catch (_) {}
    return null;
  }

  void _onControllerUpdate() {
    final ctrl = _controller;
    final item = currentItem;
    if (ctrl == null || !ctrl.value.isInitialized || item == null) return;

    final pos = ctrl.value.position.inSeconds;
    final dur = ctrl.value.duration.inSeconds;

    if (!_markedWatched && dur > 30 && pos >= dur * 0.9) {
      _markedWatched = true;
      _ref?.read(catalogApiProvider).markWatched(
            chatId: item.chatId,
            msgId: item.msgId,
          );
    }

    // Pasar automáticamente al siguiente episodio/pista al terminar.
    if (dur > 0 &&
        ctrl.value.position >= ctrl.value.duration &&
        !ctrl.value.isPlaying &&
        hasNext) {
      changeItem(_currentIndex + 1);
      return;
    }

    _syncNotification();
    notifyListeners();
  }

  void _syncNotification({bool force = false}) {
    final ctrl = _controller;
    final item = currentItem;
    if (ctrl == null || !ctrl.value.isInitialized || item == null || item.isBook) {
      return;
    }

    final playing = ctrl.value.isPlaying;
    if (!force &&
        _lastNotifiedPlaying == playing &&
        _lastNotifiedIndex == _currentIndex) {
      return;
    }

    _lastNotifiedPlaying = playing;
    _lastNotifiedIndex = _currentIndex;

    DeviceChannel.updateMediaNotification(
      title: item.title,
      subtitle: item.subtitle,
      isPlaying: playing,
      hasNext: hasNext,
      hasPrevious: hasPrevious,
      positionMs: ctrl.value.position.inMilliseconds,
      durationMs: ctrl.value.duration.inMilliseconds,
    );
  }

  void _handleSystemMediaAction(String action, int? positionMs) {
    switch (action) {
      case 'playPause':
        playPause();
      case 'next':
        if (hasNext) changeItem(_currentIndex + 1);
      case 'previous':
        if (hasPrevious) changeItem(_currentIndex - 1);
      case 'stop':
        stopAndClose();
      case 'seek':
        if (positionMs != null) {
          seekTo(Duration(milliseconds: positionMs));
        }
    }
  }

  void playPause() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
      _saveCurrentProgress();
    } else {
      ctrl.play();
    }
    _syncNotification(force: true);
    notifyListeners();
  }

  void seekRelative(int deltaSeconds) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final currentSec = ctrl.value.position.inSeconds;
    final maxSec = ctrl.value.duration.inSeconds;
    final target = (currentSec + deltaSeconds).clamp(
      0,
      maxSec > 0 ? maxSec : 86400,
    );
    ctrl.seekTo(Duration(seconds: target));
    _syncNotification(force: true);
    notifyListeners();
  }

  void seekTo(Duration position) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    ctrl.seekTo(position);
    _syncNotification(force: true);
    notifyListeners();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    await _controller?.setPlaybackSpeed(speed);
    notifyListeners();
  }

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    await _controller?.setVolume(_isMuted ? 0 : 1);
    notifyListeners();
  }

  void changeItem(int newIndex) {
    if (newIndex < 0 || newIndex >= _playlist.length) return;
    _saveCurrentProgress();
    _currentIndex = newIndex;
    initCurrentItem();
  }

  void _saveCurrentProgress() {
    final ctrl = _controller;
    final item = currentItem;
    final ref = _ref;
    if (ctrl == null || !ctrl.value.isInitialized || item == null || ref == null) {
      return;
    }
    final pos = ctrl.value.position.inMilliseconds / 1000.0;
    final dur = ctrl.value.duration.inMilliseconds / 1000.0;
    if (pos <= 3) return;

    ref.read(catalogApiProvider).saveProgress(
          chatId: item.chatId,
          msgId: item.msgId,
          positionSeconds: pos,
          durationSeconds: dur > 0 ? dur : null,
          kind: item.isAudio ? 'audio' : 'video',
        );
  }

  Future<void> stopAndClose() async {
    _progressSaveTimer?.cancel();
    _saveCurrentProgress();
    final ref = _ref;
    if (ref != null) {
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(planUsageProvider);
    }

    final prev = _controller;
    _controller = null;
    _playlist = const [];
    _currentIndex = 0;
    _loading = false;
    _error = null;
    _block = null;
    _lastNotifiedPlaying = null;
    _lastNotifiedIndex = null;

    prev?.removeListener(_onControllerUpdate);
    await prev?.dispose();
    await DeviceChannel.clearMediaNotification();
    notifyListeners();
  }
}

/// Abre el reproductor multimedia de QvaTube en pantalla completa.
Future<void> openMediaPlayer(
  BuildContext context, {
  required List<PlayableMediaItem> playlist,
  int initialIndex = 0,
}) async {
  if (playlist.isEmpty) return;
  final nav = rootNavigatorKey.currentState ??
      Navigator.of(context, rootNavigator: true);
  await nav.push<void>(
    MaterialPageRoute(
      builder: (context) => MediaPlayerScreen(
        playlist: playlist,
        initialIndex: initialIndex.clamp(0, playlist.length - 1),
      ),
    ),
  );
}

/// Barra flotante en la parte inferior de la app cuando el usuario sale de la
/// pantalla del reproductor sin detener la reproducción.
class MiniMediaPlayerBar extends ConsumerWidget {
  const MiniMediaPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: ActiveMediaSession.instance,
      builder: (context, _) {
        final session = ActiveMediaSession.instance;
        session.attachRef(ref);
        final item = session.currentItem;
        if (!session.hasActiveMedia ||
            session.isScreenOpen ||
            item == null ||
            item.isBook) {
          return const SizedBox.shrink();
        }

        final ctrl = session.controller;
        final initialized = ctrl != null && ctrl.value.isInitialized;
        final pos = initialized ? ctrl.value.position.inMilliseconds : 0;
        final dur = initialized ? ctrl.value.duration.inMilliseconds : 0;
        final progress = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;

        return Material(
          color: AppColors.surfaceSecondary,
          child: InkWell(
            onTap: () => openMediaPlayer(
              context,
              playlist: session.playlist,
              initialIndex: session.currentIndex,
            ),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.border, width: 1),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (initialized && dur > 0)
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor: Colors.white12,
                      color: AppColors.accent,
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: (item.posterUrl != null &&
                                    item.posterUrl!.isNotEmpty)
                                ? AppCachedImage(
                                    imageUrl: item.posterUrl!,
                                    fit: BoxFit.cover,
                                  )
                                : ColoredBox(
                                    color: AppColors.surface,
                                    child: Icon(
                                      item.isAudio
                                          ? Icons.music_note
                                          : Icons.movie_outlined,
                                      size: 20,
                                      color: AppColors.accent,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.body(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (item.subtitle != null &&
                                  item.subtitle!.isNotEmpty)
                                Text(
                                  item.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.body(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (session.hasPrevious)
                          IconButton(
                            onPressed: () =>
                                session.changeItem(session.currentIndex - 1),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.skip_previous,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        IconButton(
                          onPressed: session.playPause,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            session.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: AppColors.accent,
                            size: 26,
                          ),
                        ),
                        if (session.hasNext)
                          IconButton(
                            onPressed: () =>
                                session.changeItem(session.currentIndex + 1),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.skip_next,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        IconButton(
                          onPressed: session.stopAndClose,
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Detener reproducción',
                          icon: const Icon(
                            Icons.close,
                            color: AppColors.textMuted,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class MediaPlayerScreen extends ConsumerStatefulWidget {
  const MediaPlayerScreen({
    super.key,
    required this.playlist,
    this.initialIndex = 0,
  });

  final List<PlayableMediaItem> playlist;
  final int initialIndex;

  @override
  ConsumerState<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends ConsumerState<MediaPlayerScreen> {
  final ActiveMediaSession _session = ActiveMediaSession.instance;
  Timer? _hideControlsTimer;

  bool _showControls = true;
  bool _isLandscape = false;
  double? _draggingSeconds;

  @override
  void initState() {
    super.initState();
    _session.attachRef(ref);
    _session.setScreenOpen(true);
    _session.addListener(_onSessionChanged);
    _session.startPlaylist(widget.playlist, initialIndex: widget.initialIndex);
    _scheduleHideControls();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _session.removeListener(_onSessionChanged);
    _session.setScreenOpen(false);
    _restoreSystemUi();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    if (!_session.hasActiveMedia && !_session.useWebViewFallback) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {});
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  Future<void> _toggleLandscape() async {
    if (_isLandscape) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      if (mounted) setState(() => _isLandscape = false);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      if (mounted) setState(() => _isLandscape = true);
    }
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    final item = _session.currentItem;
    if (item == null || item.isAudio) return;
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _session.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _scheduleHideControls();
    }
  }

  void _playPause() {
    _session.playPause();
    if (_session.isPlaying) {
      _scheduleHideControls();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  Future<void> _pickSpeed() async {
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    final currentSpeed = _session.playbackSpeed;
    final chosen = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Velocidad de reproducción',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
              ),
              for (final s in speeds)
                ListTile(
                  leading: Icon(
                    s == currentSpeed
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: s == currentSpeed
                        ? AppColors.accent
                        : AppColors.textMuted,
                    size: 20,
                  ),
                  title: Text(
                    s == 1.0 ? 'Normal (1.0x)' : '${s}x',
                    style: AppTextStyles.body(
                      fontSize: 13.5,
                      fontWeight:
                          s == currentSpeed ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(s),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null && mounted) {
      await _session.setPlaybackSpeed(chosen);
      _scheduleHideControls();
    }
  }

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    if (totalSeconds <= 0) return '00:00';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$mm:$ss';
    }
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final item =
        _session.currentItem ??
        widget.playlist[widget.initialIndex.clamp(0, widget.playlist.length - 1)];

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          ref.invalidate(continueWatchingProvider);
          ref.invalidate(planUsageProvider);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          top: !_isLandscape,
          bottom: !_isLandscape,
          child: _session.useWebViewFallback
              ? _buildWebViewFallback(item)
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(child: _buildMediaSurface(item)),
                      if (_showControls ||
                          _session.loading ||
                          _session.error != null)
                        _buildControlsOverlay(item),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildMediaSurface(PlayableMediaItem item) {
    if (_session.loading) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.posterUrl != null && item.posterUrl!.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: SizedBox(
                width: item.isAudio ? 160 : 120,
                height: item.isAudio ? 160 : 180,
                child: AppCachedImage(
                  imageUrl: item.posterUrl!,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          const CircularProgressIndicator(color: AppColors.accent),
          const SizedBox(height: 14),
          Text(
            'Cargando reproducción…',
            style: AppTextStyles.body(
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
        ],
      );
    }

    final block = _session.block;
    if (block != null) {
      return _PlaybackBlockedView(
        block: block,
        resetInSeconds: _session.resetInSeconds,
        isMusic: item.isAudio,
        onRetry: _session.initCurrentItem,
        onAction: () async {
          final router = ref.read(routerProvider);
          final nav = Navigator.of(context);
          await _session.stopAndClose();
          if (mounted) nav.maybePop();
          router.push(block == PlaybackBlock.auth ? Routes.login : '/cuenta/plan');
        },
      );
    }

    if (_session.error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.danger,
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(
              _session.error!,
              textAlign: TextAlign.center,
              style: AppTextStyles.body(fontSize: 13.5, color: Colors.white),
            ),
            if (_session.errorDetail != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                _session.errorDetail!,
                textAlign: TextAlign.center,
                maxLines: 4,
                style: AppTextStyles.body(fontSize: 11, color: Colors.white38),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _session.initCurrentItem,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reintentar'),
                ),
                ElevatedButton.icon(
                  onPressed: () => _session.setUseWebViewFallback(true),
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: const Text('Reproductor alternativo'),
                ),
                OutlinedButton.icon(
                  onPressed: () => DeviceChannel.openUrl(item.streamUrl),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Abrir externo'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final ctrl = _session.controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const SizedBox.shrink();
    }

    if (item.isAudio) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.22),
                    blurRadius: 32,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: (item.posterUrl != null && item.posterUrl!.isNotEmpty)
                    ? AppCachedImage(
                        imageUrl: item.posterUrl!,
                        fit: BoxFit.cover,
                      )
                    : const Icon(
                        Icons.music_note,
                        size: 72,
                        color: AppColors.accent,
                      ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              item.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                item.subtitle!,
                textAlign: TextAlign.center,
                style: AppTextStyles.body(
                  fontSize: 13.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            // Deja libre la franja inferior donde van los controles para que
            // no tapen la carátula.
            const SizedBox(height: 150),
          ],
        ),
      );
    }

    final aspect = ctrl.value.aspectRatio > 0
        ? ctrl.value.aspectRatio
        : 16 / 9;

    return AspectRatio(
      aspectRatio: aspect,
      child: VideoPlayer(ctrl),
    );
  }

  Widget _buildControlsOverlay(PlayableMediaItem item) {
    final ctrl = _session.controller;
    final initialized = ctrl != null && ctrl.value.isInitialized;
    final duration = initialized ? ctrl.value.duration : Duration.zero;
    final position = initialized ? ctrl.value.position : Duration.zero;
    final maxSeconds = duration.inMilliseconds / 1000.0;
    final currentSeconds =
        _draggingSeconds ??
        (position.inMilliseconds / 1000.0).clamp(
          0.0,
          maxSeconds > 0 ? maxSeconds : 1.0,
        );

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xCC000000),
            Color(0x33000000),
            Color(0x33000000),
            Color(0xDD000000),
          ],
          stops: [0.0, 0.25, 0.7, 1.0],
        ),
      ),
      child: Column(
        children: [
          // Barra superior
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  tooltip: 'Seguir en segundo plano',
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (item.subtitle != null && item.subtitle!.isNotEmpty)
                        Text(
                          item.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body(
                            fontSize: 11.5,
                            color: Colors.white70,
                          ),
                        ),
                    ],
                  ),
                ),
                if (initialized) ...[
                  TextButton(
                    onPressed: _pickSpeed,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size(44, 36),
                    ),
                    child: Text(
                      '${_session.playbackSpeed}x',
                      style: AppTextStyles.mono(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _session.toggleMute,
                    icon: Icon(
                      _session.isMuted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
                if (!item.isAudio)
                  IconButton(
                    onPressed: _toggleLandscape,
                    tooltip: 'Rotar pantalla',
                    icon: Icon(
                      _isLandscape
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      color: Colors.white,
                    ),
                  ),
                IconButton(
                  onPressed: () async {
                    final nav = Navigator.of(context);
                    await _session.stopAndClose();
                    if (mounted) nav.maybePop();
                  },
                  tooltip: 'Detener y cerrar',
                  icon: const Icon(Icons.close, color: Colors.white, size: 22),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Controles de reproducción
          if (initialized && _session.error == null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_session.hasPrevious)
                  IconButton(
                    onPressed: () =>
                        _session.changeItem(_session.currentIndex - 1),
                    iconSize: 32,
                    color: Colors.white,
                    icon: const Icon(Icons.skip_previous),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    _session.seekRelative(-10);
                    _scheduleHideControls();
                  },
                  iconSize: 34,
                  color: Colors.white,
                  icon: const Icon(Icons.replay_10),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: _playPause,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent,
                      boxShadow: AppColors.playGlow,
                    ),
                    child: ctrl.value.isBuffering
                        ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            ctrl.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            color: Colors.white,
                            size: 36,
                          ),
                  ),
                ),
                const SizedBox(width: 18),
                IconButton(
                  onPressed: () {
                    _session.seekRelative(10);
                    _scheduleHideControls();
                  },
                  iconSize: 34,
                  color: Colors.white,
                  icon: const Icon(Icons.forward_10),
                ),
                const SizedBox(width: 8),
                if (_session.hasNext)
                  IconButton(
                    onPressed: () =>
                        _session.changeItem(_session.currentIndex + 1),
                    iconSize: 32,
                    color: Colors.white,
                    icon: const Icon(Icons.skip_next),
                  ),
              ],
            ),

          // Los controles van pegados a la barra de progreso, abajo, en vez
          // de centrados encima del video o de la carátula.
          const SizedBox(height: 8),

          // Barra inferior con progreso y episodios/pistas
          if (initialized)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        _formatDuration(
                          Duration(seconds: currentSeconds.round()),
                        ),
                        style: AppTextStyles.mono(
                          fontSize: 11.5,
                          color: Colors.white,
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3.5,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6.5,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14,
                            ),
                            activeTrackColor: AppColors.accent,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: AppColors.accent,
                          ),
                          child: Slider(
                            value: currentSeconds,
                            min: 0.0,
                            max: maxSeconds > 0 ? maxSeconds : 1.0,
                            onChanged: (value) {
                              setState(() => _draggingSeconds = value);
                            },
                            onChangeEnd: (value) {
                              setState(() => _draggingSeconds = null);
                              _session.seekTo(
                                Duration(milliseconds: (value * 1000).round()),
                              );
                              _scheduleHideControls();
                            },
                          ),
                        ),
                      ),
                      Text(
                        _formatDuration(duration),
                        style: AppTextStyles.mono(
                          fontSize: 11.5,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  if (_session.hasNext)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () =>
                            _session.changeItem(_session.currentIndex + 1),
                        icon: const Icon(
                          Icons.skip_next,
                          size: 18,
                          color: AppColors.accent,
                        ),
                        label: Text(
                          'Siguiente: ${_session.playlist[_session.currentIndex + 1].subtitle ?? _session.playlist[_session.currentIndex + 1].title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWebViewFallback(PlayableMediaItem item) {
    final targetUrl = item.isBook ? item.readUrl : item.streamUrl;
    return Column(
      children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  await _session.stopAndClose();
                  if (mounted) nav.maybePop();
                },
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => DeviceChannel.openUrl(targetUrl),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Externo'),
              ),
            ],
          ),
        ),
        Expanded(
          child: defaultTargetPlatform == TargetPlatform.android
              ? AndroidView(
                  viewType: 'qvatube/webview',
                  creationParams: <String, dynamic>{'url': targetUrl},
                  creationParamsCodec: const StandardMessageCodec(),
                )
              : Center(
                  child: ElevatedButton.icon(
                    onPressed: () => DeviceChannel.openUrl(targetUrl),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Abrir contenido'),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Pantalla cuando el servidor rechaza la reproducción (límite del plan,
/// sesión caducada o servicio saturado), con la cuenta atrás del cupo.
class _PlaybackBlockedView extends StatefulWidget {
  const _PlaybackBlockedView({
    required this.block,
    required this.resetInSeconds,
    required this.isMusic,
    required this.onRetry,
    required this.onAction,
  });

  final PlaybackBlock block;
  final int resetInSeconds;
  final bool isMusic;
  final VoidCallback onRetry;
  final VoidCallback onAction;

  @override
  State<_PlaybackBlockedView> createState() => _PlaybackBlockedViewState();
}

class _PlaybackBlockedViewState extends State<_PlaybackBlockedView> {
  Timer? _timer;
  late int _remaining = widget.resetInSeconds;

  @override
  void initState() {
    super.initState();
    if (_remaining > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_remaining <= 1) _timer?.cancel();
        setState(() => _remaining = (_remaining - 1).clamp(0, _remaining));
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _countdown(int total) {
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    return [h, m, s].map((n) => n.toString().padLeft(2, '0')).join(':');
  }

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String title, String message, String? action) =
        switch (widget.block) {
      PlaybackBlock.limit => (
          Icons.lock_clock_outlined,
          'Límite alcanzado',
          'Alcanzaste el límite de reproducciones '
              '${widget.isMusic ? 'de música' : 'online'} de tu plan.\n'
              'Para aumentar tu límite, adquiere un plan.',
          'Ver planes',
        ),
      PlaybackBlock.auth => (
          Icons.person_outline,
          'Inicia sesión',
          'Tu sesión caducó. Inicia sesión de nuevo para reproducir online.',
          'Iniciar sesión',
        ),
      PlaybackBlock.busy => (
          Icons.cloud_off_outlined,
          'Servicio saturado',
          'El servicio de reproducción online está al máximo de su capacidad. '
              'Intenta de nuevo en unos segundos.',
          null,
        ),
    };

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.accent, size: 44),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.body(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.body(fontSize: 13.5, color: Colors.white70),
          ),
          if (widget.block == PlaybackBlock.limit && widget.resetInSeconds > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Se reinicia en ${_countdown(_remaining)}',
              style: AppTextStyles.body(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              if (action != null)
                ElevatedButton.icon(
                  onPressed: widget.onAction,
                  icon: Icon(
                    widget.block == PlaybackBlock.auth
                        ? Icons.login
                        : Icons.workspace_premium_outlined,
                    size: 18,
                  ),
                  label: Text(action),
                ),
              OutlinedButton.icon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
