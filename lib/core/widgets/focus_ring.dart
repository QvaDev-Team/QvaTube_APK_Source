import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Marco visible alrededor de [child] cuando algo dentro tiene el foco del
/// teclado o del mando a distancia (Google TV).
///
/// El resaltado de foco de `InkWell` se pinta *debajo* de su contenido, así
/// que en una carátula con imagen no se ve: en la tele no se sabía qué
/// tarjeta estaba seleccionada. Este widget no toma el foco él mismo (lo
/// sigue teniendo el `InkWell`/botón de dentro); solo escucha si algún
/// descendiente lo tiene y dibuja el borde por encima.
class FocusRing extends StatefulWidget {
  const FocusRing({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadii.md)),
    this.scale = 1,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// Aumento al enfocar (1 = sin zoom). El marco va por dentro del borde:
  /// así no lo recortan los carruseles horizontales.
  final double scale;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (value) {
        // Solo cuenta el foco de teclado/mando, no el de un toque.
        final keyboard =
            FocusManager.instance.highlightMode ==
            FocusHighlightMode.traditional;
        final show = value && keyboard;
        if (show != _focused) setState(() => _focused = show);
      },
      child: AnimatedScale(
        scale: _focused ? widget.scale : 1,
        duration: const Duration(milliseconds: 140),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _focused ? 1 : 0,
                  duration: const Duration(milliseconds: 140),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: widget.borderRadius,
                      border: Border.all(color: AppColors.accent, width: 3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
