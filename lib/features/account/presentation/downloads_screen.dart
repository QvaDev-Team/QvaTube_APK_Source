import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/device_channel.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../catalog/application/catalog_providers.dart';

/// Pantalla "Mis descargas" en el menú de cuenta.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          const SizedBox(height: 24),
          Text(
            'CÓMO DESCARGAR',
            style: AppTextStyles.display(fontSize: 14, color: AppColors.textMuted),
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

