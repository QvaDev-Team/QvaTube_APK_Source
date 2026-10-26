import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../core/theme/app_assets.dart';
import '../../update/presentation/update_checker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';

/// Preferencias locales de la app.
///
/// La API no expone un endpoint de ajustes de usuario, así que estas opciones
/// se guardan localmente en el dispositivo.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Configuración'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          // Text('Temporada', style: Theme.of(context).textTheme.displaySmall),
          // const SizedBox(height: 10),
          // _ThemeSelector(),
          const SizedBox(height: 20),
          Text('Aplicación', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 10),
          const UpdateMenuEntry(),

          const SizedBox(height: 20),
          Text('Acerca de', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QvaTube',
                  style: AppTextStyles.body(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Streaming cubano — películas, series, novelas, anime, música y '
                  'libros en un solo lugar.',
                  style: AppTextStyles.body(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Los ajustes se guardan en este dispositivo.',
                  style: AppTextStyles.body(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Selector de tema (temporada).
///
/// Los logos e iconos disponibles están declarados en `assets/theme.json`.
class _ThemeSelector extends ConsumerStatefulWidget {
  const _ThemeSelector();

  @override
  ConsumerState<_ThemeSelector> createState() => _ThemeSelectorState();
}

class _ThemeSelectorState extends ConsumerState<_ThemeSelector> {
  String _themeId = AppAssets.current.id;

  @override
  void initState() {
    super.initState();
    _themeId =
        ref.read(sharedPreferencesProvider).getString(AppConfig.themeIdKey) ??
        AppAssets.current.id;
  }

  Future<void> _apply(String id) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(AppConfig.themeIdKey, id);
    await AppAssets.setTheme(id);
    if (!mounted) return;
    setState(() => _themeId = id);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Tema "$id" aplicado.')));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppAssets.revision,
      builder: (context, _, _) {
        final themes = AppAssets.themes;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    child: Image.asset(
                      AppAssets.logo,
                      height: 34,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox(height: 34),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Logo, favicon e iconos de la app',
                      style: AppTextStyles.body(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (themes.isEmpty)
                Text(
                  'No se encontró assets/theme.json.',
                  style: AppTextStyles.body(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final theme in themes)
                      ChoiceChip(
                        label: Text(theme.label),
                        selected: theme.id == _themeId,
                        onSelected: (_) => _apply(theme.id),
                        selectedColor: AppColors.accentSoft,
                        backgroundColor: AppColors.surfaceSecondary,
                        labelStyle: AppTextStyles.body(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.id == _themeId
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                        side: BorderSide(
                          color: theme.id == _themeId
                              ? AppColors.accent
                              : AppColors.border,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              Text(
                'El manifiesto está en assets/theme.json (campo "active").',
                style: AppTextStyles.body(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
