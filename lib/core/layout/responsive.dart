import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Diseño adaptable para escritorio y pantallas anchas.
///
/// En el teléfono no cambia nada: todo depende de que la ventana mida al
/// menos [kWideLayoutMinWidth] de ancho (escritorio o tablet apaisada).
const double kWideLayoutMinWidth = 900;

/// Ancho máximo del contenido principal en monitores muy anchos.
const double kMaxContentWidth = 1600;

/// Ancho de las pantallas secundarias (cuenta, planes, login…) en escritorio.
const double kFormMaxWidth = 720;

/// Ancho máximo de cada póster en las cuadrículas anchas: caben más
/// columnas cuanto más ancha es la ventana.
const double kPosterMaxWidth = 175;

/// `true` si la ventana es ancha (escritorio o tablet apaisada).
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideLayoutMinWidth;

/// Cuadrícula de pósters: [mobileColumns] columnas fijas en el teléfono y,
/// en pantallas anchas, tantas como quepan con pósters de hasta
/// [kPosterMaxWidth] (mismas proporciones y separaciones).
SliverGridDelegate posterGridDelegate(
  BuildContext context, {
  int mobileColumns = 3,
  double childAspectRatio = 2 / 3,
  double mainAxisSpacing = 0,
  double crossAxisSpacing = 0,
  double? mainAxisExtent,
  double wideMaxWidth = kPosterMaxWidth,
}) {
  if (!isWideLayout(context)) {
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: mobileColumns,
      childAspectRatio: childAspectRatio,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisExtent: mainAxisExtent,
    );
  }
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: wideMaxWidth,
    childAspectRatio: childAspectRatio,
    mainAxisSpacing: mainAxisSpacing,
    crossAxisSpacing: crossAxisSpacing,
    mainAxisExtent: mainAxisExtent,
  );
}

/// Centra [child] con un ancho máximo cuando la ventana es ancha; en el
/// teléfono lo devuelve tal cual. Fuera del ancho se ve el fondo de la app.
class DesktopFrame extends StatelessWidget {
  const DesktopFrame({
    super.key,
    required this.child,
    this.maxWidth = kFormMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!isWideLayout(context)) return child;
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(color: AppColors.borderSoft),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Desplazamiento que también se arrastra con el ratón y el trackpad (por
/// defecto Flutter en escritorio solo arrastra con el dedo), para poder
/// mover los carruseles horizontales sin rueda horizontal.
class QvaScrollBehavior extends MaterialScrollBehavior {
  const QvaScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };
}
