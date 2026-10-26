import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qvatube_apk/core/utils/icon_mapper.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/storage/app_preferences.dart';
import '../../../../core/platform/device_channel.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/widgets/app_skeleton.dart';
import '../../../catalog/application/catalog_providers.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../widgets/content_detail_sheet.dart';
import '../widgets/media_card.dart';
import '../widgets/section_header.dart';
import '../widgets/suggest_content_sheet.dart';

/// Pestaña de Inicio (spec §6.5) conectada a la API de QvaTube.
class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(sharedPreferencesProvider);
    final showContinue =
        prefs.getBool(AppConfig.showContinueWatchingKey) ?? true;
    final showNewBadges = prefs.getBool(AppConfig.showNewBadgesKey) ?? true;

    final continueWatching = ref.watch(continueWatchingProvider);
    final recommendations = ref.watch(recommendationsProvider);
    final genreRows = ref.watch(homeGenresProvider);

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: () async {
        ref.invalidate(continueWatchingProvider);
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
                    const SectionTitle(title: 'Seguir donde quedaste'),
                    MediaCarousel(items: items, showNewBadge: showNewBadges),
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
          const _CommunityBanner(),
          const SizedBox(height: 26),
          const SectionTitle(title: 'Cómo funciona'),
          const _HowItWorks(),
          const SizedBox(height: 26),
          const SectionTitle(title: 'Reseñas y estadísticas'),
          const _StatsGrid(),
        ],
      ),
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const AppLogo(height: 64),
        const SizedBox(height: 10),
        Text(
          'Streaming cubano — películas, series, novelas, anime, música y libros.',
          textAlign: TextAlign.center,
          style: AppTextStyles.display(
            fontSize: 17,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: 'Sugerir contenido',
                icon: Icons.auto_awesome,
                color: AppColors.accent,
                foreground: AppColors.accentInk,
                onTap: () => showSuggestContentSheet(context, ref),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                label: 'Súbelo tú mismo',
                icon: Icons.send,
                color: AppColors.telegram,
                foreground: Colors.white,
                onTap: () => _openTelegram(context, ref),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: 'Comunidad',
                icon: Icons.chat_bubble_outline,
                color: AppColors.whatsapp,
                foreground: Colors.white,
                onTap: () => _openCommunity(context, ref),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                label: 'Descargar APK',
                icon: Icons.download,
                color: AppColors.textPrimary,
                foreground: Colors.black,
                onTap: () => _downloadApk(context, ref),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openTelegram(BuildContext context, WidgetRef ref) async {
    final config = await ref.read(siteConfigProvider.future);
    final bot = config.botUsername ?? 'qvatube_bot';
    await DeviceChannel.openUrl('https://t.me/$bot');
  }

  Future<void> _openCommunity(BuildContext context, WidgetRef ref) async {
    final config = await ref.read(siteConfigProvider.future);
    final url = config.whatsappUrl;
    if (url == null || url.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay un enlace de comunidad configurado.'),
        ),
      );
      return;
    }
    await DeviceChannel.openUrl(url);
  }

  Future<void> _downloadApk(BuildContext context, WidgetRef ref) async {
    final info = await ref.read(catalogApiProvider).apkInfo();
    final size = info['size_mb'];
    final base = AppConfig.apiBaseUrl.endsWith('/')
        ? AppConfig.apiBaseUrl.substring(0, AppConfig.apiBaseUrl.length - 1)
        : AppConfig.apiBaseUrl;
    await DeviceChannel.openUrl('$base/download/qvatube.apk');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          size != null
              ? 'Descargando la APK ($size MB)…'
              : 'Descargando la APK…',
        ),
      ),
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
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            boxShadow: color == AppColors.accent ? AppColors.playGlow : null,
          ),
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
    );
  }
}

class _CommunityBanner extends ConsumerWidget {
  const _CommunityBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: const Color(0x55FF3D1A)),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.18),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentSoft,
            ),
            child: const Icon(
              Icons.rocket_launch_outlined,
              color: AppColors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Instala la APK de QvaTube',
                  style: AppTextStyles.body(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'La versión Android más ligera para tu teléfono.',
                  style: AppTextStyles.body(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () async {
              final config = await ref.read(siteConfigProvider.future);
              final url = config.whatsappUrl;
              if (url != null && url.isNotEmpty) {
                await DeviceChannel.openUrl(url);
              }
            },
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Text(
                'Unirme',
                style: AppTextStyles.body(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentInk,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const List<String> _steps = [
    'Elige tu contenido',
    'Reproduce o descarga directo a tu móvil',
    'Ahorra megas',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < _steps.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: AppTextStyles.body(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accentInk,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _steps[index],
                    style: AppTextStyles.body(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatsGrid extends ConsumerWidget {
  const _StatsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(siteStatsProvider);
    final reviews = ref.watch(reviewsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        reviews.when(
          loading: () => const SizedBox(height: 40),
          error: (error, stack) => const SizedBox.shrink(),
          data: (data) => Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.average.toStringAsFixed(1),
                    style: Theme.of(context).textTheme.displayLarge,
                  ),
                  Row(
                    children: List.generate(
                      5,
                      (index) => Icon(
                        index < data.average.round()
                            ? Icons.star
                            : Icons.star_border,
                        size: 14,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  Text(
                    '${data.total} reseñas',
                    style: AppTextStyles.body(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  'Lo que dice la comunidad sobre QvaTube.',
                  style: AppTextStyles.body(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        stats.when(
          loading: () => const SizedBox.shrink(),
          error: (error, stack) => const SizedBox.shrink(),
          data: (data) {
            final entries = <({String label, String value})>[
              (label: 'Películas indexadas', value: '${data.moviesCount ?? 0}'),
              (label: 'Series', value: '${data.seriesCount ?? 0}'),
              (label: 'Música', value: '${data.musicCount ?? 0}'),
              (label: 'Usuarios activos', value: '${data.onlineNow ?? 0}'),
            ];
            return GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.2,
              children: [
                for (final entry in entries)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          entry.value,
                          style: AppTextStyles.display(fontSize: 22),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
