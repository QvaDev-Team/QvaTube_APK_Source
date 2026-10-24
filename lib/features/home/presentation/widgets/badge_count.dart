import 'package:flutter/material.dart';
import 'package:qvatube_apk/core/theme/app_colors.dart';
import 'package:qvatube_apk/core/theme/app_text.dart';

/// Badge pill de contador (notificaciones, descargas, etc.).
///
/// El "halo" del borde debe coincidir con el color del fondo sobre el
/// que flota el badge para que parezca recortado sobre él.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.count,
    this.haloColor = AppColors.background,
    this.maxCount = 9,
  });

  /// Número a mostrar. Muestra cero notificaciones como badge oculto
  /// solo si el llamador lo controla (`count > 0`).
  final int count;

  /// Color del halo (borde) que simula el fondo donde se apoya.
  final Color haloColor;

  /// A partir de este valor se muestra "{maxCount}+".
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: haloColor, width: 2),
      ),
      child: Text(
        count > maxCount ? '$maxCount+' : '$count',
        style: AppTextStyles.mono(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppColors.accentInk,
        ),
      ),
    );
  }
}
