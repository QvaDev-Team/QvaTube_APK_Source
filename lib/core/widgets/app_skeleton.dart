import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../layout/responsive.dart';

/// Efecto de brillo / resplandor Shimmer para loaders tipo esqueleto.
class AppShimmer extends StatefulWidget {
  const AppShimmer({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });

  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.baseColor ?? AppColors.surfaceSecondary;
    final highlight = widget.highlightColor ?? const Color(0x33FFFFFF);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final width = bounds.width;
            final progress = _controller.value;
            // Desplazamiento continuo del gradiente de izquierda a derecha
            final dx = (progress * 2 - 1) * width;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                base,
                highlight,
                base,
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: _SlidingGradientTransform(slidePercent: dx / width),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.slidePercent});

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}

/// Contenedor base de esqueleto con bordes redondeados y color tenue.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.color,
  });

  final double? width;
  final double? height;
  final double borderRadius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton loader para una tarjeta de contenido individual (póster 2:3 + 2 líneas de texto).
class SkeletonMediaCard extends StatelessWidget {
  const SkeletonMediaCard({
    super.key,
    this.width = 122,
    this.aspectRatio = 2 / 3,
  });

  final double width;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: aspectRatio,
            child: const SkeletonBox(
              borderRadius: AppRadii.md,
            ),
          ),
          const SizedBox(height: 8),
          const SkeletonBox(
            height: 12,
            width: double.infinity,
            borderRadius: 4,
          ),
          const SizedBox(height: 5),
          const SkeletonBox(
            height: 10,
            width: 70,
            borderRadius: 4,
          ),
        ],
      ),
    );
  }
}

/// Skeleton loader para un carrusel horizontal de tarjetas con shimmer.
class SkeletonMediaCarousel extends StatelessWidget {
  const SkeletonMediaCarousel({
    super.key,
    this.itemCount = 5,
    this.itemWidth = 122,
    this.aspectRatio = 2 / 3,
  });

  final int itemCount;
  final double itemWidth;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: SizedBox(
        height: itemWidth * (1 / aspectRatio) + 55,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itemCount,
          separatorBuilder: (context, index) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            return SkeletonMediaCard(
              width: itemWidth,
              aspectRatio: aspectRatio,
            );
          },
        ),
      ),
    );
  }
}

/// Skeleton loader para la retícula del catálogo de 3 columnas con shimmer.
class SkeletonCatalogGrid extends StatelessWidget {
  const SkeletonCatalogGrid({
    super.key,
    this.itemCount = 9,
    this.gridAspectRatio = 0.5,
  });

  final int itemCount;
  final double gridAspectRatio;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        gridDelegate: posterGridDelegate(
          context,
          mainAxisSpacing: 12,
          crossAxisSpacing: 10,
          childAspectRatio: gridAspectRatio,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SkeletonBox(borderRadius: AppRadii.md),
              ),
              SizedBox(height: 6),
              SkeletonBox(height: 11, width: double.infinity, borderRadius: 3),
              SizedBox(height: 4),
              SkeletonBox(height: 9, width: 45, borderRadius: 3),
            ],
          );
        },
      ),
    );
  }
}

