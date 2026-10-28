import 'package:flutter/material.dart';

import '../theme/app_assets.dart';

/// Pantalla de inicio (Splash) idéntica a la de la web de QvaTube.
///
/// Se mantiene visible hasta que se determina si el usuario va al login o
/// entra con su sesión directa.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Image.asset(
          AppAssets.icon('512'),
          width: 256,
          height: 256,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Image.asset(
            'assets/themes/halloween/icons/icon-512.png',
            width: 256,
            height: 256,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Image.asset(
              'assets/icons/icon-512.png',
              width: 256,
              height: 256,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
