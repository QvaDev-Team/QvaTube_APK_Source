import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qvatube_apk/features/home/presentation/widgets/badge_count.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../auth/application/auth_controller.dart';
import '../../../catalog/application/catalog_providers.dart';
import '../../../catalog/domain/catalog_models.dart';
import 'account_menu_sheet.dart';

/// Barra superior de la app (spec §6.1).
///
/// Logo de QvaTube a la izquierda, buscador y avatar del usuario a la derecha.
/// El avatar despliega el menú de cuenta.
class QvaTopBar extends ConsumerWidget {
  const QvaTopBar({super.key, this.showSearch = true});

  final bool showSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;
    // Contador de notificaciones sin leer (`GET /api/notifications`).
    final unread = authState.isAuthenticated
        ? ref.watch(notificationsProvider).value?.unread ?? 0
        : 0;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xF20A0A0B), Color(0xE60A0A0B)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            border: Border(bottom: BorderSide(color: AppColors.borderSoft)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  const AppLogo(height: 26),
                  const Spacer(),
                  if (showSearch)
                    IconButton(
                      onPressed: () => context.push('/buscar'),
                      tooltip: 'Buscar',
                      icon: const Icon(Icons.search),
                      style: IconButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                      ),
                    ),
                  const SizedBox(width: 4),
                  _UserAvatar(
                    label: user?.initials ?? 'Q',
                    imageUrl: absoluteMediaUrl(user?.avatarUrl),
                    unreadCount: unread,
                    onTap: () => showAccountMenuSheet(context, ref),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({
    required this.label,
    required this.onTap,
    this.imageUrl,
    this.unreadCount = 0,
  });

  final String label;
  final String? imageUrl;
  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          key: const Key('user-avatar'),
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 36,
            height: 36,
            clipBehavior: Clip.antiAlias,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.accentGradient,
            ),
            child: (url != null && url.isNotEmpty)
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _initials(label),
                  )
                : _initials(label),
          ),
        ),
        if (unreadCount > 0)
          Positioned(
            right: -2,
            top: -2,
            child: AppBadge(
              count: unreadCount,
              haloColor: AppColors.background,
            ),
          ),
      ],
    );
  }

  Widget _initials(String text) {
    return Center(
      child: Text(
        text,
        style: AppTextStyles.body(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AppColors.accentInk,
        ),
      ),
    );
  }
}
