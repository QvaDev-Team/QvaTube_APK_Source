import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_colors.dart';

/// Logotipo de QvaTube.
///
/// La ruta se resuelve desde el manifiesto de assets (`assets/theme.json`), así
/// que el logo de la temporada se cambia sin tocar código.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.height = 32,
    this.showWordmark = false,
  });

  final double height;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppAssets.revision,
      builder: (context, _, _) {
        final logo = Image.asset(
          AppAssets.logo,
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) =>
              _FallbackLogo(height: height),
        );

        if (!showWordmark) return logo;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            logo,
            const SizedBox(width: 8),
            Text(
              'QvaTube',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    letterSpacing: 0.2,
                  ),
            ),
          ],
        );
      },
    );
  }
}

/// Marca tipográfica usada si el PNG del logo no está disponible.
class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: AppColors.accentGradient,
      ),
      child: Text(
        'QvaTube',
        style: TextStyle(
          fontFamily: 'Bebas Neue',
          fontSize: height * 0.5,
          height: 1,
          color: AppColors.accentInk,
        ),
      ),
    );
  }
}
