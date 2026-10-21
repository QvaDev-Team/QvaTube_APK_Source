import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/storage/app_preferences.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/telegram_verification_screen.dart';
import '../features/home/presentation/home_shell.dart';
import '../features/home/presentation/pending_screen.dart';
import '../features/home/presentation/tabs/catalog_tab.dart';
import '../features/home/presentation/tabs/home_tab.dart';
import '../features/onboarding/presentation/intro_screen.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

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

  // Pestañas (la de Inicio va en el medio de la barra inferior).
  static const String popular = '/popular';
  static const String television = '/television';
  static const String home = '/inicio';
  static const String movies = '/peliculas';
  static const String series = '/series';

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
    navigatorKey: _rootKey,
    initialLocation: Routes.root,
    refreshListenable: notifier,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final authState = ref.read(authControllerProvider);
      final introSeen = ref.read(introSeenProvider);
      final canBrowse = authState.canBrowse;

      if (location == Routes.root) {
        if (!introSeen) return Routes.intro;
        return canBrowse ? Routes.home : Routes.login;
      }

      final isProtected = location == Routes.home ||
          location == Routes.popular ||
          location == Routes.television ||
          location == Routes.movies ||
          location == Routes.series ||
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
          description: 'El buscador se alimentará del catálogo de QvaTube '
              'cuando se definan los endpoints de búsqueda.',
          icon: Icons.search,
        ),
      ),
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: _rootKey,
        builder: (context, state, navigationShell) {
          return HomeShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'popular'),
            routes: [
              GoRoute(
                path: Routes.popular,
                builder: (context, state) => const CatalogTab(
                  title: 'Popular',
                  icon: Icons.local_fire_department,
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
                builder: (context, state) => const CatalogTab(
                  title: 'Televisión',
                  icon: Icons.live_tv,
                  aspectRatio: 1,
                  description: 'Canales en vivo de Cuba e internacional.',
                ),
              ),
            ],
          ),
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
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'peliculas'),
            routes: [
              GoRoute(
                path: Routes.movies,
                builder: (context, state) => const CatalogTab(
                  title: 'Películas',
                  icon: Icons.movie_outlined,
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
                  description: 'Series por temporada, con episodios nuevos '
                      'cada semana.',
                ),
              ),
            ],
          ),
        ],
      ),
      for (final path in Routes.account)
        GoRoute(
          path: path,
          builder: (context, state) => PendingScreen(
            title: _accountTitle(path),
            description: 'Esta sección se completará con su endpoint '
                'correspondiente cuando se defina la información de la cuenta.',
          ),
        ),
    ],
  );
});

String _accountTitle(String path) {
  return switch (path) {
    '/cuenta/perfil' => 'Mi perfil',
    '/cuenta/nombre' => 'Nombre visible',
    '/cuenta/avatar' => 'Foto de perfil',
    '/cuenta/plan' => 'Plan y suscripción',
    '/cuenta/descargas' => 'Mis descargas',
    '/cuenta/favoritos' => 'Favoritos',
    '/cuenta/notificaciones' => 'Notificaciones',
    '/cuenta/configuracion' => 'Configuración',
    '/cuenta/comunidad' => 'Comunidad',
    _ => 'Cuenta',
  };
}
