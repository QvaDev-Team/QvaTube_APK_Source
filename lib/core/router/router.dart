import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qvatube_apk/features/auth/presentation/screens/telegram_verification_screen.dart';

import '../storage/app_preferences.dart';
import '../../features/auth/presentation/providers/auth_controller.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/account/presentation/avatar_screen.dart';
import '../../features/account/presentation/community_screen.dart';
import '../../features/account/presentation/downloads_screen.dart';
import '../../features/account/presentation/edit_name_screen.dart';
import '../../features/account/presentation/favorites_screen.dart';
import '../../features/account/presentation/notifications_screen.dart';
import '../../features/account/presentation/plan_screen.dart';
import '../../features/account/presentation/profile_screen.dart';
import '../../features/account/presentation/settings_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/home/presentation/pending_screen.dart';
import '../../features/home/presentation/tabs/catalog_tab.dart';
import '../../features/home/presentation/tabs/home_tab.dart';
import '../../features/onboarding/presentation/intro_screen.dart';

/// Navigator raíz (se usa también para mostrar diálogos globales, como el
/// aviso de actualización, desde un contexto que está por encima del
/// Navigator).
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Rutas de la app.
abstract final class Routes {
  const Routes._();

  static const String root = '/';
  static const String intro = '/intro';
  static const String login = '/login';
  static const String register = '/registro';
  static const String forgotPassword = '/recuperar-clave';
  static const String resetPassword = '/restablecer-clave';
  static const String telegramVerify = '/verificar-telegram';
  static const String search = '/buscar';

  // Pestañas (la de Inicio siempre va en el medio de la barra inferior).
  static const String popular = '/popular';
  static const String television = '/television';
  static const String movies = '/peliculas';
  static const String series = '/series';
  static const String home = '/inicio';
  static const String anime = '/anime';
  static const String novelas = '/novelas';
  static const String music = '/musica';
  static const String books = '/libros';

  static const List<String> account = [
    '/cuenta/perfil',
    '/cuenta/nombre',
    '/cuenta/avatar',
    '/cuenta/plan',
    '/cuenta/descargas',
    '/cuenta/favoritos',
    '/cuenta/notificaciones',
    '/cuenta/configuracion',
    '/cuenta/comunidad',
  ];
}

/// Router de la aplicación.
final routerProvider = Provider<GoRouter>((ref) {
  // Solo se reconstruye el router cuando cambia la sesión o la intro; el
  // estado de autenticación se lee en cada redirección para no perder el
  // estado de navegación.
  final notifier = ref.watch(authSessionNotifierProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.root,
    refreshListenable: notifier,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final authState = ref.read(authControllerProvider);
      final introSeen = ref.read(introSeenProvider);
      final canBrowse = authState.canBrowse;

      // Mientras se comprueba la sesión (`GET /api/auth/me`) no se redirige:
      // se espera para no mostrar el login a un usuario que sí tiene sesión.
      if (authState.status == AuthStatus.unknown) {
        return null;
      }

      if (location == Routes.root) {
        if (!introSeen) return Routes.intro;
        return canBrowse ? Routes.home : Routes.login;
      }

      final isProtected =
          location == Routes.home ||
          location == Routes.popular ||
          location == Routes.television ||
          location == Routes.movies ||
          location == Routes.series ||
          location == Routes.anime ||
          location == Routes.novelas ||
          location == Routes.music ||
          location == Routes.books ||
          location.startsWith('/cuenta/');

      if (isProtected && !canBrowse) {
        return Routes.login;
      }

      if (location == Routes.login && canBrowse) {
        return Routes.home;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: Routes.root,
        builder: (context, state) => const SizedBox.shrink(),
      ),
      GoRoute(
        path: Routes.intro,
        builder: (context, state) => const IntroScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: Routes.resetPassword,
        builder: (context, state) =>
            ResetPasswordScreen(token: state.extra as String?),
      ),
      GoRoute(
        path: Routes.telegramVerify,
        builder: (context, state) => const TelegramVerificationScreen(),
      ),
      GoRoute(
        path: Routes.search,
        builder: (context, state) => const PendingScreen(
          title: 'Buscar',
          description:
              'El buscador se alimentará del catálogo de QvaTube '
              'cuando se definan los endpoints de búsqueda.',
          icon: Icons.search,
        ),
      ),
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state, navigationShell) {
          return HomeShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'inicio'),
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomeTab(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'popular'),
            routes: [
              GoRoute(
                path: Routes.popular,
                builder: (context, state) => const CatalogTab(
                  title: 'Popular',
                  icon: Icons.local_fire_department,
                  categoryKey: 'popular',
                  allowSort: false,
                  allowGenreFilter: false,
                  description: 'Lo más visto por la comunidad de QvaTube.',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'television'),
            routes: [
              GoRoute(
                path: Routes.television,
                builder: (context, state) => const PendingScreen(
                  title: 'Televisión',
                  description:
                      'La lista de canales en vivo no está expuesta '
                      'por la API (la web la tiene embebida). Se conectará '
                      'cuando el backend exponga GET /api/tv/channels.',
                  icon: Icons.live_tv,
                  showBackButton: false,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'peliculas'),
            routes: [
              GoRoute(
                path: Routes.movies,
                builder: (context, state) => const CatalogTab(
                  title: 'Películas',
                  icon: Icons.movie_outlined,
                  categoryKey: 'movie',
                  description: 'Cine cubano e internacional, siempre en 2:3.',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'series'),
            routes: [
              GoRoute(
                path: Routes.series,
                builder: (context, state) => const CatalogTab(
                  title: 'Series',
                  icon: Icons.tv,
                  categoryKey: 'series',
                  description:
                      'Series por temporada, con episodios nuevos '
                      'cada semana.',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'anime'),
            routes: [
              GoRoute(
                path: Routes.anime,
                builder: (context, state) => const CatalogTab(
                  title: 'Anime',
                  icon: Icons.auto_awesome,
                  categoryKey: 'anime',
                  description:
                      'Series de anime por temporada, con episodios '
                      'nuevos cada semana.',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'novelas'),
            routes: [
              GoRoute(
                path: Routes.novelas,
                builder: (context, state) => const CatalogTab(
                  title: 'Novelas',
                  icon: Icons.favorite_border,
                  categoryKey: 'novela',
                  description: 'Novelas por capítulos, con la Novela Cubana.',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'musica'),
            routes: [
              GoRoute(
                path: Routes.music,
                builder: (context, state) => const CatalogTab(
                  title: 'Música',
                  icon: Icons.music_note,
                  categoryKey: 'music',
                  gridAspectRatio: 0.68,
                  description:
                      'Álbumes completos con carátula cuadrada y '
                      'reproductor.',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'libros'),
            routes: [
              GoRoute(
                path: Routes.books,
                builder: (context, state) => const CatalogTab(
                  title: 'Libros',
                  icon: Icons.menu_book,
                  categoryKey: 'book',
                  description: 'Libros en EPUB y PDF listos para leer.',
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/cuenta/perfil',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/cuenta/nombre',
        builder: (context, state) => const EditNameScreen(),
      ),
      GoRoute(
        path: '/cuenta/avatar',
        builder: (context, state) => const AvatarScreen(),
      ),
      GoRoute(
        path: '/cuenta/plan',
        builder: (context, state) => const PlanScreen(),
      ),
      GoRoute(
        path: '/cuenta/notificaciones',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/cuenta/favoritos',
        builder: (context, state) => const FavoritesScreen(),
      ),
      GoRoute(
        path: '/cuenta/configuracion',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/cuenta/comunidad',
        builder: (context, state) => const CommunityScreen(),
      ),
      GoRoute(
        path: '/cuenta/descargas',
        builder: (context, state) => const DownloadsScreen(),
      ),
    ],
  );
});
