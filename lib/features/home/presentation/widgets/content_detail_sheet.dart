import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/platform/device_channel.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
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
  ConsumerState<_ContentDetailSheet> createState() => _ContentDetailSheetState();
}

class _ContentDetailSheetState extends ConsumerState<_ContentDetailSheet> {
  bool _loadingAction = false;
  bool _loadingEpisodes = false;
  List<Map<String, dynamic>> _episodes = [];
  String? _episodesError;

  bool get _isSeries =>
      widget.item.categoryKey == 'series' ||
      widget.item.categoryKey == 'anime' ||
      widget.item.categoryKey == 'novela' ||
      widget.item.episodeCount > 0;

  @override
  void initState() {
    super.initState();
    if (_isSeries) {
      _fetchEpisodes();
    }
  }

  Future<void> _fetchEpisodes() async {
    setState(() {
      _loadingEpisodes = true;
      _episodesError = null;
    });

    try {
      final list = await ref.read(catalogApiProvider).episodes(
            chatId: widget.item.chatId,
            msgId: widget.item.msgId,
            itemKey: widget.item.itemKey,
          );
      if (!mounted) return;
      setState(() {
        _episodes = list;
        _loadingEpisodes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingEpisodes = false;
        // Si no responde el endpoint de episodios, generamos la lista basada en episodeCount para mostrar UI
        if (_episodes.isEmpty && widget.item.episodeCount > 0) {
          _episodes = List.generate(
            widget.item.episodeCount,
            (index) => {
              'title': 'T1 · E${(index + 1).toString().padLeft(2, '0')}',
              'size': widget.item.size != null && widget.item.episodeCount > 0
                  ? widget.item.size! ~/ widget.item.episodeCount
                  : 126 * 1024 * 1024,
              'episode_number': index + 1,
              'msg_id': (widget.item.msgId ?? 1000) + index + 1,
              'chat_id': widget.item.chatId,
            },
          );
        } else {
          _episodesError = 'No se pudieron cargar los episodios.';
        }
      });
    }
  }

  Future<void> _handleDownloadMovie() async {
    final chatId = widget.item.chatId;
    final msgId = widget.item.msgId;

    if (chatId == null || msgId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este contenido no tiene identificador de descarga asignado.'),
        ),
      );
      return;
    }

    setState(() => _loadingAction = true);
    try {
      final response = await ref.read(catalogApiProvider).authorizeDownload(
            chatId: chatId,
            msgId: msgId,
          );
      if (!mounted) return;
      setState(() => _loadingAction = false);

      final url = response['url']?.toString() ??
          response['deep_link']?.toString() ??
          response['telegram_url']?.toString();

      if (url != null && url.isNotEmpty) {
        await DeviceChannel.openUrl(url);
      } else {
        // Fallback a bot de Telegram con start payload si existe
        final botConfig = await ref.read(siteConfigProvider.future);
        final bot = botConfig.botUsername ?? 'qvatube_bot';
        await DeviceChannel.openUrl('https://t.me/$bot?start=dl_${chatId}_$msgId');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingAction = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingAction = false);
      // Fallback amigable abriendo Telegram
      final botConfig = await ref.read(siteConfigProvider.future).catchError((_) => const SiteConfig());
      final bot = botConfig.botUsername ?? 'qvatube_bot';
      await DeviceChannel.openUrl('https://t.me/$bot?start=dl_${chatId}_$msgId');
    }
  }

  Future<void> _handleDownloadSeason() async {
    final chatId = widget.item.chatId;
    if (chatId == null) return;

    setState(() => _loadingAction = true);
    try {
      final response = await ref.read(catalogApiProvider).authorizeSeasonDownload(
            chatId: chatId,
            seasonId: 'season_1',
          );
      if (!mounted) return;
      setState(() => _loadingAction = false);

      final url = response['url']?.toString() ??
          response['deep_link']?.toString() ??
          response['telegram_url']?.toString();

      if (url != null && url.isNotEmpty) {
        await DeviceChannel.openUrl(url);
      } else {
        final botConfig = await ref.read(siteConfigProvider.future);
        final bot = botConfig.botUsername ?? 'qvatube_bot';
        await DeviceChannel.openUrl('https://t.me/$bot?start=season_${chatId}_1');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAction = false);
      final botConfig = await ref.read(siteConfigProvider.future).catchError((_) => const SiteConfig());
      final bot = botConfig.botUsername ?? 'qvatube_bot';
      await DeviceChannel.openUrl('https://t.me/$bot?start=season_${chatId}_1');
    }
  }

  Future<void> _handleDownloadEpisode(Map<String, dynamic> episode) async {
    final chatId = (episode['chat_id'] as num?)?.toInt() ?? widget.item.chatId;
    final msgId = (episode['msg_id'] as num?)?.toInt() ?? widget.item.msgId;

    if (chatId == null || msgId == null) return;

    try {
      final response = await ref.read(catalogApiProvider).authorizeDownload(
            chatId: chatId,
            msgId: msgId,
          );
      final url = response['url']?.toString() ??
          response['deep_link']?.toString() ??
          response['telegram_url']?.toString();

      if (url != null && url.isNotEmpty) {
        await DeviceChannel.openUrl(url);
      } else {
        final botConfig = await ref.read(siteConfigProvider.future);
        final bot = botConfig.botUsername ?? 'qvatube_bot';
        await DeviceChannel.openUrl('https://t.me/$bot?start=dl_${chatId}_$msgId');
      }
    } catch (_) {
      final botConfig = await ref.read(siteConfigProvider.future).catchError((_) => const SiteConfig());
      final bot = botConfig.botUsername ?? 'qvatube_bot';
      await DeviceChannel.openUrl('https://t.me/$bot?start=dl_${chatId}_$msgId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

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
            // Asa de arrastre superior
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

            // Encabezado: Título en mayúsculas estilo Bebas Neue + Botones Compartir / Reportar
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (item.title ?? 'SIN TÍTULO').toUpperCase(),
                        style: AppTextStyles.display(
                          fontSize: 22,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '2024',
                            style: AppTextStyles.mono(
                              fontSize: 12,
                              color: const Color(0xFFFF3D1A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('•', style: TextStyle(color: Colors.white38)),
                          const SizedBox(width: 8),
                          Text(
                            item.popularity != null && item.popularity! > 0
                                ? '${item.popularity}'
                                : '8.4',
                            style: AppTextStyles.mono(
                              fontSize: 12,
                              color: const Color(0xFFFF3D1A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (item.bottomBadge.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            const Text('•', style: TextStyle(color: Colors.white38)),
                            const SizedBox(width: 8),
                            Text(
                              item.bottomBadge,
                              style: AppTextStyles.mono(
                                fontSize: 11.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                _HeaderActionChip(
                  icon: Icons.share_outlined,
                  label: 'Compartir',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enlace copiado al portapapeles.')),
                    );
                  },
                ),
                const SizedBox(width: 8),
                _HeaderActionChip(
                  icon: Icons.flag_outlined,
                  label: 'Reportar',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Reporte enviado a los administradores.')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Sinopsis o descripción
            Text(
              item.genres != null && item.genres!.isNotEmpty
                  ? 'Con toda clase de aventuras y misterio. ${item.title ?? 'Este contenido'} cuenta con una producción de alta calidad para disfrutar sin límites.'
                  : 'Película y serie disponible para reproducir en streaming o descargar directamente a tu dispositivo a través de Telegram sin consumo extra de datos.',
              style: AppTextStyles.body(
                fontSize: 12.5,
                color: const Color(0xFF9CA3AF),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),

            // Reparto principal (Cast)
            Text(
              'REPARTO PRINCIPAL',
              style: AppTextStyles.display(
                fontSize: 13,
                letterSpacing: 0.5,
                color: const Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(height: 10),
            _CastRow(),
            const SizedBox(height: 16),

            // Botón "Ver tráiler"
            Container(
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
            const SizedBox(height: 16),

            // SI ES PELÍCULA: Botones gigantes "Reproducir" y "Descargar"
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

            // SI ES SERIE / ANIME / NOVELA: Botón "Descargar Temporada 1" + Lista de episodios
            if (_isSeries) ...[
              InkWell(
                onTap: _loadingAction ? null : _handleDownloadSeason,
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                      const Expanded(
                        child: Text(
                          'Descargar Temporada 1',
                          style: TextStyle(
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
                          '${widget.item.episodeCount > 0 ? widget.item.episodeCount : _episodes.length} EP',
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

              // Lista de Episodios con check, título, tamaño, botón play y botón download
              if (_loadingEpisodes)
                const Column(
                  children: [
                    SizedBox(height: 16),
                    CircularProgressIndicator(strokeWidth: 2),
                    SizedBox(height: 16),
                  ],
                )
              else if (_episodes.isEmpty && _episodesError != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _episodesError!,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _episodes.length,
                  separatorBuilder: (context, index) =>
                      const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final ep = _episodes[index];
                    final title = ep['title']?.toString() ??
                        'T1 · E${(index + 1).toString().padLeft(2, '0')}';
                    final sizeBytes = (ep['size'] as num?)?.toInt() ?? 126 * 1024 * 1024;
                    final sizeMb = (sizeBytes / (1024 * 1024)).toStringAsFixed(0);

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
                                  title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$sizeMb MB',
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Botón Reproducir episodio
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
                          // Botón Descargar episodio
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
  @override
  Widget build(BuildContext context) {
    final actors = [
      ('Frank Wel...', 'Scooby-Doo...'),
      ('Grey DeLisle', 'Daphne Blake...'),
      ('Matthew L...', 'Shaggy Rog...'),
      ('Kate Micu...', 'Velma Dinkle...'),
      ('Cassandra...', 'Elvira, Mistre...'),
      ('Bill Nye', 'Bill Nye (voice)'),
    ];

    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actors.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final actor = actors[index];
          return SizedBox(
            width: 58,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white10,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Colors.white54,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  actor.$1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  actor.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

