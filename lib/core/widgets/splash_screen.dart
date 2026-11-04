import 'package:flutter/material.dart';

import '../theme/season_calendar.dart';

/// Pantalla de inicio (Splash) idéntica a la de la web de QvaTube.
///
/// Se mantiene visible hasta que se determina si el usuario va al login o
/// entra con su sesión directa. El arte de la temporada sale del APK y se
/// elige por la fecha ([SeasonCalendar]): se ve desde el primer fotograma,
/// sin esperar al servidor.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Image.asset(
          SeasonCalendar.splashFor(),
          width: 256,
          height: 256,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => Image.asset(
            SeasonCalendar.defaultSplash,
            width: 256,
            height: 256,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
