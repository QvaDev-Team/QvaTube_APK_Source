import 'package:flutter/material.dart';

import '../../../core/push/push_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';

/// Interruptor para activar o desactivar las notificaciones del teléfono
/// (avisos de la cuenta y de versiones nuevas).
class NotificationsSwitchTile extends StatelessWidget {
  const NotificationsSwitchTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PushService.enabled,
      builder: (context, enabled, _) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: SwitchListTile(
          value: enabled,
          onChanged: PushService.setEnabled,
          activeThumbColor: AppColors.accent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          secondary: Icon(
            enabled ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
            color: enabled ? AppColors.accent : AppColors.textSecondary,
          ),
          title: Text(
            'Notificaciones',
            style: AppTextStyles.body(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            enabled ? 'Activadas' : 'Desactivadas',
            style: AppTextStyles.body(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }
}
