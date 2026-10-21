import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import 'widgets/qvatube_bottom_nav.dart';
import 'widgets/qvatube_top_bar.dart';

/// Contenedor principal de la app tras el login.
///
/// - Barra superior fija con logo, buscador y avatar de usuario.
/// - Barra de navegación inferior con 5 secciones y "Inicio" en el centro.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<QvaBottomNavItem> _items = [
    QvaBottomNavItem(label: 'Popular', icon: Icons.local_fire_department),
    QvaBottomNavItem(label: 'TV', icon: Icons.live_tv),
    QvaBottomNavItem(
      label: 'Inicio',
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
    ),
    QvaBottomNavItem(label: 'Películas', icon: Icons.movie_outlined),
    QvaBottomNavItem(label: 'Series', icon: Icons.tv),
  ];

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const QvaTopBar(),
          Expanded(child: navigationShell),
        ],
      ),
      bottomNavigationBar: QvaBottomNav(
        items: _items,
        currentIndex: navigationShell.currentIndex,
        onTap: _onTap,
      ),
    );
  }
}
