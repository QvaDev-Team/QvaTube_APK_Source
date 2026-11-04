import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/app_config.dart';
import 'core/network/api_providers.dart';
import 'core/push/push_service.dart';
import 'core/router/router.dart';
import 'core/storage/app_preferences.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/update/update_providers.dart';
import 'core/widgets/splash_screen.dart';
import 'features/auth/presentation/providers/auth_controller.dart';
import 'features/catalog/application/catalog_providers.dart';
import 'core/theme/season_branding.dart';
import 'features/home/presentation/widgets/media_player_screen.dart';
import 'features/update/presentation/update_checker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();

  // Arte de temporada: la última que dijo el servidor (GET /api/season) y su
  // logo/icono guardados; sin eso, el arte incluido en el APK.
  await SeasonBranding.init(preferences);

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const QvaTubeApp(),
    ),
  );
}

class QvaTubeApp extends ConsumerStatefulWidget {
  const QvaTubeApp({super.key});

  @override
  ConsumerState<QvaTubeApp> createState() => _QvaTubeAppState();
}

class _QvaTubeAppState extends ConsumerState<QvaTubeApp>
    with WidgetsBindingObserver {
  bool _homeInitialLoadDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshSeason();
      // Restaura la sesión guardada (`GET /api/auth/me`) antes de decidir a
      // qué pantalla ir.
      ref.read(authControllerProvider.notifier).restoreSession();
      _showUpdateWelcome();
      _startPush();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshSeason();
  }

  /// Temporada del servidor al abrir y al volver a primer plano. El icono
  /// del launcher solo se cambia sin nada reproduciéndose (algunos launchers
  /// cierran la app al cambiar de alias).
  void _refreshSeason() {
    SeasonBranding.refresh(
      canChangeIcon: !ActiveMediaSession.instance.hasActiveMedia,
    );
  }

  /// Notificaciones push (FCM). Al tocar una se abre Notificaciones (o el
  /// Modo creador si es un aviso `creator_*`); con la app abierta se
  /// refresca la lista y se avisa con un mensaje breve.
  void _startPush() {
    PushService.start(
      client: ref.read(apiClientProvider),
      onOpen: (message) {
        ref.invalidate(notificationsProvider);
        final type = message.data['type']?.toString() ?? '';
        ref.read(routerProvider).push(
              type.startsWith('creator_') ? '/cuenta/creador' : '/cuenta/notificaciones',
            );
      },
      onForeground: (message) {
        ref.invalidate(notificationsProvider);
        final title = message.notification?.title;
        final context = rootNavigatorKey.currentContext;
        if (title == null || context == null || !context.mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(title),
            action: SnackBarAction(
              label: 'Ver',
              onPressed: () =>
                  ref.read(routerProvider).push('/cuenta/notificaciones'),
            ),
          ),
        );
      },
    );
    // Con sesión (también tras iniciarla), el backend recibe el token.
    ref.listenManual(authControllerProvider, (previous, next) {
      if (next.isAuthenticated && previous?.isAuthenticated != true) {
        PushService.registerWithBackend();
      }
    });
  }

  Future<void> _showUpdateWelcome() async {
    final version = await ref.read(appUpdateServiceProvider).installedVersion();
    if (version.versionCode <= 0) return;

    final prefs = ref.read(sharedPreferencesProvider);
    final previous = prefs.getInt(AppConfig.lastVersionCodeKey);
    final hasOpenedBefore = prefs.getBool(AppConfig.introSeenKey) ?? false;
    final justUpdated = previous == null
        ? hasOpenedBefore
        : version.versionCode > previous;

    await prefs.setInt(AppConfig.lastVersionCodeKey, version.versionCode);
    if (!justUpdated) return;

    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await showAppVersionDialog(
      context,
      installedVersion: version,
      justUpdated: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final authState = ref.watch(authControllerProvider);

    // Si el usuario tiene sesión directa, precargamos los datos iniciales de
    // Inicio y mantenemos la splash hasta que la vista esté lista.
    var keepSplash = authState.status == AuthStatus.unknown;
    if (!keepSplash && authState.canBrowse && !_homeInitialLoadDone) {
      final recs = ref.watch(recommendationsProvider);
      final genres = ref.watch(homeGenresProvider);
      if (recs.isLoading && genres.isLoading) {
        keepSplash = true;
      } else {
        _homeInitialLoadDone = true;
      }
    }

    return MaterialApp.router(
      title: 'QvaTube',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      builder: (context, child) {
        // Evita que el tamaño de fuente del sistema rompa el diseño.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.2,
            ),
          ),
          child: ColoredBox(
            color: AppColors.background,
            child: Stack(
              fit: StackFit.expand,
              children: [
                UpdateChecker(child: child ?? const SizedBox.shrink()),
                if (keepSplash) const SplashScreen(),
              ],
            ),
          ),
        );
      },
    );
  }
}
