import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/app_skeleton.dart';
import '../../../catalog/application/catalog_providers.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../widgets/content_detail_sheet.dart';
import '../widgets/media_card.dart';

/// Pestaña de catálogo conectada a `GET /api/movies`, `GET /api/genres` y
/// `GET /api/categories`.
class CatalogTab extends ConsumerStatefulWidget {
  const CatalogTab({
    super.key,
    required this.title,
    required this.icon,
    this.categoryKey,
    this.aspectRatio = 2 / 3,
    this.description,
    this.allowSort = true,
    this.allowGenreFilter = true,
    this.gridAspectRatio = 0.5,
  });

  final String title;
  final IconData icon;
  final String? categoryKey;
  final double aspectRatio;
  final String? description;
  final bool allowSort;
  final bool allowGenreFilter;

  /// Proporción del alto de cada tarjeta de la retícula (2:3 → 0.5,
  /// 1:1 para música → 0.68).
  final double gridAspectRatio;

  @override
  ConsumerState<CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends ConsumerState<CatalogTab> {
  final _scrollController = ScrollController();

  final List<CatalogItem> _items = [];
  List<String> _genres = const [];
  String? _genre;
  String _sort = 'date';
  int _page = 1;
  int _pages = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (_loadingMore) return;
    if (!reset && _page >= _pages) return;

    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _items.clear();
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final page = await ref
          .read(catalogApiProvider)
          .catalog(
            categoryKey: widget.categoryKey,
            page: reset ? 1 : _page + 1,
            genre: _genre,
            sort: _sort,
          );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _page = page.page;
        _pages = page.pages;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = 'No se pudo cargar el catálogo.';
      });
    }
  }

  Future<void> _loadGenres() async {
    final key = widget.categoryKey;
    if (key == null || key.isEmpty) return;
    try {
      final genres = await ref.read(catalogApiProvider).genres(key);
      if (!mounted) return;
      setState(() => _genres = genres);
    } catch (_) {
      // El filtro por género es opcional: si falla se muestra sin él.
    }
  }

  void _setSort(String sort) {
    if (_sort == sort) return;
    setState(() => _sort = sort);
    _load(reset: true);
  }

  void _setGenre(String? genre) {
    setState(() => _genre = genre);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: () => _load(reset: true),
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CatalogHeaderCard(
                    genre: _genre,
                    genres: _genres,
                    sort: _sort,
                    allowSort: widget.allowSort,
                    allowGenreFilter: widget.allowGenreFilter,
                    onGenreTap: () => _showGenrePicker(context),
                    onSortToggle: () =>
                        _setSort(_sort == 'date' ? 'alpha' : 'date'),
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            SliverToBoxAdapter(
              child: SkeletonCatalogGrid(
                itemCount: 9,
                gridAspectRatio: widget.gridAspectRatio,
              ),
            )
          else if (_error != null && _items.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body(
                        fontSize: 13,
                        color: AppColors.danger,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _load(reset: true),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          else if (_items.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    'No hay contenido con estos filtros.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 10,
                  childAspectRatio: widget.gridAspectRatio,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final item = _items[index];
                  return MediaCard(
                    item: item,
                    onTap: () => showContentDetailSheet(context, item),
                  );
                }, childCount: _items.length),
              ),
            ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showGenrePicker(BuildContext context) async {
    if (_genres.isEmpty) {
      await _loadGenres();
    }
    if (!context.mounted) return;
    final selected = await showModalBottomSheet<String?>(
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
                Flexible(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final genre in _genres)
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
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (selected != null) {
      _setGenre(selected == _genre ? null : selected);
    } else if (_genre != null) {
      // Se cerró la hoja con el botón de limpiar.
      _setGenre(null);
    }
  }
}

/// Tarjeta de cabecera con filtros y ordenamiento (spec §6.4).
class _CatalogHeaderCard extends StatelessWidget {
  const _CatalogHeaderCard({
    required this.genre,
    required this.genres,
    required this.sort,
    required this.allowSort,
    required this.allowGenreFilter,
    required this.onGenreTap,
    required this.onSortToggle,
  });

  final String? genre;
  final List<String> genres;
  final String sort;
  final bool allowSort;
  final bool allowGenreFilter;
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
          if (allowGenreFilter)
            InkWell(
              onTap: onGenreTap,
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
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
                        genre ?? 'Todos los géneros',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: genre == null
                              ? AppColors.textPrimary
                              : AppColors.accent,
                        ),
                      ),
                    ),
                    if (genre != null)
                      const Icon(
                        Icons.close,
                        size: 16,
                        color: AppColors.textMuted,
                      ),
                  ],
                ),
              ),
            ),
          if (allowSort) ...[
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
                      selected: sort == 'date',
                      onTap: onSortToggle,
                    ),
                  ),
                  Expanded(
                    child: _SortOption(
                      label: 'A-Z',
                      icon: Icons.sort_by_alpha,
                      selected: sort == 'alpha',
                      onTap: onSortToggle,
                    ),
                  ),
                ],
              ),
            ),
          ],
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

/// Ficha rápida de un contenido.
Future<void> showItemSheet(BuildContext context, CatalogItem item) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    barrierColor: AppColors.modalBackdrop,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
    ),
    builder: (context) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: SizedBox(
                      width: 56,
                      height: 84,
                      child: item.posterUrl.isEmpty
                          ? Container(color: AppColors.surfaceSecondary)
                          : Image.network(
                              item.posterUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(color: AppColors.surfaceSecondary),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title ?? 'Sin título',
                          style: AppTextStyles.body(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (item.genres != null)
                          Text(
                            item.genres!,
                            style: AppTextStyles.body(
                              fontSize: 12,
                              color: AppColors.accent,
                            ),
                          ),
                        const SizedBox(height: 6),
                        if (item.bottomBadge.isNotEmpty)
                          Text(
                            item.bottomBadge,
                            style: AppTextStyles.mono(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'El reproductor y la descarga se conectarán en la siguiente '
                'iteración (endpoint de autorización de descarga).',
                style: AppTextStyles.body(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
