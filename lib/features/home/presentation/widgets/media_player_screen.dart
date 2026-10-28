import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/network/api_providers.dart';
import '../../../../core/network/endpoints/playback_endpoints.dart';
import '../../../../core/platform/device_channel.dart';
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

/// Abre el reproductor multimedia de QvaTube en pantalla completa.
Future<void> openMediaPlayer(
  BuildContext context, {
  required List<PlayableMediaItem> playlist,
  int initialIndex = 0,
}) async {
  if (playlist.isEmpty) return;
  await Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute(
      builder: (context) => MediaPlayerScreen(
        playlist: playlist,
        initialIndex: initialIndex.clamp(0, playlist.length - 1),
      ),
    ),
  );
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
  VideoPlayerController? _controller;
  Timer? _hideControlsTimer;
  Timer? _progressSaveTimer;

  late int _currentIndex;
  bool _loading = true;
  String? _error;
  bool _showControls = true;
  bool _isLandscape = false;
  bool _isMuted = false;
  double _playbackSpeed = 1.0;
  bool _markedWatched = false;
  bool _useWebViewFallback = false;
  double? _draggingSeconds;

  PlayableMediaItem get _current => widget.playlist[_currentIndex];
  bool get _hasPrevious => _currentIndex > 0;
  bool get _hasNext => _currentIndex < widget.playlist.length - 1;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _initCurrentItem();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _progressSaveTimer?.cancel();
    _saveCurrentProgress();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _restoreSystemUi();
    super.dispose();
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

  Map<String, String> _buildAuthHeaders() {
    final cookie = ref.read(apiClientProvider).sessionCookie;
    if (cookie != null && cookie.isNotEmpty) {
      return <String, String>{'Cookie': 'qva_session=$cookie'};
    }
    return const <String, String>{};
  }

  Future<void> _initCurrentItem() async {
    _hideControlsTimer?.cancel();
    _progressSaveTimer?.cancel();
    _markedWatched = false;
    _useWebViewFallback = false;
    _draggingSeconds = null;

    final previousController = _controller;
    _controller = null;
    previousController?.removeListener(_onControllerUpdate);
    await previousController?.dispose();

    final item = _current;
    if (item.isBook) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
          _useWebViewFallback = true;
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _showControls = true;
    });

    try {
      // Consultar progreso guardado si no viene predefinido.
      var startSeconds = item.initialPositionSeconds ?? 0;
      if (startSeconds <= 0) {
        startSeconds = await ref.read(catalogApiProvider).getProgress(
              chatId: item.chatId,
              msgId: item.msgId,
            );
      }

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(item.streamUrl),
        httpHeaders: _buildAuthHeaders(),
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

      if (!mounted) return;
      setState(() => _loading = false);
      _scheduleHideControls();

      _progressSaveTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _saveCurrentProgress(),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'No se pudo iniciar la reproducción directa de este formato.';
      });
    }
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    final pos = ctrl.value.position.inSeconds;
    final dur = ctrl.value.duration.inSeconds;

    if (!_markedWatched && dur > 30 && pos >= dur * 0.9) {
      _markedWatched = true;
      ref.read(catalogApiProvider).markWatched(
            chatId: _current.chatId,
            msgId: _current.msgId,
          );
    }

    setState(() {});
  }

  void _saveCurrentProgress() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final pos = ctrl.value.position.inMilliseconds / 1000.0;
    final dur = ctrl.value.duration.inMilliseconds / 1000.0;
    if (pos <= 3) return;

    final item = _current;
    ref.read(catalogApiProvider).saveProgress(
          chatId: item.chatId,
          msgId: item.msgId,
          positionSeconds: pos,
          durationSeconds: dur > 0 ? dur : null,
          kind: item.isAudio ? 'audio' : 'video',
        );
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    if (_current.isAudio) return;
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      final ctrl = _controller;
      if (mounted && ctrl != null && ctrl.value.isPlaying) {
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
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
      _saveCurrentProgress();
      _hideControlsTimer?.cancel();
    } else {
      ctrl.play();
      _scheduleHideControls();
    }
    setState(() {});
  }

  void _seekRelative(int deltaSeconds) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final currentSec = ctrl.value.position.inSeconds;
    final maxSec = ctrl.value.duration.inSeconds;
    final target = (currentSec + deltaSeconds).clamp(
      0,
      maxSec > 0 ? maxSec : 86400,
    );
    ctrl.seekTo(Duration(seconds: target));
    _scheduleHideControls();
  }

  void _changeItem(int newIndex) {
    if (newIndex < 0 || newIndex >= widget.playlist.length) return;
    _saveCurrentProgress();
    setState(() => _currentIndex = newIndex);
    _initCurrentItem();
  }

  Future<void> _pickSpeed() async {
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
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
                    s == _playbackSpeed
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: s == _playbackSpeed
                        ? AppColors.accent
                        : AppColors.textMuted,
                    size: 20,
                  ),
                  title: Text(
                    s == 1.0 ? 'Normal (1.0x)' : '${s}x',
                    style: AppTextStyles.body(
                      fontSize: 13.5,
                      fontWeight: s == _playbackSpeed
                          ? FontWeight.w700
                          : FontWeight.w500,
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
      setState(() => _playbackSpeed = chosen);
      await _controller?.setPlaybackSpeed(chosen);
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
    final item = _current;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _saveCurrentProgress();
          ref.invalidate(continueWatchingProvider);
          ref.invalidate(planUsageProvider);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          top: !_isLandscape,
          bottom: !_isLandscape,
          child: _useWebViewFallback
              ? _buildWebViewFallback(item)
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Superficie de vídeo o carátula de audio
                      Center(child: _buildMediaSurface(item)),

                      // Controles superpuestos
                      if (_showControls || _loading || _error != null)
                        _buildControlsOverlay(item),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildMediaSurface(PlayableMediaItem item) {
    if (_loading) {
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

    if (_error != null) {
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
              _error!,
              textAlign: TextAlign.center,
              style: AppTextStyles.body(fontSize: 13.5, color: Colors.white),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _initCurrentItem,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reintentar'),
                ),
                ElevatedButton.icon(
                  onPressed: () =>
                      setState(() => _useWebViewFallback = true),
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

    final ctrl = _controller;
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
            const SizedBox(height: 80),
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
    final ctrl = _controller;
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
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                      '${_playbackSpeed}x',
                      style: AppTextStyles.mono(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() => _isMuted = !_isMuted);
                      _controller?.setVolume(_isMuted ? 0 : 1);
                    },
                    icon: Icon(
                      _isMuted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
                if (!item.isAudio)
                  IconButton(
                    onPressed: _toggleLandscape,
                    tooltip: ' Rotar pantalla',
                    icon: Icon(
                      _isLandscape
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),

          const Spacer(),

          // Controles centrales
          if (initialized && _error == null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_hasPrevious)
                  IconButton(
                    onPressed: () => _changeItem(_currentIndex - 1),
                    iconSize: 32,
                    color: Colors.white,
                    icon: const Icon(Icons.skip_previous),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _seekRelative(-10),
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
                  onPressed: () => _seekRelative(10),
                  iconSize: 34,
                  color: Colors.white,
                  icon: const Icon(Icons.forward_10),
                ),
                const SizedBox(width: 8),
                if (_hasNext)
                  IconButton(
                    onPressed: () => _changeItem(_currentIndex + 1),
                    iconSize: 32,
                    color: Colors.white,
                    icon: const Icon(Icons.skip_next),
                  ),
              ],
            ),

          const Spacer(),

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
                              ctrl.seekTo(
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
                  if (_hasNext)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _changeItem(_currentIndex + 1),
                        icon: const Icon(
                          Icons.skip_next,
                          size: 18,
                          color: AppColors.accent,
                        ),
                        label: Text(
                          'Siguiente: ${widget.playlist[_currentIndex + 1].subtitle ?? widget.playlist[_currentIndex + 1].title}',
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
                onPressed: () => Navigator.of(context).maybePop(),
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

