import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/app_colors.dart';
import '../theme/season_branding.dart';

/// Logotipo de QvaTube.
///
/// Usa el logo de temporada que manda el servidor (descargado y guardado por
/// [SeasonBranding]); sin copia, el del APK (`assets/theme.json`).
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
    return ListenableBuilder(
      listenable: Listenable.merge([AppAssets.revision, SeasonBranding.revision]),
      builder: (context, _) {
        final bundled = Image.asset(
          AppAssets.logo,
          height: height,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) =>
              _FallbackLogo(height: height),
        );
        final downloaded = SeasonBranding.logoFile;
        final logo = downloaded == null
            ? bundled
            : Image.file(
                downloaded,
                height: height,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => bundled,
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
