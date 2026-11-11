import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:qvatube_apk/core/utils/icon_mapper.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/storage/app_preferences.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/app_skeleton.dart';
import '../../../catalog/application/catalog_providers.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../../../reviews/presentation/rating_widgets.dart';
import '../widgets/content_detail_sheet.dart';
import '../widgets/media_card.dart';
import '../widgets/section_header.dart';

/// Máximo de tarjetas de "Mis favoritos" en Inicio (igual que la web); la
/// lista completa vive en Cuenta → Favoritos.
const int _homeFavoritesMax = 20;

/// Pestaña de Inicio (spec §6.5) conectada a la API de QvaTube.
class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  /// "×" de una tarjeta de "Seguir donde quedaste": borra el progreso
  /// guardado de ese ítem (`DELETE /api/progress`).
  Future<void> _removeContinueItem(
    BuildContext context,
    WidgetRef ref,
    CatalogItem item,
  ) async {
    final chatId = item.chatId;
    final msgId = item.msgId;
    if (chatId == null || msgId == null) return;
    try {
      await ref
          .read(catalogApiProvider)
          .removeProgress(chatId: chatId, msgId: msgId);
      ref.invalidate(continueWatchingProvider);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo quitar. Intenta de nuevo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final showContinue =
        prefs.getBool(AppConfig.showContinueWatchingKey) ?? true;
    final showNewBadges = prefs.getBool(AppConfig.showNewBadgesKey) ?? true;

    final continueWatching = ref.watch(continueWatchingProvider);
    final favorites = ref.watch(favoritesProvider);
    final recommendations = ref.watch(recommendationsProvider);
    final genreRows = ref.watch(homeGenresProvider);

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: () async {
        ref.invalidate(continueWatchingProvider);
        ref.invalidate(favoritesProvider);
        ref.invalidate(recommendationsProvider);
        ref.invalidate(homeGenresProvider);
        ref.invalidate(siteStatsProvider);
        ref.invalidate(reviewsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const _Hero(),
          const SizedBox(height: 26),
          if (!showContinue)
            const SizedBox.shrink()
          else
            continueWatching.when(
              loading: () => const SizedBox.shrink(),
              error: (error, stack) => const SizedBox.shrink(),
              data: (items) {
                if (items.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(
                      title: 'Seguir donde quedaste',
                      accent: '#FF3D1A',
                      icon: Icon(LucideIcons.play),
                    ),
                    MediaCarousel(
                      items: items,
                      showNewBadge: showNewBadges,
                      onTap: (item) => showContentDetailSheet(context, item),
                      onRemove: (item) =>
                          _removeContinueItem(context, ref, item),
                    ),
                    const SizedBox(height: 26),
                  ],
                );
              },
            ),
          // "Mis favoritos": entre "Seguir donde quedaste" y "Recomendaciones".
          // Sin sesión (401), sin favoritos o sin red, la fila no aparece.
          favorites.when(
            loading: () => const SizedBox.shrink(),
            error: (error, stack) => const SizedBox.shrink(),
            data: (items) {
              if (items.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // El corazón ya lo usan Novelas y la fila de Romance.
                  const SectionTitle(
                    title: 'Mis favoritos',
                    accent: '#FF4D6D',
                    icon: Icon(LucideIcons.bookmark),
                  ),
                  MediaCarousel(
                    items: items.take(_homeFavoritesMax).toList(),
                    showNewBadge: showNewBadges,
                    onTap: (item) => showContentDetailSheet(context, item),
                  ),
                  const SizedBox(height: 26),
                ],
              );
            },
          ),
          recommendations.when(
            loading: () => const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(title: 'Recomendaciones'),
                SkeletonMediaCarousel(itemCount: 4),
                SizedBox(height: 26),
              ],
            ),
            error: (error, stack) => const SizedBox.shrink(),
            data: (data) {
              if (data.items.isEmpty) return const SizedBox.shrink();
              final seasonLabel = data.seasonLabel;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(
                    title: seasonLabel != null
                        ? 'Recomendaciones:'
                        : 'Recomendaciones',
                    highlight: seasonLabel != null
                        ? ' Especial $seasonLabel'
                        : null,
                    accent: '#FF8A1F',
                    icon: Icon(
                      getIconFromName(
                        'star',
                      ), // Convierte "spark" a Icons.auto_awesome
                    ),
                  ),
                  MediaCarousel(
                    items: data.items,
                    showNewBadge: showNewBadges,
                    onTap: (item) => showContentDetailSheet(context, item),
                  ),
                  const SizedBox(height: 26),
                ],
              );
            },
          ),
          genreRows.when(
            loading: () => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 2; i++) ...[
                  const SectionTitle(title: 'Cargando contenido...'),
                  const SkeletonMediaCarousel(itemCount: 4),
                  const SizedBox(height: 26),
                ],
              ],
            ),
            error: (error, stack) => const SizedBox.shrink(),
            data: (rows) {
              if (rows.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final row in rows) ...[
                    SectionTitle(
                      title: row.label ?? 'Contenido',
                      accent: row.accent,
                      icon: Icon(
                        getIconFromName(
                          row.icon,
                        ), // Convierte "spark" a Icons.auto_awesome
                      ),
                    ),
                    MediaCarousel(
                      items: row.items,
                      showNewBadge: showNewBadges,
                      onTap: (item) => showContentDetailSheet(context, item),
                    ),
                    const SizedBox(height: 26),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Cabecera de Inicio: lema, resumen con la categoría rotando, valoración
/// media real (`GET /api/reviews`), "Planes y Precios" y "Valorar la APK"
/// (abre la pantalla de valoraciones).
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'TODO EL ENTRETENIMIENTO, EN UN SOLO LUGAR.',
          textAlign: TextAlign.center,
          style: AppTextStyles.display(fontSize: 20, letterSpacing: 0.4),
        ),
        const SizedBox(height: 8),
        const _RotatingTagline(),
        const SizedBox(height: 16),
        const RatingSummary(),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: _ActionButton(
            label: 'Planes y Precios',
            icon: LucideIcons.crown,
            color: AppColors.accent,
            foreground: AppColors.accentInk,
            onTap: () => context.push('/cuenta/plan'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: _ActionButton(
            label: 'Valorar la APK',
            icon: LucideIcons.star,
            color: ratingGold,
            foreground: const Color(0xFF1A1300),
            onTap: () => context.push('/cuenta/valoraciones'),
          ),
        ),
      ],
    );
  }
}

/// "Disfruta de [CATEGORÍA] y mucho más…", con la categoría rotando en el
/// color de acento y un pequeño glow.
class _RotatingTagline extends StatefulWidget {
  const _RotatingTagline();

  @override
  State<_RotatingTagline> createState() => _RotatingTaglineState();
}

class _RotatingTaglineState extends State<_RotatingTagline> {
  static const _categories = [
    'Música',
    'Series',
    'Anime',
    'Libros',
    'Películas',
    'Televisión',
  ];

  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      setState(() => _index = (_index + 1) % _categories.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppTextStyles.body(
      fontSize: 13.5,
      color: AppColors.textSecondary,
      height: 1.5,
    );
    final highlight = base.copyWith(
      color: AppColors.accent,
      fontWeight: FontWeight.w800,
      shadows: [
        Shadow(color: AppColors.accent.withValues(alpha: 0.75), blurRadius: 12),
      ],
    );

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'Disfruta de '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            // Todas las categorías invisibles reservan el ancho de la más
            // larga, así el resto del texto no salta al cambiar de palabra.
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (final category in _categories)
                  Opacity(opacity: 0, child: Text(category, style: highlight)),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.4),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    _categories[_index],
                    key: ValueKey(_index),
                    style: highlight,
                  ),
                ),
              ],
            ),
          ),
          const TextSpan(
            text:
                ' y mucho más en línea o descárgalo para llevarlo contigo sin '
                'conexión, con contenido nuevo todos los días.',
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.md);
    // Degradado suave (más claro arriba) + filo de luz + glow del propio
    // color por fuera: así el botón no se ve plano/plástico.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(color, Colors.white, 0.16)!,
            color,
            Color.lerp(color, Colors.black, 0.14)!,
          ],
          stops: const [0, 0.55, 1],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.55),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: color.withValues(alpha: 0.28),
            blurRadius: 36,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// class _CommunityBanner extends ConsumerWidget {
//   const _CommunityBanner();

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: AppColors.surface,
//         borderRadius: BorderRadius.circular(AppRadii.lg),
//         border: Border.all(color: const Color(0x55FF3D1A)),
//         boxShadow: [
//           BoxShadow(
//             color: AppColors.accent.withValues(alpha: 0.18),
//             blurRadius: 24,
//             spreadRadius: 1,
//           ),
//         ],
//       ),
//       child: Row(
//         children: [
//           Container(
//             width: 46,
//             height: 46,
//             alignment: Alignment.center,
//             decoration: const BoxDecoration(
//               shape: BoxShape.circle,
//               color: AppColors.accentSoft,
//             ),
//             child: const Icon(
//               Icons.rocket_launch_outlined,
//               color: AppColors.accent,
//               size: 22,
//             ),
//           ),
//           const SizedBox(width: 14),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   'Instala la APK de QvaTube',
//                   style: AppTextStyles.body(
//                     fontSize: 14,
//                     fontWeight: FontWeight.w700,
//                   ),
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   'La versión Android más ligera para tu teléfono.',
//                   style: AppTextStyles.body(
//                     fontSize: 12,
//                     color: AppColors.textSecondary,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           InkWell(
//             onTap: () async {
//               final config = await ref.read(siteConfigProvider.future);
//               final url = config.whatsappUrl;
//               if (url != null && url.isNotEmpty) {
//                 await DeviceChannel.openUrl(url);
//               }
//             },
//             borderRadius: BorderRadius.circular(AppRadii.pill),
//             child: Container(
//               padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
//               decoration: BoxDecoration(
//                 color: AppColors.accent,
//                 borderRadius: BorderRadius.circular(AppRadii.pill),
//               ),
//               child: Text(
//                 'Unirme',
//                 style: AppTextStyles.body(
//                   fontSize: 12.5,
//                   fontWeight: FontWeight.w800,
//                   color: AppColors.accentInk,
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _HowItWorks extends StatelessWidget {
//   const _HowItWorks();

//   static const List<String> _steps = [
//     'Elige tu contenido',
//     'Reproduce o descarga directo a tu móvil',
//     'Ahorra megas',
//   ];

//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       children: [
//         for (var index = 0; index < _steps.length; index++)
//           Padding(
//             padding: const EdgeInsets.only(bottom: 12),
//             child: Row(
//               children: [
//                 Container(
//                   width: 30,
//                   height: 30,
//                   alignment: Alignment.center,
//                   decoration: const BoxDecoration(
//                     shape: BoxShape.circle,
//                     color: AppColors.accent,
//                   ),
//                   child: Text(
//                     '${index + 1}',
//                     style: AppTextStyles.body(
//                       fontSize: 13,
//                       fontWeight: FontWeight.w800,
//                       color: AppColors.accentInk,
//                     ),
//                   ),
//                 ),
//                 const SizedBox(width: 12),
//                 Expanded(
//                   child: Text(
//                     _steps[index],
//                     style: AppTextStyles.body(fontSize: 13),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//       ],
//     );
//   }
// }

// class _StatsGrid extends ConsumerWidget {
//   const _StatsGrid();

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final stats = ref.watch(siteStatsProvider);
//     final reviews = ref.watch(reviewsProvider);

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         reviews.when(
//           loading: () => const SizedBox(height: 40),
//           error: (error, stack) => const SizedBox.shrink(),
//           data: (data) => Row(
//             children: [
//               Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     data.average.toStringAsFixed(1),
//                     style: Theme.of(context).textTheme.displayLarge,
//                   ),
//                   Row(
//                     children: List.generate(
//                       5,
//                       (index) => Icon(
//                         index < data.average.round()
//                             ? Icons.star
//                             : Icons.star_border,
//                         size: 14,
//                         color: AppColors.accent,
//                       ),
//                     ),
//                   ),
//                   Text(
//                     '${data.total} reseñas',
//                     style: AppTextStyles.body(
//                       fontSize: 11,
//                       color: AppColors.textMuted,
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(width: 18),
//               Expanded(
//                 child: Text(
//                   'Lo que dice la comunidad sobre QvaTube.',
//                   style: AppTextStyles.body(
//                     fontSize: 12,
//                     color: AppColors.textSecondary,
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         ),
//         const SizedBox(height: 16),
//         stats.when(
//           loading: () => const SizedBox.shrink(),
//           error: (error, stack) => const SizedBox.shrink(),
//           data: (data) {
//             final entries = <({String label, String value})>[
//               (label: 'Películas indexadas', value: '${data.moviesCount ?? 0}'),
//               (label: 'Series', value: '${data.seriesCount ?? 0}'),
//               (label: 'Música', value: '${data.musicCount ?? 0}'),
//               (label: 'Usuarios activos', value: '${data.onlineNow ?? 0}'),
//             ];
//             return GridView.count(
//               crossAxisCount: 2,
//               shrinkWrap: true,
//               physics: const NeverScrollableScrollPhysics(),
//               mainAxisSpacing: 10,
//               crossAxisSpacing: 10,
//               childAspectRatio: 2.2,
//               children: [
//                 for (final entry in entries)
//                   Container(
//                     padding: const EdgeInsets.all(12),
//                     decoration: BoxDecoration(
//                       color: AppColors.surface,
//                       borderRadius: BorderRadius.circular(AppRadii.md),
//                       border: Border.all(color: AppColors.border),
//                     ),
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       mainAxisAlignment: MainAxisAlignment.center,
//                       children: [
//                         Text(
//                           entry.value,
//                           style: AppTextStyles.display(fontSize: 22),
//                         ),
//                         const SizedBox(height: 2),
//                         Text(
//                           entry.label,
//                           maxLines: 2,
//                           overflow: TextOverflow.ellipsis,
//                           style: AppTextStyles.body(
//                             fontSize: 11,
//                             color: AppColors.textMuted,
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//               ],
//             );
//           },
//         ),
//       ],
//     );
//   }
// }
