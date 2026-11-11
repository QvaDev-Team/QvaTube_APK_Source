import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../catalog/application/catalog_providers.dart';

/// Dorado de las estrellas de valoración.
const Color ratingGold = Color(0xFFFFC83D);
const Color _ratingGoldDeep = Color(0xFFFF9E1B);

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

/// Estrella dorada con una órbita roja brillante y destellos.
class OrbitStar extends StatelessWidget {
  const OrbitStar({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Mitad trasera de la órbita (queda detrás de la estrella).
          CustomPaint(
            size: Size.square(size),
            painter: const _OrbitPainter(front: false),
          ),
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFE680), ratingGold, _ratingGoldDeep],
            ).createShader(rect),
            child: Icon(
              Icons.star_rounded,
              size: size * 0.82,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: _ratingGoldDeep.withValues(alpha: 0.6),
                  blurRadius: size * 0.18,
                ),
              ],
            ),
          ),
          // Mitad delantera (cruza por delante de la estrella).
          CustomPaint(
            size: Size.square(size),
            painter: const _OrbitPainter(front: true),
          ),
        ],
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  const _OrbitPainter({required this.front});

  final bool front;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.save();
    canvas.translate(c.dx, c.dy + size.height * 0.04);
    canvas.rotate(-0.32);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: size.width * 1.02,
      height: size.height * 0.36,
    );
    // La mitad inferior de la elipse va delante; la superior, detrás.
    final start = front ? 0.0 : math.pi;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.05
      ..color = AppColors.accent.withValues(alpha: 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.04);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.022
      ..color = AppColors.accent;
    canvas.drawArc(rect, start, math.pi, false, glow);
    canvas.drawArc(rect, start, math.pi, false, line);
    canvas.restore();

    if (front) {
      _sparkle(
        canvas,
        Offset(size.width * 0.82, size.height * 0.08),
        size.width * 0.06,
      );
      _sparkle(
        canvas,
        Offset(size.width * 0.12, size.height * 0.9),
        size.width * 0.04,
      );
    }
  }

  void _sparkle(Canvas canvas, Offset o, double r) {
    final path = Path()
      ..moveTo(o.dx, o.dy - r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
      ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
      ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFE2B0));
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) =>
      oldDelegate.front != front;
}

/// Bloque de valoración media: estrella, "4.8 /5", estrellas y número real de
/// valoraciones (`GET /api/reviews`).
class RatingSummary extends ConsumerWidget {
  const RatingSummary({super.key, this.starSize = 120});

  final double starSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(reviewsProvider);
    final summary = reviews.whenData(
      (d) => (average: d.average, total: d.total),
    );

    return Row(
      children: [
        OrbitStar(size: starSize),
        SizedBox(width: starSize * 0.16),
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
