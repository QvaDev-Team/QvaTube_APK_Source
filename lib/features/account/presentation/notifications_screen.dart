import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../auth/presentation/providers/auth_controller.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/catalog_models.dart';

/// Notificaciones del usuario (`GET /api/notifications`).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Notificaciones'),
        actions: [
          notifications.maybeWhen(
            data: (data) {
              if (data.items.isEmpty) return const SizedBox.shrink();
              return Row(
                children: [
                  if (data.unread > 0)
                    IconButton(
                      tooltip: 'Marcar todas como leídas',
                      onPressed: () async {
                        await ref
                            .read(catalogApiProvider)
                            .markAllNotificationsRead();
                        ref.invalidate(notificationsProvider);
                      },
                      icon: const Icon(Icons.done_all, size: 20),
                    ),
                  IconButton(
                    tooltip: 'Borrar todas',
                    onPressed: () async {
                      await ref
                          .read(catalogApiProvider)
                          .clearAllNotifications();
                      ref.invalidate(notificationsProvider);
                    },
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                ],
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: notifications.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (error, stack) => Center(
          child: Text(
            'No se pudieron cargar las notificaciones.',
            style: AppTextStyles.body(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        data: (data) {
          if (data.items.isEmpty) {
            return Center(
              child: Text(
                'Todavía no tienes notificaciones.',
                style: AppTextStyles.body(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            );
          }
          return RefreshIndicator(
            color: AppColors.accent,
            backgroundColor: AppColors.surface,
            onRefresh: () async => ref.invalidate(notificationsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: data.items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = data.items[index];
                return _NotificationTile(
                  item: item,
                  onTap: () async {
                    final router = GoRouter.of(context);
                    if (item.id != null) {
                      await ref
                          .read(catalogApiProvider)
                          .markNotificationRead(item.id!);
                      ref.invalidate(notificationsProvider);
                    }
                    // Avisos del programa de creadores: abren el Modo creador
                    // (tras refrescar `me` si acaba de ser nombrado).
                    if (item.isCreator) {
                      final auth = ref.read(authControllerProvider.notifier);
                      if (ref.read(authControllerProvider).user?.creator ==
                          null) {
                        await auth.restoreSession();
                      }
                      if (ref.read(authControllerProvider).user?.creator !=
                          null) {
                        router.push('/cuenta/creador');
                      }
                    }
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final NotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: item.read ? AppColors.border : AppColors.accent,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.image.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.sm),
                child: Image.network(
                  item.image,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox(),
                ),
              )
            else
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentSoft,
                ),
                child: const Icon(
                  Icons.notifications_none,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title ?? '',
                    style: AppTextStyles.body(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (item.body != null && item.body!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.body!,
                      style: AppTextStyles.body(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (item.createdAt != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      item.createdAt!,
                      style: AppTextStyles.mono(
                        fontSize: 10.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!item.read)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4, left: 6),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
