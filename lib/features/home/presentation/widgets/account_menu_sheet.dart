import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:qvatube_apk/features/catalog/application/catalog_providers.dart';
import 'package:qvatube_apk/features/home/presentation/widgets/badge_count.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/platform/device_channel.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/app_cached_image.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../../catalog/domain/catalog_models.dart';
import '../../../telegram/telegram_service.dart';

/// Menú de cuenta que se despliega al pulsar el avatar (spec §6.1).
Future<void> showAccountMenuSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    barrierColor: AppColors.modalBackdrop,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
    ),
    builder: (context) => const _AccountMenuSheet(),
  );
}

class _AccountMenuSheet extends ConsumerWidget {
  const _AccountMenuSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;

    final avatarUrl = absoluteMediaUrl(user?.avatarUrl);
    final initials = Center(
      child: Text(
        user?.initials ?? 'Q',
        style: AppTextStyles.body(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: AppColors.accentInk,
        ),
      ),
    );

    final unreadNotifications = authState.isAuthenticated
        ? ref.watch(notificationsProvider).value?.unread ?? 0
        : 0;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                // Antes solo pintaba las iniciales aunque hubiera foto.
                Container(
                  width: 44,
                  height: 44,
                  clipBehavior: Clip.antiAlias,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.accentGradient,
                  ),
                  child: avatarUrl.isNotEmpty
                      ? AppCachedImage(
                          imageUrl: avatarUrl,
                          fit: BoxFit.cover,
                          placeholder: initials,
                          errorWidget: initials,
                        )
                      : initials,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'Invitado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.email ??
                            (authState.isGuest
                                ? 'Modo invitado'
                                : 'Cuenta de QvaTube'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (user?.plan != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(color: AppColors.accent),
                    ),
                    child: Text(
                      user!.plan!.toUpperCase(),
                      style: AppTextStyles.mono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                _MenuTile(
                  icon: Icons.person_outline,
                  label: 'Mi perfil',
                  onTap: () => _go(context, '/cuenta/perfil'),
                ),
                _MenuTile(
                  icon: Icons.bolt,
                  label: 'Plan y suscripción',
                  onTap: () => _go(context, '/cuenta/plan'),
                ),
                _MenuTile(
                  icon: Icons.download,
                  label: 'Mis descargas',
                  onTap: () => _go(context, '/cuenta/descargas'),
                ),
                // Gestor de archivos del bot (solo en APK con claves de
                // Telegram y en teléfonos ARM).
                if (TelegramService.isAvailable)
                  _MenuTile(
                    icon: Icons.send,
                    label: 'Telegram',
                    onTap: () => _go(context, '/cuenta/telegram'),
                  ),
                _MenuTile(
                  icon: LucideIcons.bookmark,
                  label: 'Favoritos',
                  onTap: () => _go(context, '/cuenta/favoritos'),
                ),
                // Solo para creadores oficiales (`user.creator`).
                if (user?.creator != null)
                  _MenuTile(
                    icon: LucideIcons.star,
                    label: 'Modo creador',
                    onTap: () => _go(context, '/cuenta/creador'),
                  ),
                _MenuTile(
                  icon: Icons.notifications_none,
                  label: 'Notificaciones',
                  badgeCount: unreadNotifications,
                  onTap: () => _go(context, '/cuenta/notificaciones'),
                ),
                _MenuTile(
                  icon: Icons.settings,
                  label: 'Configuración',
                  onTap: () => _go(context, '/cuenta/configuracion'),
                ),
                _MenuTile(
                  icon: Icons.chat_bubble_outline,
                  label: 'Comunidad de WhatsApp',
                  accent: AppColors.whatsapp,
                  onTap: () async {
                    // Abre directamente la comunidad (enlace de /api/config).
                    // Solo si no se pudo obtener se cae a la pantalla Comunidad.
                    final nav = Navigator.of(context);
                    final router = GoRouter.of(context);
                    String? url;
                    try {
                      url = (await ref.read(siteConfigProvider.future))
                          .whatsappUrl;
                    } catch (_) {}
                    nav.pop();
                    if (url != null && url.isNotEmpty) {
                      DeviceChannel.openUrl(url);
                    } else {
                      router.push('/cuenta/comunidad');
                    }
                  },
                ),
                _MenuTile(
                  icon: Icons.send,
                  label: 'Comunidad de Telegram',
                  accent: AppColors.telegram,
                  onTap: () {
                    Navigator.of(context).pop();
                    DeviceChannel.openUrl(AppConfig.telegramCommunityUrl);
                  },
                ),
                const Divider(height: 1),
                _MenuTile(
                  icon: Icons.logout,
                  label: 'Cerrar sesión',
                  danger: true,
                  onTap: () async {
                    Navigator.of(context).pop();
                    await ref.read(authControllerProvider.notifier).logout();
                    if (context.mounted) {
                      context.go('/login');
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _go(BuildContext context, String path) {
    Navigator.of(context).pop();
    context.push(path);
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeCount = 0,
    this.accent,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accent;
  final bool danger;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : accent ?? AppColors.textSecondary;

    return ListTile(
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: badgeCount > 0
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 20, color: color),
                Positioned(
                  right: -9,
                  left: 12,
                  bottom: 9,
                  child: AppBadge(count: badgeCount),
                ),
              ],
            )
          : Icon(icon, size: 20, color: color),

      title: Text(
        label,
        style: AppTextStyles.body(
          fontSize: 13.5,
          color: danger ? AppColors.danger : AppColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
