import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/platform/device_channel.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/app_cached_image.dart';
import '../../../catalog/application/catalog_providers.dart';
import '../../../catalog/domain/catalog_models.dart';

/// Modal interactivo de detalle y descarga de contenido (película o serie/anime/novela)
/// diseñado idéntico a las pantallas de referencia de QvaTube.
void showContentDetailSheet(BuildContext context, CatalogItem item) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0D0E11),
    barrierColor: AppColors.modalBackdrop,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
    ),
    builder: (context) => _ContentDetailSheet(item: item),
  );
}

class _ContentDetailSheet extends ConsumerStatefulWidget {
  const _ContentDetailSheet({required this.item});

  final CatalogItem item;

  @override
  ConsumerState<_ContentDetailSheet> createState() =>
      _ContentDetailSheetState();
}

class _ContentDetailSheetState extends ConsumerState<_ContentDetailSheet> {
  bool _loadingAction = false;
  bool _loadingEpisodes = false;
  bool _loadingInfo = false;
  bool _isUnlimitedPlan = false;
  ContentInfo? _info;
  List<Map<String, dynamic>> _episodes = [];
  String? _episodesError;
  int _selectedSeason = 1;

  bool get _isSeries =>
      widget.item.isSeries ||
      widget.item.categoryKey == 'series' ||
      widget.item.categoryKey == 'anime' ||
      widget.item.categoryKey == 'novela';

  String? get _title {
    final title = widget.item.title;
    return title == null || title.isEmpty ? null : title;
  }

  @override
  void initState() {
    super.initState();
    _fetchInfo();
    if (_isSeries) {
      _fetchEpisodes();
      _fetchPlan();
    }
  }

  Future<void> _fetchInfo() async {
    final title = _title;
    final type = widget.item.tmdbType;
    if (title == null || type == null || type.isEmpty) return;

    setState(() => _loadingInfo = true);
    try {
      final info = await ref.read(catalogApiProvider).info(title, type: type);
      if (!mounted) return;
      setState(() {
        _info = info;
        _loadingInfo = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingInfo = false);
    }
  }

  Future<void> _fetchPlan() async {
    try {
      final result = await ref.read(planUsageProvider.future);
      if (!mounted) return;
      setState(() => _isUnlimitedPlan = result.usage?.unlimited ?? false);
    } catch (_) {
      // Sin sesión o sin red: se mantiene oculto el botón de temporada.
    }
  }

  Future<void> _fetchEpisodes() async {
    setState(() {
      _loadingEpisodes = true;
      _episodesError = null;
    });

    try {
      final list = await ref
          .read(catalogApiProvider)
          .episodes(categoryKey: widget.item.categoryKey, title: _title);
      if (!mounted) return;
      setState(() {
        _episodes = list;
        _loadingEpisodes = false;
        _selectedSeason = _defaultSeason(list);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingEpisodes = false;
        _episodes = const [];
        _episodesError = 'No se pudieron cargar los episodios.';
      });
    }
  }

  int _defaultSeason(List<Map<String, dynamic>> episodes) {
    final seasons = <int>{
      for (final ep in episodes) (ep['season'] as num?)?.toInt() ?? 0,
    };
    if (seasons.isEmpty) return 1;
    final numbered = seasons.where((s) => s > 0).toList()..sort();
    if (numbered.isNotEmpty) return numbered.first;
    final all = seasons.toList()..sort();
    return all.first;
  }

  List<int> get _seasons {
    final seasons = <int>{
      for (final ep in _episodes) (ep['season'] as num?)?.toInt() ?? 0,
    };
    return seasons.toList()..sort();
  }

  List<Map<String, dynamic>> get _seasonEpisodes => _episodes
      .where((ep) => ((ep['season'] as num?)?.toInt() ?? 0) == _selectedSeason)
      .toList();

  String _seasonLabel(int season) {
    if (season > 0) return 'Temporada $season';
    if (season == -1) return 'OVA';
    if (season == -2) return 'Especiales';
    if (season == -3) return 'ONA';
    if (season < -3) return 'Especial T${season + 1000}';
    return 'Otros';
  }

  String _episodeLabel(Map<String, dynamic> ep, int index) {
    final season = (ep['season'] as num?)?.toInt() ?? 0;
    final number = (ep['episode'] as num?)?.toInt();
    final padded = number != null
        ? number.toString().padLeft(2, '0')
        : (index + 1).toString().padLeft(2, '0');
    if (season > 0) return 'T$season · E$padded';
    if (season == -1) return 'OVA $padded';
    if (season == -2) return 'Especial $padded';
    if (season == -3) return 'ONA $padded';
    return 'E$padded';
  }

  String? _downloadLink(Map<String, dynamic> response) {
    final url =
        response['url']?.toString() ??
        response['deep_link']?.toString() ??
        response['telegram_url']?.toString();
    return url == null || url.isEmpty ? null : url;
  }

  Future<void> _openTelegram(String fallbackPayload) async {
    final botConfig = await ref
        .read(siteConfigProvider.future)
        .catchError((_) => const SiteConfig());
    final bot = botConfig.botUsername ?? 'qvatube_bot';
    await DeviceChannel.openUrl('https://t.me/$bot?start=$fallbackPayload');
  }

  Future<void> _handleDownloadMovie() async {
    final chatId = widget.item.chatId;
    final msgId = widget.item.msgId;

    if (chatId == null || msgId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este contenido no tiene identificador de descarga asignado.',
          ),
        ),
      );
      return;
    }

    setState(() => _loadingAction = true);
    try {
      final response = await ref
          .read(catalogApiProvider)
          .authorizeDownload(chatId: chatId, msgId: msgId);
      if (!mounted) return;
      setState(() => _loadingAction = false);

      final url = _downloadLink(response);
      if (url != null) {
        await DeviceChannel.openUrl(url);
      } else {
        await _openTelegram('dl_${chatId}_$msgId');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingAction = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAction = false);
      await _openTelegram('dl_${chatId}_$msgId');
    }
  }

  Future<void> _handleDownloadSeason() async {
    final categoryKey = widget.item.categoryKey;
    final title = _title;
    if (categoryKey == null || categoryKey.isEmpty || title == null) return;

    setState(() => _loadingAction = true);
    try {
      final response = await ref
          .read(catalogApiProvider)
          .authorizeSeasonDownload(
            categoryKey: categoryKey,
            title: title,
            season: _selectedSeason,
          );
      if (!mounted) return;
      setState(() => _loadingAction = false);

      final url = _downloadLink(response);
      if (url != null) {
        await DeviceChannel.openUrl(url);
      } else {
        await _openTelegram('season_${categoryKey}_$_selectedSeason');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingAction = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAction = false);
      await _openTelegram('season_${categoryKey}_$_selectedSeason');
    }
  }

  Future<void> _handleDownloadEpisode(Map<String, dynamic> episode) async {
    final chatId = (episode['chat_id'] as num?)?.toInt() ?? widget.item.chatId;
    final msgId = (episode['msg_id'] as num?)?.toInt() ?? widget.item.msgId;

    if (chatId == null || msgId == null) return;

    try {
      final response = await ref
          .read(catalogApiProvider)
          .authorizeDownload(chatId: chatId, msgId: msgId);
      final url = _downloadLink(response);

      if (url != null) {
        await DeviceChannel.openUrl(url);
      } else {
        await _openTelegram('dl_${chatId}_$msgId');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      await _openTelegram('dl_${chatId}_$msgId');
    }
  }

  void _openTrailer() {
    final key = _info?.trailerKey;
    if (key == null || key.isEmpty) return;
    DeviceChannel.openUrl('https://www.youtube.com/watch?v=$key');
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final info = _info;

    final title = info?.title ?? item.title ?? 'Sin título';
    final year = info?.hasYear == true ? info!.year : null;
    final rating = info?.hasRating == true ? info!.rating : null;
    final overview = info?.hasOverview == true
        ? info!.overview!
        : (item.genres != null && item.genres!.isNotEmpty
              ? 'Sin sinopsis disponible.'
              : 'Película y serie disponible para reproducir en streaming o '
                    'descargar directamente a tu dispositivo a través de Telegram '
                    'sin consumo extra de datos.');
    final cast = info?.cast ?? const <CastMember>[];
    final trailerKey = info?.trailerKey;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.toUpperCase(),
                        style: AppTextStyles.display(
                          fontSize: 22,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (year != null || rating != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (year != null)
                              Text(
                                year,
                                style: AppTextStyles.mono(
                                  fontSize: 12,
                                  color: const Color(0xFFFF3D1A),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            if (year != null && rating != null)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  '·',
                                  style: TextStyle(color: Colors.white38),
                                ),
                              ),
                            if (rating != null)
                              Text(
                                rating,
                                style: AppTextStyles.mono(
                                  fontSize: 12,
                                  color: const Color(0xFFFF3D1A),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                _HeaderActionChip(
                  icon: Icons.share_outlined,
                  label: 'Compartir',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enlace copiado al portapapeles.'),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                _HeaderActionChip(
                  icon: Icons.flag_outlined,
                  label: 'Reportar',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Reporte enviado a los administradores.'),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingInfo && info == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else
              Text(
                overview,
                style: AppTextStyles.body(
                  fontSize: 12.5,
                  color: const Color(0xFF9CA3AF),
                  height: 1.4,
                ),
              ),
            if (cast.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'REPARTO PRINCIPAL',
                style: AppTextStyles.display(
                  fontSize: 13,
                  letterSpacing: 0.5,
                  color: const Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(height: 10),
              _CastRow(cast: cast),
            ],
            if (trailerKey != null && trailerKey.isNotEmpty) ...[
              const SizedBox(height: 16),
              InkWell(
                onTap: _openTrailer,
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF16181D),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Center(
                    child: Text(
                      'Ver tráiler',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (!_isSeries) ...[
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3D1A),
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: const Center(
                        child: Text(
                          'Reproducir',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _loadingAction ? null : _handleDownloadMovie,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF16181D),
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Center(
                          child: _loadingAction
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Descargar',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'La descarga necesita Telegram instalado',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ),
            ],
            if (_isSeries) ...[
              if (_loadingEpisodes)
                const Column(
                  children: [
                    SizedBox(height: 16),
                    CircularProgressIndicator(strokeWidth: 2),
                    SizedBox(height: 16),
                  ],
                )
              else if (_episodesError != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _episodesError!,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                )
              else if (_episodes.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No hay episodios disponibles.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                )
              else ...[
                if (_seasons.length > 1)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final season in _seasons)
                        ChoiceChip(
                          label: Text(_seasonLabel(season)),
                          selected: season == _selectedSeason,
                          onSelected: (_) =>
                              setState(() => _selectedSeason = season),
                          selectedColor: const Color(0xFFFF3D1A),
                          backgroundColor: const Color(0xFF16181D),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: season == _selectedSeason
                                ? Colors.white
                                : Colors.white70,
                          ),
                          side: BorderSide(
                            color: season == _selectedSeason
                                ? const Color(0xFFFF3D1A)
                                : Colors.white12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                    ],
                  ),
                if (_seasons.length > 1) const SizedBox(height: 12),
                if (_isUnlimitedPlan && _seasonEpisodes.length > 1) ...[
                  InkWell(
                    onTap: _loadingAction ? null : _handleDownloadSeason,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16181D),
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        border: Border.all(color: const Color(0xFFFF3D1A)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.arrow_downward,
                            size: 15,
                            color: Color(0xFFFF3D1A),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Descargar ${_seasonLabel(_selectedSeason)}',
                              style: const TextStyle(
                                color: Color(0xFFFF3D1A),
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3D1A),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_seasonEpisodes.length} EP',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _seasonEpisodes.length,
                  separatorBuilder: (context, index) =>
                      const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final ep = _seasonEpisodes[index];
                    final size = formatFileSize((ep['size'] as num?)?.toInt());

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            size: 16,
                            color: Colors.white30,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _episodeLabel(ep, index),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (size.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    size,
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFFF3D1A),
                            ),
                            child: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          InkWell(
                            onTap: () => _handleDownloadEpisode(ep),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                              child: const Icon(
                                Icons.download,
                                color: Colors.white70,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _HeaderActionChip extends StatelessWidget {
  const _HeaderActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF16181D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white70),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11.5, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _CastRow extends StatelessWidget {
  const _CastRow({required this.cast});

  final List<CastMember> cast;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cast.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final actor = cast[index];
          return SizedBox(
            width: 58,
            child: Column(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: actor.photoUrl.isEmpty
                        ? Container(
                            color: Colors.white10,
                            child: const Icon(
                              Icons.person,
                              color: Colors.white54,
                              size: 22,
                            ),
                          )
                        : AppCachedImage(
                            imageUrl: actor.photoUrl,
                            fit: BoxFit.cover,
                            errorWidget: Container(
                              color: Colors.white10,
                              child: const Icon(
                                Icons.person,
                                color: Colors.white54,
                                size: 22,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  actor.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  actor.character ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: Colors.white38),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
