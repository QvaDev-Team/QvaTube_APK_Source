import 'package:flutter/material.dart';

import '../theme/app_assets.dart';
import '../theme/season_branding.dart';

/// Pantalla de inicio (Splash) idéntica a la de la web de QvaTube.
///
/// Se mantiene visible hasta que se determina si el usuario va al login o
/// entra con su sesión directa. Muestra el icono de la temporada que dijo el
/// servidor la última vez ([SeasonBranding]); sin copia, el del APK.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bundled(BuildContext context, Object error, StackTrace? stack) =>
        Image.asset(
          'assets/icons/icon-512.png',
          width: 256,
          height: 256,
          fit: BoxFit.contain,
        );

    final asset = Image.asset(
      AppAssets.icon('512'),
      width: 256,
      height: 256,
      fit: BoxFit.contain,
      errorBuilder: bundled,
    );
    final downloaded = SeasonBranding.faviconFile;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: downloaded == null
            ? asset
            : Image.file(
                downloaded,
                width: 256,
                height: 256,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => asset,
              ),
      ),
    );
  }
}
