import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/device_channel.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../auth/presentation/providers/auth_controller.dart';
import '../../catalog/domain/catalog_models.dart';

/// Foto de perfil.
///
/// Sube la imagen con `POST /api/auth/avatar` (multipart, campo `photo`) y la
/// elimina con `DELETE /api/auth/avatar`.
class AvatarScreen extends ConsumerWidget {
  const AvatarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;
    final avatarUrl = absoluteMediaUrl(user?.avatarUrl);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Foto de perfil'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Center(
            child: Container(
              width: 140,
              height: 140,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.accentGradient,
              ),
              child: avatarUrl.isEmpty
                  ? Center(
                      child: Text(
                        user?.initials ?? 'Q',
                        style: AppTextStyles.body(
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accentInk,
                        ),
                      ),
                    )
                  : Image.network(
                      avatarUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Text(
                          user?.initials ?? 'Q',
                          style: AppTextStyles.body(
                            fontSize: 48,
                            fontWeight: FontWeight.w800,
                            color: AppColors.accentInk,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          if (authState.error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                authState.error!,
                style: AppTextStyles.body(
                  fontSize: 12.5,
                  color: AppColors.danger,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: authState.isWorking
                  ? null
                  : () async {
                      final path = await DeviceChannel.pickImage();
                      if (path == null || !context.mounted) return;
                      final name = path.split('/').last;
                      await ref
                          .read(authControllerProvider.notifier)
                          .uploadAvatar(filePath: path, fileName: name);
                    },
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: Text(
                authState.isWorking ? 'Subiendo…' : 'Elegir una imagen',
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: (authState.isWorking || avatarUrl.isEmpty)
                  ? null
                  : () async {
                      await ref
                          .read(authControllerProvider.notifier)
                          .deleteAvatar();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Foto eliminada.')),
                      );
                    },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.border),
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Quitar la foto'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'La imagen se envía al servidor de QvaTube con tu sesión iniciada.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body(
              fontSize: 11.5,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
