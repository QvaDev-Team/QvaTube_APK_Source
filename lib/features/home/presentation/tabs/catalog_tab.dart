import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../widgets/content_placeholders.dart';

/// Pestaña de catálogo (Popular, Televisión, Películas, Series).
///
/// Incluye la cabecera de filtros por género y el conmutador de ordenamiento
/// (spec §6.4). El contenido se rellenará con `/api/movies`, `/api/series`,
/// `/api/tv/...` y `/api/recommendations` cuando se defina el modelo de datos.
class CatalogTab extends StatefulWidget {
  const CatalogTab({
    super.key,
    required this.title,
    required this.icon,
    this.aspectRatio = 2 / 3,
    this.description,
  });

  final String title;
  final IconData icon;
  final double aspectRatio;
  final String? description;

  @override
  State<CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<CatalogTab> {
  String _genre = 'Todos los géneros';
  bool _sortAlphabetical = false;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(widget.icon, size: 20, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text(
                      widget.title,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                  ],
                ),
                if (widget.description != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    widget.description!,
                    style: AppTextStyles.body(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                _CatalogHeaderCard(
                  genre: _genre,
                  sortAlphabetical: _sortAlphabetical,
                  onGenreTap: () => _showGenrePicker(context),
                  onSortToggle: () => setState(
                    () => _sortAlphabetical = !_sortAlphabetical,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 10,
              // El póster 2:3 necesita más alto que la Quadrícula cuadrada.
              childAspectRatio: widget.aspectRatio == 1 ? 0.85 : 0.6,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return PosterGridItem(
                  title: 'Título ${index + 1}',
                  aspectRatio: widget.aspectRatio,
                );
              },
              childCount: 9,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showGenrePicker(BuildContext context) async {
    const genres = [
      'Todos los géneros',
      'Acción',
      'Terror',
      'Comedia',
      'Ciencia ficción',
      'Novelas',
      'Anime',
      'Infantiles',
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      barrierColor: AppColors.modalBackdrop,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filtrar por género',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final genre in genres)
                      ChoiceChip(
                        label: Text(genre),
                        selected: genre == _genre,
                        onSelected: (_) => Navigator.of(context).pop(genre),
                        selectedColor: AppColors.accentSoft,
                        backgroundColor: AppColors.surfaceSecondary,
                        labelStyle: AppTextStyles.body(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: genre == _genre
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                        side: BorderSide(
                          color: genre == _genre
                              ? AppColors.accent
                              : AppColors.border,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null && mounted) {
      setState(() => _genre = selected);
    }
  }
}

/// Tarjeta de cabecera con filtros y ordenamiento (spec §6.4).
class _CatalogHeaderCard extends StatelessWidget {
  const _CatalogHeaderCard({
    required this.genre,
    required this.sortAlphabetical,
    required this.onGenreTap,
    required this.onSortToggle,
  });

  final String genre;
  final bool sortAlphabetical;
  final VoidCallback onGenreTap;
  final VoidCallback onSortToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: AppColors.cardHeaderGradient,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onGenreTap,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceSecondary,
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.filter_list,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      genre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (genre != 'Todos los géneros')
                    const Icon(
                      Icons.close,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.surfaceSecondary,
              borderRadius: BorderRadius.circular(AppRadii.pill),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _SortOption(
                    label: 'Recientes',
                    icon: Icons.schedule,
                    selected: !sortAlphabetical,
                    onTap: onSortToggle,
                  ),
                ),
                Expanded(
                  child: _SortOption(
                    label: 'A-Z',
                    icon: Icons.sort_by_alpha,
                    selected: sortAlphabetical,
                    onTap: onSortToggle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  const _SortOption({
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? AppColors.accent : AppColors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.body(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.accent : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
