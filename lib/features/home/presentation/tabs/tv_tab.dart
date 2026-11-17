import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/platform/device_channel.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/app_cached_image.dart';
import '../../../../core/widgets/focus_ring.dart';
import '../../../catalog/application/catalog_providers.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../../../../core/layout/responsive.dart';

/// Pestaña de Televisión y Radio en vivo (`GET /api/tv/channels`).
class TvTab extends ConsumerStatefulWidget {
  const TvTab({super.key});

  @override
  ConsumerState<TvTab> createState() => _TvTabState();
}

class _TvTabState extends ConsumerState<TvTab> {
  final _searchController = TextEditingController();
  String _selectedGroup = 'all';
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TvChannel> _filterChannels(
    List<TvChannel> channels,
    Map<String, int> liveViewers,
  ) {
    final q = _searchQuery.trim().toLowerCase();
    return channels
        .map((c) {
          if (c.isRadio) return c;
          final liveCount = liveViewers[c.id] ?? c.viewers ?? 0;
          return c.copyWith(viewers: liveCount);
        })
        .where((c) {
          if (_selectedGroup != 'all' && c.group != _selectedGroup) {
            return false;
          }
          if (q.isEmpty) return true;
          final nameMatch = c.name.toLowerCase().contains(q);
          final tagMatch = (c.tag ?? '').toLowerCase().contains(q);
          final groupMatch = c.groupTitle.toLowerCase().contains(q);
          return nameMatch || tagMatch || groupMatch;
        })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(tvChannelsProvider);
    final viewersMap =
        ref.watch(tvViewersProvider).value ?? const <String, int>{};

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: () async {
        ref.invalidate(tvChannelsProvider);
        ref.invalidate(tvViewersProvider);
        await ref.read(tvChannelsProvider.future);
      },
      child: channelsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
        error: (error, _) {
          final message = error is ApiException
              ? error.message
              : 'No se pudieron cargar los canales de TV y radio.';
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 60),
              const Icon(
                Icons.live_tv_outlined,
                size: 48,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.body(
                  fontSize: 13.5,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: OutlinedButton.icon(
                  onPressed: () => ref.invalidate(tvChannelsProvider),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reintentar'),
                ),
              ),
            ],
          );
        },
        data: (data) {
          final filtered = _filterChannels(data.channels, viewersMap);
          final groups = data.groups;

          // Si se muestra "Todos" sin búsqueda o con ella, agrupamos por grupo.
          final groupedSections =
              <({String key, String title, List<TvChannel> items})>[];
          if (_selectedGroup == 'all') {
            for (final group in groups) {
              final groupItems = filtered
                  .where((c) => c.group == group.key)
                  .toList();
              if (groupItems.isNotEmpty) {
                groupedSections.add((
                  key: group.key,
                  title: group.title,
                  items: groupItems,
                ));
              }
            }
            if (groupedSections.isEmpty && filtered.isNotEmpty) {
              groupedSections.add((
                key: 'all',
                title: 'Canales en vivo',
                items: filtered,
              ));
            }
          } else {
            final groupTitle = groups
                .where((g) => g.key == _selectedGroup)
                .map((g) => g.title)
                .firstOrNull;
            groupedSections.add((
              key: _selectedGroup,
              title: groupTitle ?? 'Canales',
              items: filtered,
            ));
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Buscador de canales
                      TextField(
                        controller: _searchController,
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                        style: AppTextStyles.body(fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText:
                              'Buscar canal o emisora (ej. Cubavisión, Deportes…)',
                          prefixIcon: const Icon(
                            Icons.search,
                            size: 20,
                            color: AppColors.textMuted,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                  icon: const Icon(
                                    Icons.close,
                                    size: 18,
                                    color: AppColors.textMuted,
                                  ),
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Filtros horizontales por grupo
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _GroupFilterChip(
                              label: 'Todos (${data.total})',
                              icon: Icons.live_tv,
                              selected: _selectedGroup == 'all',
                              onTap: () =>
                                  setState(() => _selectedGroup = 'all'),
                            ),
                            for (final g in groups) ...[
                              const SizedBox(width: 8),
                              _GroupFilterChip(
                                label: '${g.title} (${g.count})',
                                icon: g.key == 'radio'
                                    ? Icons.radio
                                    : g.key == 'cu'
                                    ? Icons.tv
                                    : Icons.public,
                                selected: _selectedGroup == g.key,
                                onTap: () =>
                                    setState(() => _selectedGroup = g.key),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (filtered.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 56, horizontal: 24),
                    child: Center(
                      child: Text(
                        'No se encontraron canales con ese filtro.',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ),
                )
              else
                for (final section in groupedSections) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      child: Row(
                        children: [
                          Icon(
                            section.key == 'radio'
                                ? Icons.radio
                                : section.key == 'cu'
                                ? Icons.tv
                                : Icons.public,
                            size: 18,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              section.title,
                              style: Theme.of(context).textTheme.displaySmall,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSecondary,
                              borderRadius: BorderRadius.circular(
                                AppRadii.pill,
                              ),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              '${section.items.length}',
                              style: AppTextStyles.mono(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    sliver: SliverGrid(
                      gridDelegate: posterGridDelegate(
                        context,
                        mobileColumns: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.55,
                        wideMaxWidth: 300,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final channel = section.items[index];
                        return TvChannelCard(
                          channel: channel,
                          onTap: () =>
                              showTvPlayerSheet(context, ref, channel),
                        );
                      }, childCount: section.items.length),
                    ),
                  ),
                ],
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          );
        },
      ),
    );
  }
}

class _GroupFilterChip extends StatelessWidget {
  const _GroupFilterChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 15,
        color: selected ? Colors.white : AppColors.textSecondary,
      ),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.accent,
      backgroundColor: AppColors.surface,
      labelStyle: AppTextStyles.body(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: selected ? Colors.white : AppColors.textSecondary,
      ),
      side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
    );
  }
}

/// Tarjeta de un canal de TV o emisora de radio (reutilizable también en búsqueda).
class TvChannelCard extends StatelessWidget {
  const TvChannelCard({
    super.key,
    required this.channel,
    required this.onTap,
  });

  final TvChannel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viewers = channel.viewers ?? 0;

    return FocusRing(
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 44,
                        height: 44,
                        color: AppColors.surfaceSecondary,
                        child: channel.logoUrl.isEmpty
                            ? Icon(
                                channel.isRadio ? Icons.radio : Icons.live_tv,
                                color: AppColors.textMuted,
                                size: 22,
                              )
                            : AppCachedImage(
                                imageUrl: channel.logoUrl,
                                fit: BoxFit.cover,
                                errorWidget: Icon(
                                  channel.isRadio ? Icons.radio : Icons.live_tv,
                                  color: AppColors.textMuted,
                                  size: 22,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            channel.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            channel.tag?.isNotEmpty == true
                                ? channel.tag!
                                : channel.groupTitle,
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
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: channel.isRadio
                            ? const Color(0x263B82F6)
                            : AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: channel.isRadio
                                  ? const Color(0xFF3B82F6)
                                  : AppColors.accent,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            channel.isRadio ? 'RADIO' : 'EN VIVO',
                            style: AppTextStyles.mono(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: channel.isRadio
                                  ? const Color(0xFF3B82F6)
                                  : AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (!channel.isRadio && viewers > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.visibility_outlined,
                            size: 12,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$viewers',
                            style: AppTextStyles.mono(
                              fontSize: 10.5,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    else
                      const Icon(
                        Icons.play_circle_fill,
                        size: 18,
                        color: AppColors.accent,
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
}

/// Abre el reproductor en vivo de un canal de TV o emisora de radio.
void showTvPlayerSheet(
  BuildContext context,
  WidgetRef ref,
  TvChannel channel,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0D0E11),
    barrierColor: AppColors.modalBackdrop,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
    ),
    builder: (context) => _TvPlayerSheet(channel: channel),
  );
}

class _TvPlayerSheet extends ConsumerStatefulWidget {
  const _TvPlayerSheet({required this.channel});

  final TvChannel channel;

  @override
  ConsumerState<_TvPlayerSheet> createState() => _TvPlayerSheetState();
}

class _TvPlayerSheetState extends ConsumerState<_TvPlayerSheet> {
  VideoPlayerController? _videoController;
  Timer? _heartbeatTimer;
  late final String _sessionId;
  bool _loadingHls = false;
  String? _hlsError;
  bool _useWebViewFallback = false;

  @override
  void initState() {
    super.initState();
    _sessionId = 'tv_${DateTime.now().millisecondsSinceEpoch}';
    if (!widget.channel.isRadio) {
      _sendHeartbeat();
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _sendHeartbeat(),
      );
    }
    if (widget.channel.stream.isHls) {
      _initHlsPlayer();
    }
  }

  void _sendHeartbeat() {
    ref.read(catalogApiProvider).tvHeartbeat(
          sessionId: _sessionId,
          contentId: widget.channel.id,
        );
  }

  Future<void> _initHlsPlayer() async {
    final url = widget.channel.stream.url;
    if (url.isEmpty) {
      setState(() => _hlsError = 'La señal de este canal no está disponible.');
      return;
    }

    // Al recargar la señal se libera el reproductor anterior; si no, seguía
    // sonando en segundo plano aunque ya no se mostrara.
    final previous = _videoController;
    _videoController = null;
    setState(() {
      _loadingHls = true;
      _hlsError = null;
    });
    await previous?.pause();
    await previous?.dispose();

    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      _videoController = controller;
      await controller.initialize();
      // El overlay pudo cerrarse mientras se conectaba: no arrancar audio
      // huérfano.
      if (!mounted || _videoController != controller) {
        await controller.dispose();
        return;
      }
      await controller.play();
      if (!mounted) return;
      setState(() => _loadingHls = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingHls = false;
        _hlsError = 'No se pudo iniciar la señal directa.';
      });
    }
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    if (!widget.channel.isRadio) {
      ref.read(catalogApiProvider).tvLeave(
            sessionId: _sessionId,
            contentId: widget.channel.id,
          );
    }
    final controller = _videoController;
    _videoController = null;
    controller?.pause();
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final useWebView = channel.stream.isEmbed || _useWebViewFallback;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 42,
                    height: 42,
                    color: AppColors.surfaceSecondary,
                    child: channel.logoUrl.isEmpty
                        ? Icon(
                            channel.isRadio ? Icons.radio : Icons.live_tv,
                            color: AppColors.textMuted,
                          )
                        : AppCachedImage(
                            imageUrl: channel.logoUrl,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        style: AppTextStyles.body(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        channel.tag?.isNotEmpty == true
                            ? '${channel.groupTitle} · ${channel.tag}'
                            : channel.groupTitle,
                        style: AppTextStyles.body(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: Container(
                width: double.infinity,
                height: channel.isRadio ? 190 : 230,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: useWebView
                    ? _EmbeddedStreamView(url: channel.stream.url)
                    : _buildHlsView(),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (channel.stream.isHls &&
                    _videoController != null &&
                    _videoController!.value.isInitialized) ...[
                  IconButton.filledTonal(
                    onPressed: () {
                      final ctrl = _videoController!;
                      setState(() {
                        ctrl.value.isPlaying ? ctrl.pause() : ctrl.play();
                      });
                    },
                    icon: Icon(
                      _videoController!.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _initHlsPlayer,
                    tooltip: 'Recargar señal',
                    icon: const Icon(Icons.refresh),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () => _openFullscreen(_videoController!),
                    tooltip: 'Pantalla completa',
                    icon: const Icon(Icons.fullscreen),
                  ),
                ],
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => DeviceChannel.openUrl(channel.stream.url),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Abrir en navegador'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFullscreen(VideoPlayerController controller) async {
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        pageBuilder: (_, _, _) => _TvFullscreenPage(
          controller: controller,
          title: widget.channel.name,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _buildHlsView() {
    if (_loadingHls) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.accent),
            SizedBox(height: 10),
            Text(
              'Conectando con la señal en vivo…',
              style: TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ],
        ),
      );
    }

    if (_hlsError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.danger,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              _hlsError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _initHlsPlayer,
                  child: const Text('Reintentar'),
                ),
                ElevatedButton(
                  onPressed: () => setState(() => _useWebViewFallback = true),
                  child: const Text('Modo alternativo'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio > 0
            ? controller.value.aspectRatio
            : 16 / 9,
        child: VideoPlayer(controller),
      ),
    );
  }
}

/// Canal HLS a pantalla completa: horizontal, sin barras del sistema y con
/// controles que se ocultan solos. Usa el mismo reproductor del panel.
class _TvFullscreenPage extends StatefulWidget {
  const _TvFullscreenPage({required this.controller, required this.title});

  final VideoPlayerController controller;
  final String title;

  @override
  State<_TvFullscreenPage> createState() => _TvFullscreenPageState();
}

class _TvFullscreenPageState extends State<_TvFullscreenPage> {
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    widget.controller.addListener(_onTick);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onTick);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  /// Mando de Google TV: OK y Play/Pausa pausan o reanudan; las flechas
  /// enseñan los controles (para llegar a "Salir"). Si un botón tiene el
  /// foco, las teclas son suyas.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final controller = widget.controller;
    void togglePlay() {
      controller.value.isPlaying ? controller.pause() : controller.play();
      setState(() => _showControls = true);
      _scheduleHide();
    }

    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.space) {
      togglePlay();
      return KeyEventResult.handled;
    }
    if (!node.hasPrimaryFocus) {
      _scheduleHide();
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      togglePlay();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (!_showControls) {
        setState(() => _showControls = true);
        _scheduleHide();
        return KeyEventResult.handled;
      }
      _scheduleHide();
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final playing = controller.value.isPlaying;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio > 0
                    ? controller.value.aspectRatio
                    : 16 / 9,
                child: VideoPlayer(controller),
              ),
            ),
            if (controller.value.isBuffering)
              const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            AnimatedOpacity(
              opacity: _showControls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Container(
                  color: Colors.black38,
                  child: SafeArea(
                    child: Stack(
                      children: [
                        Positioned(
                          top: 8,
                          left: 8,
                          right: 8,
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: 'Salir de pantalla completa',
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(
                                  Icons.fullscreen_exit,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.body(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Center(
                          child: IconButton.filled(
                            iconSize: 40,
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.accent,
                            ),
                            onPressed: () {
                              playing ? controller.pause() : controller.play();
                              _scheduleHide();
                            },
                            icon: Icon(
                              playing ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _EmbeddedStreamView extends StatelessWidget {
  const _EmbeddedStreamView({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: 'qvatube/webview',
        creationParams: <String, dynamic>{'url': url},
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return Center(
      child: ElevatedButton.icon(
        onPressed: () => DeviceChannel.openUrl(url),
        icon: const Icon(Icons.open_in_new),
        label: const Text('Abrir señal en vivo'),
      ),
    );
  }
}
