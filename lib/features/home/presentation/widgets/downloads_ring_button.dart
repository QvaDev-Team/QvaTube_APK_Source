import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../../../core/platform/device_channel.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../telegram/telegram_files.dart';
import '../../../telegram/telegram_service.dart';

/// Botón de descargas de la barra superior: un aro alrededor del icono
/// muestra el progreso conjunto de las descargas de Telegram en marcha
/// (gira en gris mientras Telegram conecta) y, si hay varias, cuántas.
/// Abre Cuenta → Telegram (o "Mis descargas" si este teléfono no puede
/// usar Telegram en la app).
class DownloadsRingButton extends StatelessWidget {
  const DownloadsRingButton({super.key});

  static const double _size = 32;

  @override
  Widget build(BuildContext context) {
    final files = TelegramFiles.instance;
    final online = TelegramService.instance.online;
    return ListenableBuilder(
      listenable: Listenable.merge([files, online]),
      builder: (context, _) {
        final p = files.activeProgress;
        final active = p.count > 0;
        final value = p.total > 0 ? (p.done / p.total).clamp(0.0, 1.0) : 0.0;
        final waiting = active && !online.value;
        final percent = (value * 100).floor();

        return Tooltip(
          message: active
              ? waiting
                    ? 'Descargas: esperando conexión con Telegram'
                    : 'Descargando ${p.count == 1 ? '1 archivo' : '${p.count} archivos'} · $percent %'
              : 'Descargas',
          child: InkResponse(
            key: const Key('downloads-ring'),
            radius: _size / 2 + 4,
            onTap: () => context.push(
              TelegramService.isAvailable || DeviceChannel.isDesktop
                  ? '/cuenta/telegram'
                  : '/cuenta/descargas',
            ),
            child: SizedBox(
              width: _size,
              height: _size,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // Pista del aro (siempre visible mientras hay descargas).
                  if (active)
                    const SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: 1,
                        strokeWidth: 2.2,
                        color: AppColors.border,
                      ),
                    ),
                  if (active)
                    SizedBox.expand(
                      child: waiting
                          ? const CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: AppColors.textMuted,
                            )
                          : TweenAnimationBuilder<double>(
                              tween: Tween(end: value),
                              duration: const Duration(milliseconds: 450),
                              curve: Curves.easeOut,
                              builder: (context, v, _) =>
                                  CircularProgressIndicator(
                                    value: v,
                                    strokeWidth: 2.2,
                                    strokeCap: StrokeCap.round,
                                    color: AppColors.accent,
                                  ),
                            ),
                    ),
                  Icon(
                    active
                        ? LucideIcons.arrowDown
                        : LucideIcons.arrowDownToLine,
                    size: active ? 15 : 20,
                    color: active ? AppColors.accent : AppColors.textSecondary,
                  ),
                  if (p.count > 1)
                    Positioned(
                      right: -4,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.background,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          '${p.count}',
                          style: AppTextStyles.body(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
