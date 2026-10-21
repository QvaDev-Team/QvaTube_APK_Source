import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'core/storage/app_preferences.dart';
import 'features/auth/application/auth_controller.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
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
    // Restaura la sesión guardada (`GET /api/auth/me`) antes de decidir a
    // qué pantalla ir.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).restoreSession();
    });
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
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
