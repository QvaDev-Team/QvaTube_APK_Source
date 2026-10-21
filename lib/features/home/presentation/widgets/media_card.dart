import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../catalog/domain/catalog_models.dart';

/// Tarjeta de contenido multimedia (spec §6.3).
///
/// - Póster 2:3 (o 1:1 para música/TV).
/// - Cinta "NUEVO" en la esquina superior izquierda.
/// - Badge inferior derecho con el tamaño o la cantidad de episodios.
/// - Badge inferior izquierdo con la popularidad.
/// - Barra de progreso roja pegada al borde inferior.
class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.item,
    this.width,
    this.onTap,
    this.showProgress = true,
    this.showNewBadge = true,
  });

  final CatalogItem item;
  final double? width;
  final VoidCallback? onTap;
  final bool showProgress;
  final bool showNewBadge;

  @override
  Widget build(BuildContext context) {
    final posterUrl = item.posterUrl;
    final badge = item.bottomBadge;

    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: item.square ? 1 : 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: posterUrl.isEmpty
                        ? _PosterPlaceholder(icon: item.categoryIcon)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            child: Image.network(
                              posterUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _PosterPlaceholder(icon: item.categoryIcon),
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return const _PosterPlaceholder();
                              },
                            ),
                          ),
                  ),
                  if (item.isNew && showNewBadge)
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          'NUEVO',
                          style: AppTextStyles.mono(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accentInk,
                          ),
                        ),
                      ),
                    ),
                  if ((item.popularity ?? 0) > 0)
                    Positioned(
                      left: 4,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xD10A0A0B),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.local_fire_department,
                              size: 9,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${item.popularity}',
                              style: AppTextStyles.mono(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (badge.isNotEmpty)
                    Positioned(
                      right: 4,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xD10A0A0B),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          badge,
                          style: AppTextStyles.mono(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  if (showProgress && (item.progressPct ?? 0) > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: (item.progressPct! / 100).clamp(0, 1),
                        minHeight: 3,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title ?? 'Sin título',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            if (item.artist != null && item.artist!.isNotEmpty)
              Text(
                item.artist!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body(
                  fontSize: 10.5,
                  color: AppColors.textMuted,
                ),
              )
            else if (item.genres != null && item.genres!.isNotEmpty)
              Text(
                item.genres!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body(
                  fontSize: 10.5,
                  color: AppColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder({this.icon});

  final String? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      child: Icon(
        _iconFor(icon),
        color: AppColors.textMuted,
        size: 24,
      ),
    );
  }

  static IconData _iconFor(String? key) {
    return switch (key) {
      'sparkle' => Icons.auto_awesome,
      'book' => Icons.menu_book,
      'music' => Icons.music_note,
      'heart' => Icons.favorite_border,
      'tv' => Icons.tv,
      _ => Icons.movie_filter_outlined,
    };
  }
}

/// Fila horizontal de tarjetas.
class MediaCarousel extends StatelessWidget {
  const MediaCarousel({
    super.key,
    required this.items,
    this.itemWidth = 122,
    this.onTap,
    this.showNewBadge = true,
  });

  final List<CatalogItem> items;
  final double itemWidth;
  final ValueChanged<CatalogItem>? onTap;
  final bool showNewBadge;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: itemWidth * 1.5 + 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          return MediaCard(
            width: itemWidth,
            item: item,
            showNewBadge: showNewBadge,
            onTap: onTap == null ? null : () => onTap!(item),
          );
        },
      ),
    );
  }
}
