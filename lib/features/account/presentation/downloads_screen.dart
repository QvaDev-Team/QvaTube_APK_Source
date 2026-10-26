import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/device_channel.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/catalog_models.dart';

/// Pantalla "Mis descargas" en el menú de cuenta.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planUsage = ref.watch(planUsageProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mis descargas'),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: const Color(0x33FF3D1A)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0x22FF3D1A),
                  ),
                  child: const Icon(Icons.download, color: Color(0xFFFF3D1A)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Descargas directas por Telegram',
                        style: AppTextStyles.body(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Las descargas se envían a través de nuestro bot oficial de Telegram para ahorrar megas y datos nacionales.',
                        style: AppTextStyles.body(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ...planUsage.maybeWhen(
            data: (result) {
              final usage = result.usage;
              if (usage == null) return const <Widget>[];
              return <Widget>[
                const SizedBox(height: 16),
                _DownloadQuotaCard(usage: usage),
              ];
            },
            orElse: () => const <Widget>[],
          ),
          const SizedBox(height: 24),
          Text(
            'CÓMO DESCARGAR',
            style: AppTextStyles.display(
              fontSize: 14,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          const _DownloadStep(
            number: '1',
            title: 'Explora una película o serie',
            description: 'Toca cualquier tarjeta del catálogo o la pantalla de inicio para abrir su ficha.',
          ),
          const SizedBox(height: 12),
          const _DownloadStep(
            number: '2',
            title: 'Toca "Descargar" o un episodio',
            description: 'Para series y novelas puedes descargar episodios individuales o la temporada completa.',
          ),
          const SizedBox(height: 12),
          const _DownloadStep(
            number: '3',
            title: 'Se abrirá Telegram automáticamente',
            description: 'El bot te enviará el archivo listo para guardar en tu galería o reproducir offline.',
          ),
          const SizedBox(height: 28),
          Center(
            child: OutlinedButton.icon(
              onPressed: () async {
                final config = await ref.read(siteConfigProvider.future);
                final bot = config.botUsername ?? 'qvatube_bot';
                await DeviceChannel.openUrl('https://t.me/$bot');
              },
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Abrir bot de Telegram'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Consumo real de descargas del plan (`GET /api/plans/me`), igual que en la web.
class _DownloadQuotaCard extends StatelessWidget {
  const _DownloadQuotaCard({required this.usage});

  final PlanUsage usage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              const Icon(Icons.data_usage, size: 18, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Consumo de descargas',
                  style: AppTextStyles.body(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (usage.planName != null && usage.planName!.isNotEmpty)
                Text(
                  usage.planName!.toUpperCase(),
                  style: AppTextStyles.mono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _QuotaRow(
            icon: Icons.movie_outlined,
            label: 'Video',
            used: usage.downloadsUsed,
            limit: usage.downloadLimit,
            unlimited: usage.unlimited,
          ),
          const SizedBox(height: 8),
          _QuotaRow(
            icon: Icons.music_note,
            label: 'Música',
            used: usage.musicDownloadsUsed,
            limit: usage.musicDownloadLimit,
            unlimited: usage.unlimited,
          ),
          if (usage.resetInSeconds != null && usage.resetInSeconds! > 0) ...[
            const SizedBox(height: 10),
            Text(
              'Se renueva en ${_formatRemaining(usage.resetInSeconds!)}.',
              style: AppTextStyles.body(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatRemaining(int seconds) {
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (days > 0) return '$days d $hours h';
    if (hours > 0) return '$hours h $minutes min';
    return '$minutes min';
  }
}

class _QuotaRow extends StatelessWidget {
  const _QuotaRow({
    required this.icon,
    required this.label,
    required this.used,
    required this.limit,
    required this.unlimited,
  });

  final IconData icon;
  final String label;
  final int? used;
  final int? limit;
  final bool unlimited;

  @override
  Widget build(BuildContext context) {
    final value = unlimited || limit == null
        ? '${used ?? 0} · Ilimitadas'
        : '${used ?? 0} de $limit';

    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.body(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: AppTextStyles.mono(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DownloadStep extends StatelessWidget {
  const _DownloadStep({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFFF3D1A),
            ),
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.body(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: AppTextStyles.body(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
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
