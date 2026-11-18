import 'package:flutter/material.dart';

import '../network/response_cache.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Franja fina que avisa de que no hay conexión y que lo que se ve es el
/// catálogo guardado. Desaparece sola cuando vuelve la conexión.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: OfflineStatus.offline,
      builder: (context, offline, _) => AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: offline
            ? Container(
                width: double.infinity,
                color: AppColors.surfaceSecondary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      size: 16,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Sin conexión · estás viendo el catálogo guardado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
    );
  }
}
