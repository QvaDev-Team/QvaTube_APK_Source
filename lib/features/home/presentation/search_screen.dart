import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/icon_mapper.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/catalog_models.dart';
import 'tabs/tv_tab.dart';
import 'widgets/content_detail_sheet.dart';
import 'widgets/media_card.dart';
import 'widgets/suggest_content_sheet.dart';

/// Pantalla de búsqueda global (`GET /api/search`).
///
/// Busca en todas las categorías del catálogo (películas, series, anime,
/// novelas, música, libros…) y en los canales de TV/Radio en vivo.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  String _query = '';
  String _selectedFilter = 'all';
  bool _loading = false;
  String? _error;
  SearchResponse? _response;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() => _query = value);

    final trimmed = value.trim();
    if (trimmed.length < 2) {
      setState(() {
        _loading = false;
        _error = null;
        _response = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    _debounce = Timer(const Duration(milliseconds: 350), () {
      _performSearch(trimmed);
    });
  }

  Future<void> _performSearch(String query) async {
    try {
      final result = await ref.read(catalogApiProvider).search(
            query: query,
            perCategory: 15,
            includeTv: true,
          );
      if (!mounted || _query.trim() != query) return;
      setState(() {
        _response = result;
        _loading = false;
        _error = null;
        if (_selectedFilter != 'all' &&
            _selectedFilter != 'tv' &&
            !result.categories.any((c) => c.key == _selectedFilter)) {
          _selectedFilter = 'all';
        }
      });
    } on ApiException catch (e) {
      if (!mounted || _query.trim() != query) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted || _query.trim() != query) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo completar la búsqueda.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = _query.trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (v) {
              if (v.trim().length >= 2) {
                _debounce?.cancel();
                _performSearch(v.trim());
              }
            },
            style: AppTextStyles.body(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Buscar películas, series, anime, TV…',
              prefixIcon: const Icon(
                Icons.search,
                size: 20,
                color: AppColors.textMuted,
              ),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
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
                vertical: 10,
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(trimmed),
    );
  }

  Widget _buildBody(String trimmed) {
    if (trimmed.length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.search,
                  size: 30,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Búsqueda global en QvaTube',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 6),
              Text(
                'Escribe al menos 2 letras para buscar en películas, series, '
                'novelas, anime, música, libros y canales de TV o radio en vivo.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading && _response == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    if (_error != null && _response == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTextStyles.body(
                  fontSize: 13.5,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => _performSearch(trimmed),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final response = _response;
    if (response == null) return const SizedBox.shrink();

    if (response.total == 0 ||
        (response.categories.isEmpty && response.tv.isEmpty)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.search_off,
                size: 48,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 14),
              Text(
                'Sin resultados para "${response.query}"',
                textAlign: TextAlign.center,
                style: AppTextStyles.body(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '¿No encuentras lo que buscas? Puedes sugerirlo para que '
                'lo agreguemos al catálogo.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => showSuggestContentSheet(context, ref),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Sugerir contenido'),
              ),
            ],
          ),
        ),
      );
    }

    final showTv =
        response.tv.isNotEmpty &&
        (_selectedFilter == 'all' || _selectedFilter == 'tv');
    final visibleCategories = _selectedFilter == 'tv'
        ? const <SearchCategoryResult>[]
        : _selectedFilter == 'all'
        ? response.categories
        : response.categories
              .where((c) => c.key == _selectedFilter)
              .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        // Chips de filtro por categoría
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(
                label: 'Todos (${response.total})',
                selected: _selectedFilter == 'all',
                onTap: () => setState(() => _selectedFilter = 'all'),
              ),
              if (response.tv.isNotEmpty) ...[
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'TV / Radio (${response.tv.length})',
                  selected: _selectedFilter == 'tv',
                  onTap: () => setState(() => _selectedFilter = 'tv'),
                ),
              ],
              for (final cat in response.categories) ...[
                const SizedBox(width: 8),
                _FilterChip(
                  label: '${cat.name} (${cat.total})',
                  selected: _selectedFilter == cat.key,
                  onTap: () => setState(() => _selectedFilter = cat.key),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Sección de canales de TV / Radio
        if (showTv) ...[
          _SectionRowHeader(
            icon: Icons.live_tv,
            title: 'TV y Radio en vivo',
            count: response.tv.length,
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
            ),
            itemCount: response.tv.length,
            itemBuilder: (context, index) {
              final channel = response.tv[index];
              return TvChannelCard(
                channel: channel,
                onTap: () => showTvPlayerSheet(context, ref, channel),
              );
            },
          ),
          const SizedBox(height: 24),
        ],

        // Secciones de categorías del catálogo
        for (final cat in visibleCategories) ...[
          _SectionRowHeader(
            icon: getIconFromName(cat.icon),
            title: cat.name,
            count: cat.total,
          ),
          const SizedBox(height: 10),
          if (_selectedFilter == cat.key || visibleCategories.length == 1)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 10,
                childAspectRatio: cat.key == 'music' ? 0.68 : 0.5,
              ),
              itemCount: cat.items.length,
              itemBuilder: (context, index) {
                final item = cat.items[index];
                return MediaCard(
                  item: item,
                  onTap: () => showContentDetailSheet(context, item),
                );
              },
            )
          else
            MediaCarousel(
              items: cat.items,
              onTap: (item) => showContentDetailSheet(context, item),
            ),
          const SizedBox(height: 22),
        ],
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
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

class _SectionRowHeader extends StatelessWidget {
  const _SectionRowHeader({
    required this.icon,
    required this.title,
    required this.count,
  });

  final IconData icon;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.displaySmall,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.surfaceSecondary,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            '$count',
            style: AppTextStyles.mono(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

