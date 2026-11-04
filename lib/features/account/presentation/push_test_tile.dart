import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/push/push_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';

/// Estado de las notificaciones push y token FCM de este teléfono, para
/// probarlas con "Enviar mensaje de prueba" de la consola de Firebase.
class PushTestTile extends StatelessWidget {
  const PushTestTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PushStatus>(
      valueListenable: PushService.status,
      builder: (context, status, _) {
        final (icon, color, text) = switch (status.state) {
          'ready' => (Icons.check_circle, AppColors.success, 'Activas: este teléfono puede recibir notificaciones.'),
          'loading' => (Icons.hourglass_top, AppColors.textSecondary, 'Conectando con Google…'),
          'unavailable' => (Icons.block, AppColors.danger, 'No disponibles: este teléfono no tiene Google Play Services.'),
          _ => (Icons.error_outline, AppColors.danger, 'No se pudo registrar el teléfono.'),
        };
        final token = status.token;
        return Container(
          padding: const EdgeInsets.all(14),
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
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: AppTextStyles.body(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              if (status.detail != null) ...[
                const SizedBox(height: 6),
                Text(
                  status.detail!,
                  style: AppTextStyles.body(fontSize: 11.5, color: AppColors.textSecondary),
                ),
              ],
              if (token != null) ...[
                const SizedBox(height: 10),
                SelectableText(
                  token,
                  maxLines: 3,
                  style: AppTextStyles.mono(fontSize: 10.5, color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (token != null)
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: token));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Token copiado.')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copiar token'),
                    ),
                  if (status.state != 'unavailable')
                    TextButton.icon(
                      onPressed: status.state == 'loading' ? null : PushService.refreshToken,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reintentar'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
