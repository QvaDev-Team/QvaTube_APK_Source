import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../catalog/application/catalog_providers.dart';
import 'widgets/qvatube_bottom_nav.dart';
import 'widgets/qvatube_top_bar.dart';

/// Contenedor principal de la app tras el login.
///
/// - Barra superior fija con logo, buscador y avatar de usuario.
/// - Barra de navegación inferior con 5 secciones y "Inicio" en el centro.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// 9 secciones: 4 a la izquierda, **Inicio en el medio** y 4 a la derecha.
  static const List<({String label, IconData icon, IconData? activeIcon})>
      _definitions = [
    (label: 'Popular', icon: Icons.local_fire_department, activeIcon: null),
    (label: 'TV', icon: Icons.live_tv, activeIcon: null),
    (label: 'Películas', icon: Icons.movie_outlined, activeIcon: null),
    (label: 'Series', icon: Icons.tv, activeIcon: null),
    (
      label: 'Inicio',
      icon: Icons.home_outlined,
      activeIcon: Icons.home
    ),
    (label: 'Anime', icon: Icons.auto_awesome, activeIcon: null),
    (label: 'Novelas', icon: Icons.favorite_border, activeIcon: null),
    (label: 'Música', icon: Icons.music_note, activeIcon: null),
    (label: 'Libros', icon: Icons.menu_book, activeIcon: null),
  ];

  /// Índice de la pestaña de Inicio (siempre en el medio).
  static const int homeIndex = 4;

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
    // Los badges de estrenos van en Inicio (total), Películas, Series y
    // Anime, que son las categorías con contador en el backend.
    final badges = <int>[
      0,
      0,
      counts['movie'] ?? 0,
      counts['series'] ?? 0,
      totalNew,
      counts['anime'] ?? 0,
      0,
      0,
      0,
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const QvaTopBar(),
          Expanded(child: navigationShell),
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
