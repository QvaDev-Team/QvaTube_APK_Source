import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/app_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_logo.dart';
import '../../auth/application/auth_controller.dart';

/// Pantalla de introducción: se muestra una sola vez, antes del login.
///
/// Contenido (spec §1): resumen de la app + imagen del logo de QvaTube
/// y opción de cerrar.
class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen> {
  bool _closing = false;

  Future<void> _close() async {
    if (_closing) return;
    setState(() => _closing = true);
    await markIntroAsSeen(ref);
    if (!mounted) return;
    final canBrowse = ref.read(authControllerProvider).canBrowse;
    context.go(canBrowse ? '/inicio' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const _IntroBackdrop(),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: IconButton(
                      onPressed: _close,
                      tooltip: 'Cerrar',
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.surfaceSecondary,
                        foregroundColor: AppColors.textPrimary,
                        shape: const CircleBorder(
                          side: BorderSide(color: AppColors.border),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(
                          child: AppLogo(height: 96),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'QvaTube',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.displayMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Streaming cubano — películas, series, novelas, anime, '
                          'música y libros en un solo lugar, hecho para Cuba.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body(
                            fontSize: 13.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 28),
                        const _FeatureGrid(),
                        const SizedBox(height: 28),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.wifi_off,
                                size: 18,
                                color: AppColors.accent,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Diseñado para conexiones móviles cubanas: '
                                  'catálogo guardado, micro-caché y descargas '
                                  'ligeras para ahorrar megas.',
                                  style: AppTextStyles.body(
                                    fontSize: 12.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _close,
                          child: const Text('Comenzar'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Podrás explorar como invitado sin crear una cuenta.',
                        textAlign: TextAlign.center,
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
          ),
        ],
      ),
    );
  }
}

class _IntroBackdrop extends StatelessWidget {
  const _IntroBackdrop();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.6),
            radius: 1.1,
            colors: [
              Color(0x331B1714),
              AppColors.background,
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  static const List<({IconData icon, String label})> _items = [
    (icon: Icons.movie_outlined, label: 'Películas y series'),
    (icon: Icons.live_tv, label: 'Televisión en vivo'),
    (icon: Icons.music_note, label: 'Música con mini-reproductor'),
    (icon: Icons.menu_book, label: 'Libros EPUB y PDF'),
    (icon: Icons.favorite_border, label: 'Novelas y favorites'),
    (icon: Icons.bolt, label: 'Planes por Transfermóvil'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.6,
      children: [
        for (final item in _items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(item.icon, size: 18, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
