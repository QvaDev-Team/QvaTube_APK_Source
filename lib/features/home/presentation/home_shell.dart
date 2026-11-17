import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../catalog/application/catalog_providers.dart';
import 'widgets/media_player_screen.dart';
import 'widgets/qvatube_bottom_nav.dart';
import 'widgets/qvatube_side_nav.dart';
import 'widgets/qvatube_top_bar.dart';

/// Contenedor principal de la app tras el login.
///
/// - Barra superior fija con logo, buscador y avatar de usuario.
/// - Barra de navegación inferior con 9 secciones e "Inicio" a la izquierda;
///   en pantallas anchas (escritorio) pasa a ser un menú lateral.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// 9 secciones: **Inicio a la izquierda** y el resto a su derecha.
  static const List<({String label, IconData icon, IconData? activeIcon})>
      _definitions = [
    (
      label: 'Inicio',
      icon: Icons.home_outlined,
      activeIcon: Icons.home
    ),
    (label: 'Popular', icon: Icons.local_fire_department, activeIcon: null),
    (label: 'TV', icon: Icons.live_tv, activeIcon: null),
    (label: 'Películas', icon: Icons.movie_outlined, activeIcon: null),
    (label: 'Series', icon: Icons.tv, activeIcon: null),
    (label: 'Anime', icon: Icons.auto_awesome, activeIcon: null),
    (label: 'Novelas', icon: Icons.favorite_border, activeIcon: null),
    (label: 'Música', icon: Icons.music_note, activeIcon: null),
    (label: 'Libros', icon: Icons.menu_book, activeIcon: null),
  ];

  /// Índice de la pestaña de Inicio (primera a la izquierda).
  static const int homeIndex = 0;

  /// Claves de `GET /api/new-content/counts` de cada pestaña (mismo orden
  /// que [_definitions]). Se aceptan alias por si el backend usa el nombre
  /// en plural o en español.
  static const List<List<String>> _countKeys = [
    [],
    ['popular'],
    ['tv', 'live', 'channels'],
    ['movie', 'movies', 'peliculas'],
    ['series'],
    ['anime'],
    ['novela', 'novelas'],
    ['music', 'musica', 'música'],
    ['book', 'books', 'libros'],
  ];

  static int _countFor(Map<String, int> counts, List<String> keys) {
    for (final key in keys) {
      final value = counts[key];
      if (value != null && value > 0) return value;
    }
    return 0;
  }

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Estrenos nuevos por categoría (`GET /api/new-content/counts`).
    final counts =
        ref.watch(newContentCountsProvider).value ?? const <String, int>{};
    final totalNew = counts.values.fold<int>(0, (sum, value) => sum + value);
    // Cada pestaña muestra los estrenos de su categoría, igual que la web.
    // Antes solo Películas, Series y Anime tenían contador, así que una
    // subida grande de música (p. ej. 81 canciones) salía en el total de
    // Inicio pero no en la pestaña Música.
    final badges = <int>[
      for (var index = 0; index < _definitions.length; index++)
        index == homeIndex ? totalNew : _countFor(counts, _countKeys[index]),
    ];

    final items = <QvaBottomNavItem>[
      for (var index = 0; index < _definitions.length; index++)
        QvaBottomNavItem(
          label: _definitions[index].label,
          icon: _definitions[index].icon,
          activeIcon: _definitions[index].activeIcon,
          badgeCount: badges[index],
        ),
    ];

    final width = MediaQuery.sizeOf(context).width;
    if (width >= kWideLayoutMinWidth) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            const QvaTopBar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  QvaSideNav(
                    items: items,
                    currentIndex: navigationShell.currentIndex,
                    onTap: _onTap,
                    compact: width < 1180,
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: kMaxContentWidth,
                        ),
                        child: navigationShell,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const MiniMediaPlayerBar(),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const QvaTopBar(),
          Expanded(child: navigationShell),
          const MiniMediaPlayerBar(),
        ],
      ),
      bottomNavigationBar: QvaBottomNav(
        items: items,
        currentIndex: navigationShell.currentIndex,
        onTap: _onTap,
      ),
    );
  }
}
