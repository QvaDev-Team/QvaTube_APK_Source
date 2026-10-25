import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qvatube_apk/features/home/presentation/widgets/info_row.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../auth/presentation/providers/auth_controller.dart';
import '../../catalog/domain/catalog_models.dart';

/// Pantalla de perfil del usuario (`GET /api/auth/me`).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

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
        title: const Text('Mi perfil'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Container(
                  width: 78,
                  height: 78,
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.accentGradient,
                  ),
                  child: (avatarUrl.isNotEmpty)
                      ? Image.network(
                          avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _initials(user?.initials ?? 'Q'),
                        )
                      : _initials(user?.initials ?? 'Q'),
                ),
                const SizedBox(height: 14),
                Text(
                  user?.name ?? 'Invitado',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? 'Sin sesión',
                  style: AppTextStyles.body(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (user?.plan != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(color: AppColors.accent),
                    ),
                    child: Text(
                      'PLAN ${user!.plan!.toUpperCase()}',
                      style: AppTextStyles.mono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          InfoRow(
            icon: Icons.telegram,
            label: 'Telegram',
            value: (user?.telegramLinked ?? false)
                ? 'Vinculado'
                : 'Sin vincular',
            accent: (user?.telegramLinked ?? false) ? AppColors.success : null,
          ),
          if (user?.planExpiresAt != null)
            InfoRow(
              icon: Icons.event_available_outlined,
              label: 'Plan válido hasta',
              value: user!.planExpiresAt!,
            ),
          // _TelegramLinkCard(),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.push('/cuenta/nombre'),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Cambiar nombre visible'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => context.push('/cuenta/avatar'),
            icon: const Icon(Icons.camera_alt_outlined, size: 18),
            label: const Text('Cambiar foto de perfil'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => context.push('/cuenta/plan'),
            icon: const Icon(Icons.bolt, size: 18),
            label: const Text('Plan y suscripción'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
            ),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }

  Widget _initials(String text) {
    return Center(
      child: Text(
        text,
        style: AppTextStyles.body(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: AppColors.accentInk,
        ),
      ),
    );
  }
}

/// Vinculación con Telegram (`POST /api/auth/link-code`).
// class _TelegramLinkCard extends ConsumerStatefulWidget {
//   @override
//   ConsumerState<_TelegramLinkCard> createState() => _TelegramLinkCardState();
// }

// class _TelegramLinkCardState extends ConsumerState<_TelegramLinkCard> {
//   String? _code;
//   int? _expiresIn;

//   @override
//   Widget build(BuildContext context) {
//     final authState = ref.watch(authControllerProvider);

//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: AppColors.surface,
//         borderRadius: BorderRadius.circular(AppRadii.md),
//         border: Border.all(color: AppColors.border),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               const Icon(Icons.telegram, color: AppColors.telegram, size: 20),
//               const SizedBox(width: 10),
//               Expanded(
//                 child: Text(
//                   'Vincular con Telegram',
//                   style: AppTextStyles.body(
//                     fontSize: 14,
//                     fontWeight: FontWeight.w700,
//                   ),
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 6),
//           Text(
//             'Recibe códigos y avisos de tu cuenta directamente en Telegram.',
//             style: AppTextStyles.body(
//               fontSize: 12,
//               color: AppColors.textSecondary,
//             ),
//           ),
//           if (authState.error != null) ...[
//             const SizedBox(height: 10),
//             Text(
//               authState.error!,
//               style: AppTextStyles.body(fontSize: 12, color: AppColors.danger),
//             ),
//           ],
//           if (_code != null) ...[
//             const SizedBox(height: 14),
//             Container(
//               width: double.infinity,
//               padding: const EdgeInsets.symmetric(vertical: 12),
//               alignment: Alignment.center,
//               decoration: BoxDecoration(
//                 color: AppColors.surfaceSecondary,
//                 borderRadius: BorderRadius.circular(AppRadii.sm),
//                 border: Border.all(color: AppColors.border),
//               ),
//               child: Text(
//                 _code!,
//                 style: AppTextStyles.mono(
//                   fontSize: 22,
//                   fontWeight: FontWeight.w700,
//                   letterSpacing: 4,
//                 ),
//               ),
//             ),
//             const SizedBox(height: 8),
//             Text(
//               'Envía este código al bot de QvaTube'
//               '${_expiresIn != null ? ' (expira en ${_expiresIn! ~/ 60} min)' : ''}.',
//               style: AppTextStyles.body(
//                 fontSize: 11.5,
//                 color: AppColors.textMuted,
//               ),
//             ),
//           ],
//           const SizedBox(height: 12),
//           SizedBox(
//             width: double.infinity,
//             child: ElevatedButton(
//               onPressed: authState.isWorking
//                   ? null
//                   : () async {
//                       final link = await ref
//                           .read(authControllerProvider.notifier)
//                           .createTelegramLinkCode();
//                       if (!mounted) return;
//                       if (link?.code != null) {
//                         setState(() {
//                           _code = link!.code;
//                           _expiresIn = link.expiresIn;
//                         });
//                       }
//                     },
//               child: Text(_code == null ? 'Generar código' : 'Generar otro'),
//             ),
//           ),
//           if (_code != null) ...[
//             const SizedBox(height: 8),
//             SizedBox(
//               width: double.infinity,
//               child: OutlinedButton.icon(
//                 onPressed: () async {
//                   final config = await ref.read(siteConfigProvider.future);
//                   final bot = config.botUsername ?? 'qvatube_bot';
//                   await DeviceChannel.openUrl('https://t.me/$bot');
//                 },
//                 icon: const Icon(Icons.open_in_new, size: 16),
//                 label: const Text('Abrir el bot de Telegram'),
//               ),
//             ),
//           ],
//         ],
//       ),
//     );
//   }
// }
