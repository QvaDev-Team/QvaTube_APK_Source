import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/storage/app_preferences.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/app_skeleton.dart';
import '../../../catalog/application/catalog_providers.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../widgets/content_detail_sheet.dart';
import '../widgets/media_card.dart';
import '../widgets/media_player_screen.dart';

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
  static const int _pageLimit = 30;
  static const List<String> _azOrder = [
    '#',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];

  final _scrollController = ScrollController();
  final _jumpTargetKey = GlobalKey();
  final _headerKey = GlobalKey();

  /// Alto real de la cabecera (filtros); el índice A-Z empieza debajo.
  double _headerHeight = 0;

  final List<CatalogItem> _items = [];
  List<String> _genres = const [];
  List<CatalogLetter> _letters = const [];
  String? _genre;
  String _sort = 'date';
  String _musicPlayMode = 'linear';
  int _page = 1;
  int _pages = 1;
  int? _jumpTargetIndex;
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadingMusicPlayAll = false;
  String? _error;

  bool get _isMusic => widget.categoryKey == 'music';

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(sharedPreferencesProvider);
    _musicPlayMode = prefs.getString(AppConfig.musicPlayModeKey) == 'shuffle'
        ? 'shuffle'
        : 'linear';
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
            limit: _pageLimit,
            genre: _genre,
            sort: _sort,
          );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _page = page.page;
        _pages = page.pages;
        if (reset) _letters = page.letters;
        _jumpTargetIndex = null;
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
    setState(() {
      _sort = sort;
      if (sort != 'alpha') _letters = const [];
    });
    _load(reset: true);
  }

  void _setGenre(String? genre) {
    setState(() => _genre = genre);
    _load(reset: true);
  }

  Future<void> _setMusicPlayMode(String mode) async {
    if (_musicPlayMode == mode) return;
    setState(() => _musicPlayMode = mode);
    await ref
        .read(sharedPreferencesProvider)
        .setString(AppConfig.musicPlayModeKey, mode);
  }

  Future<void> _handlePlayAllCatalog() async {
    if (_loadingMusicPlayAll) return;
    setState(() => _loadingMusicPlayAll = true);
    try {
      final tracks = await ref
          .read(catalogApiProvider)
          .categoryTracks(categoryKey: widget.categoryKey);
      if (!mounted) return;

      final ordered = List<Map<String, dynamic>>.from(tracks);
      if (_musicPlayMode == 'shuffle') ordered.shuffle();

      final playlist = <PlayableMediaItem>[];
      for (final track in ordered) {
        final chatId = (track['chat_id'] as num?)?.toInt();
        final msgId = (track['msg_id'] as num?)?.toInt();
        if (chatId == null || msgId == null) continue;
        playlist.add(
          PlayableMediaItem(
            chatId: chatId,
            msgId: msgId,
            title: track['title']?.toString() ?? 'Pista',
            subtitle: track['artist']?.toString(),
            posterUrl: absoluteMediaUrl('/cover/$chatId/$msgId'),
            isAudio: true,
          ),
        );
      }

      if (playlist.isEmpty) {
        _showSnack('Todavía no hay canciones en esta categoría.');
        return;
      }

      await openMediaPlayer(context, playlist: playlist);
    } catch (_) {
      if (mounted) {
        _showSnack('No se pudo cargar el catálogo completo.');
      }
    } finally {
      if (mounted) setState(() => _loadingMusicPlayAll = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _letterFor(CatalogItem item) {
    final serverLetter = item.letter?.trim().toUpperCase();
    if (serverLetter != null && serverLetter.isNotEmpty) {
      return serverLetter;
    }
    final title = (item.title ?? '').trim();
    if (title.isEmpty) return '#';
    final first = title.substring(0, 1).toUpperCase();
    const accented = {
      'Á': 'A',
      'À': 'A',
      'Ä': 'A',
      'Â': 'A',
      'É': 'E',
      'È': 'E',
      'Ë': 'E',
      'Ê': 'E',
      'Í': 'I',
      'Ì': 'I',
      'Ï': 'I',
      'Î': 'I',
      'Ó': 'O',
      'Ò': 'O',
      'Ö': 'O',
      'Ô': 'O',
      'Ú': 'U',
      'Ù': 'U',
      'Ü': 'U',
      'Û': 'U',
      'Ñ': 'N',
    };
    final normalized = accented[first] ?? first;
    return RegExp(r'^[A-Z]$').hasMatch(normalized) ? normalized : '#';
  }

  CatalogLetter? _letterEntry(String letter) {
    if (_letters.isEmpty) return null;
    for (final entry in _letters) {
      if (entry.letter.toUpperCase() == letter) return entry;
    }
    final target = _azOrder.indexOf(letter);
    CatalogLetter? best;
    var bestDistance = 1 << 30;
    for (final entry in _letters) {
      final distance = (_azOrder.indexOf(entry.letter.toUpperCase()) - target)
          .abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = entry;
      }
    }
    return best;
  }

  Future<void> _jumpToLetter(String letter) async {
    if (_sort != 'alpha') return;
    final entry = _letterEntry(letter);
    if (entry == null) return;

    final loadedIndex = _items.indexWhere(
      (item) => _letterFor(item) == entry.letter.toUpperCase(),
    );
    if (loadedIndex >= 0) {
      _scrollToItem(loadedIndex);
      return;
    }

    final targetPage = (entry.index ~/ _pageLimit) + 1;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _items.clear();
      _jumpTargetIndex = null;
    });

    try {
      final page = await ref
          .read(catalogApiProvider)
          .catalog(
            categoryKey: widget.categoryKey,
            page: targetPage,
            limit: _pageLimit,
            genre: _genre,
            sort: _sort,
          );
      if (!mounted) return;
      final index = page.items.indexWhere(
        (item) => _letterFor(item) == entry.letter.toUpperCase(),
      );
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _page = page.page;
        _pages = page.pages;
        if (page.letters.isNotEmpty) _letters = page.letters;
        _jumpTargetIndex = index >= 0 ? index : 0;
        _loading = false;
      });
      _scrollToItem(_jumpTargetIndex ?? 0);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo saltar a la letra $letter.';
      });
    }
  }

  void _scrollToItem(int index) {
    setState(() => _jumpTargetIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _jumpTargetKey.currentContext;
      if (targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0.08,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final showAzIndex = _sort == 'alpha' && _letters.isNotEmpty;
    final allowGenreFilter = widget.allowGenreFilter && !_isMusic;
    // Popular no tiene orden ni géneros: sin esto quedaba una tarjeta vacía.
    final showHeader = widget.allowSort || allowGenreFilter || _isMusic;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());

    return Stack(
      children: [
        RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.surface,
          onRefresh: () => _load(reset: true),
          child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  key: _headerKey,
                  padding: EdgeInsets.fromLTRB(16, showHeader ? 16 : 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showHeader)
                        _CatalogHeaderCard(
                          genre: _genre,
                          genres: _genres,
                          sort: _sort,
                          allowSort: widget.allowSort,
                          allowGenreFilter: allowGenreFilter,
                          isMusic: _isMusic,
                          musicPlayMode: _musicPlayMode,
                          loadingMusicPlayAll: _loadingMusicPlayAll,
                          onGenreTap: () => _showGenrePicker(context),
                          onSortToggle: () =>
                              _setSort(_sort == 'date' ? 'alpha' : 'date'),
                          onPlayAll: _handlePlayAllCatalog,
                          onMusicPlayModeChanged: _setMusicPlayMode,
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
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    showAzIndex ? 32 : 16,
                    28,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 10,
                      childAspectRatio: widget.gridAspectRatio,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final item = _items[index];
                      final card = MediaCard(
                        item: item,
                        onTap: () => showContentDetailSheet(context, item),
                      );
                      if (index == _jumpTargetIndex) {
                        return KeyedSubtree(key: _jumpTargetKey, child: card);
                      }
                      return card;
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
        ),
        if (showAzIndex)
          Positioned(
            right: 0,
            top: _headerHeight + 8,
            bottom: 36,
            child: _AzIndex(
              available: {
                for (final entry in _letters) entry.letter.toUpperCase(),
              },
              onLetter: _jumpToLetter,
            ),
          ),
      ],
    );
  }

  void _measureHeader() {
    if (!mounted) return;
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final height = box.size.height;
    if ((height - _headerHeight).abs() > 0.5) {
      setState(() => _headerHeight = height);
    }
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
    required this.isMusic,
    required this.musicPlayMode,
    required this.loadingMusicPlayAll,
    required this.onGenreTap,
    required this.onSortToggle,
    required this.onPlayAll,
    required this.onMusicPlayModeChanged,
  });

  final String? genre;
  final List<String> genres;
  final String sort;
  final bool allowSort;
  final bool allowGenreFilter;
  final bool isMusic;
  final String musicPlayMode;
  final bool loadingMusicPlayAll;
  final VoidCallback onGenreTap;
  final VoidCallback onSortToggle;
  final VoidCallback onPlayAll;
  final ValueChanged<String> onMusicPlayModeChanged;

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
          if (isMusic) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: loadingMusicPlayAll ? null : onPlayAll,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              shape: BoxShape.circle,
                              boxShadow: AppColors.playGlow,
                            ),
                            child: loadingMusicPlayAll
                                ? const Padding(
                                    padding: EdgeInsets.all(9),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.accentInk,
                                    ),
                                  )
                                : const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 20,
                                    color: AppColors.accentInk,
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Reproducir todo el catálogo',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.body(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  'Todas las canciones de esta categoría',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.body(
                                    fontSize: 10,
                                    color: AppColors.textMuted,
                                    height: 1.2,
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
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _MusicModeOption(
                            label: 'Aleatorio',
                            icon: Icons.shuffle,
                            selected: musicPlayMode == 'shuffle',
                            onTap: () => onMusicPlayModeChanged('shuffle'),
                          ),
                        ),
                        Expanded(
                          child: _MusicModeOption(
                            label: 'Lineal',
                            icon: Icons.format_list_bulleted,
                            selected: musicPlayMode == 'linear',
                            onTap: () => onMusicPlayModeChanged('linear'),
                          ),
                        ),
                      ],
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

class _MusicModeOption extends StatelessWidget {
  const _MusicModeOption({
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
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? AppColors.accentInk : AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTextStyles.body(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.accentInk : AppColors.textSecondary,
              ),
            ),
          ],
        ),
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

/// Índice lateral A-Z (fast-scroll) del catálogo de música.
class _AzIndex extends StatefulWidget {
  const _AzIndex({required this.available, required this.onLetter});

  final Set<String> available;
  final ValueChanged<String> onLetter;

  @override
  State<_AzIndex> createState() => _AzIndexState();
}

class _AzIndexState extends State<_AzIndex> {
  String? _active;

  String _letterAt(double dy, double height) {
    var index = ((dy / height) * _CatalogTabState._azOrder.length).floor();
    if (index < 0) index = 0;
    if (index >= _CatalogTabState._azOrder.length) {
      index = _CatalogTabState._azOrder.length - 1;
    }
    return _CatalogTabState._azOrder[index];
  }

  void _updateActive(Offset local, double height) {
    final letter = _letterAt(local.dy, height);
    if (letter == _active) return;
    setState(() => _active = letter);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final letter = _letterAt(details.localPosition.dy, height);
            setState(() => _active = letter);
            widget.onLetter(letter);
          },
          onVerticalDragStart: (details) =>
              _updateActive(details.localPosition, height),
          onVerticalDragUpdate: (details) =>
              _updateActive(details.localPosition, height),
          onVerticalDragEnd: (_) {
            final letter = _active;
            setState(() => _active = null);
            if (letter != null) widget.onLetter(letter);
          },
          onVerticalDragCancel: () => setState(() => _active = null),
          child: Container(
            width: 22,
            padding: const EdgeInsets.symmetric(vertical: 4),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final letter in _CatalogTabState._azOrder)
                  _AzLetter(
                    letter: letter,
                    available: widget.available.contains(letter),
                    active: _active == letter,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AzLetter extends StatelessWidget {
  const _AzLetter({
    required this.letter,
    required this.available,
    required this.active,
  });

  final String letter;
  final bool available;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
      decoration: BoxDecoration(
        color: active ? AppColors.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        letter,
        style: AppTextStyles.body(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          height: 1,
          color: active
              ? AppColors.accentInk
              : available
              ? AppColors.textSecondary
              : AppColors.textMuted.withValues(alpha: 0.45),
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
