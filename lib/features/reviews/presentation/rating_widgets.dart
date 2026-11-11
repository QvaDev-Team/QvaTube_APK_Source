import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../catalog/application/catalog_providers.dart';

/// Dorado de las estrellas de valoración.
const Color ratingGold = Color(0xFFFFC83D);

/// `1234` → `1.234`.
String formatCount(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// "Basado en 1 valoración" / "Basado en 1.234 valoraciones".
String ratingBasisLabel(int total) {
  if (total <= 0) return 'Aún no hay valoraciones';
  return 'Basado en ${formatCount(total)} '
      '${total == 1 ? 'valoración' : 'valoraciones'}';
}

/// Fila de 5 estrellas con relleno parcial (4.3 → 4 llenas y 30 % de la 5.ª).
class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.value, this.size = 22});

  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: EdgeInsets.only(right: i == 4 ? 0 : size * 0.12),
            child: _PartialStar(fill: (value - i).clamp(0.0, 1.0), size: size),
          ),
      ],
    );
  }
}

class _PartialStar extends StatelessWidget {
  const _PartialStar({required this.fill, required this.size});

  final double fill;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Icon(Icons.star_rounded, size: size, color: AppColors.border),
          ClipRect(
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: fill,
              child: Icon(Icons.star_rounded, size: size, color: ratingGold),
            ),
          ),
        ],
      ),
    );
  }
}

/// Qubi, la mascota de QvaTube (PNG con fondo transparente), sobre un
/// resplandor rojo suave para que se integre con el fondo oscuro.
class QubiMascot extends StatelessWidget {
  const QubiMascot({super.key, this.size = 120});

  static const String asset = 'assets/mascota/qubi.png';

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              AppColors.accent.withValues(alpha: 0.30),
              AppColors.accent.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.72],
          ),
        ),
        child: Image.asset(
          asset,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          semanticLabel: 'Qubi, la mascota de QvaTube',
        ),
      ),
    );
  }
}

/// Bloque de valoración media: Qubi, "4.8 /5", estrellas y número real de
/// valoraciones (`GET /api/reviews`).
class RatingSummary extends ConsumerWidget {
  const RatingSummary({super.key, this.mascotSize = 120});

  final double mascotSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(reviewsProvider);
    final summary = reviews.whenData(
      (d) => (average: d.average, total: d.total),
    );

    return Row(
      children: [
        QubiMascot(size: mascotSize),
        SizedBox(width: mascotSize * 0.16),
        Expanded(
          child: summary.when(
            loading: () => const AppShimmer(
              child: Column(
                children: [
                  SkeletonBox(width: 120, height: 56),
                  SizedBox(height: 10),
                  SkeletonBox(width: 150, height: 20),
                  SizedBox(height: 8),
                  SkeletonBox(width: 170, height: 12),
                ],
              ),
            ),
            error: (error, stack) => _SummaryText(
              average: null,
              caption: 'No se pudieron cargar las valoraciones',
            ),
            data: (d) => _SummaryText(
              average: d.total > 0 ? d.average : null,
              caption: ratingBasisLabel(d.total),
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryText extends StatelessWidget {
  const _SummaryText({required this.average, required this.caption});

  final double? average;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: average == null ? '–' : average!.toStringAsFixed(1),
                  style: AppTextStyles.body(
                    fontSize: 58,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                TextSpan(
                  text: ' /5',
                  style: AppTextStyles.body(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMuted,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          RatingStars(value: average ?? 0, size: 28),
          const SizedBox(height: 8),
          Text(
            caption,
            style: AppTextStyles.body(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
