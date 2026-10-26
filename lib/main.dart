import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/router/router.dart';
import 'core/config/app_config.dart';
import 'core/storage/app_preferences.dart';
import 'core/theme/app_assets.dart';
import 'core/update/update_providers.dart';
import 'features/auth/presentation/providers/auth_controller.dart';
import 'features/update/presentation/update_checker.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();

  // Assets de la temporada (assets/theme.json). Se respeta el tema elegido
  // en Configuración; si no hay ninguno, se usa el "active" del manifiesto.
  await AppAssets.init(themeId: preferences.getString(AppConfig.themeIdKey));

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

class _QvaTubeAppState extends ConsumerState<QvaTubeApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Restaura la sesión guardada (`GET /api/auth/me`) antes de decidir a
      // qué pantalla ir.
      ref.read(authControllerProvider.notifier).restoreSession();
      _showUpdateWelcome();
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
            // Aviso de versión nueva al abrir la app.
            child: UpdateChecker(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
    );
  }
}
