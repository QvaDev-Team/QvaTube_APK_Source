import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';

/// Tarjeta de contenido en estado pendiente de datos (spec §6.3).
///
/// Mantiene la retícula y la proporción 2:3 reales para que, al conectar el
/// catálogo, solo haya que sustituir el contenido.
class PosterPlaceholder extends StatelessWidget {
  const PosterPlaceholder({
    super.key,
    this.title = 'Contenido pendiente',
    this.subtitle,
    this.aspectRatio = 2 / 3,
    this.width,
  });

  final String title;
  final String? subtitle;
  final double aspectRatio;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: aspectRatio,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: AppColors.border),
              ),
              child: const Center(
                child: Icon(
                  Icons.movie_filter_outlined,
                  color: AppColors.textMuted,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body(
                fontSize: 10.5,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}

/// Ítem de retícula: póster 2:3 (o 1:1) + título de una línea.
class PosterGridItem extends StatelessWidget {
  const PosterGridItem({
    super.key,
    required this.title,
    this.subtitle,
    this.aspectRatio = 2 / 3,
  });

  final String title;
  final String? subtitle;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: AppColors.border),
              ),
              child: const Center(
                child: Icon(
                  Icons.movie_filter_outlined,
                  color: AppColors.textMuted,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.body(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Estado vacío genérico de una sección por definir.
class PendingContentNotice extends StatelessWidget {
  const PendingContentNotice({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_empty, size: 18, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.body(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
