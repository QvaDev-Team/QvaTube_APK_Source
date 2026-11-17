import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qvatube_apk/core/widgets/focus_ring.dart';

void main() {
  testWidgets('el marco aparece al enfocar con el mando y se va al salir', (
    tester,
  ) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              for (final label in ['A', 'B'])
                FocusRing(
                  key: ValueKey(label),
                  child: InkWell(
                    onTap: () {},
                    child: SizedBox(width: 80, height: 80, child: Text(label)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    double opacityOf(String label) => tester
        .widget<AnimatedOpacity>(
          find.descendant(
            of: find.byKey(ValueKey(label)),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    expect(opacityOf('A'), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(opacityOf('A'), 1);
    expect(opacityOf('B'), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(opacityOf('A'), 0);
    expect(opacityOf('B'), 1);
  });

  testWidgets('no encoge al hijo: un botón en Expanded llena su casilla', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: Row(
              children: [
                for (final label in ['A', 'B', 'C'])
                  Expanded(
                    child: FocusRing(
                      child: InkWell(
                        key: ValueKey(label),
                        onTap: () {},
                        // Igual que el botón de la navegación inferior:
                        // una Column, que se encoge a su contenido si las
                        // restricciones le llegan sueltas.
                        child: const SizedBox(
                          height: 66,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [Icon(Icons.home, size: 22)],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // Cada botón ocupa su tercio entero y el icono queda en su centro.
    for (final (i, label) in ['A', 'B', 'C'].indexed) {
      final rect = tester.getRect(find.byKey(ValueKey(label)));
      expect(rect.width, 100);
      expect(rect.left, i * 100);
      final icon = tester.getCenter(
        find.descendant(
          of: find.byKey(ValueKey(label)),
          matching: find.byIcon(Icons.home),
        ),
      );
      expect(icon.dx, i * 100 + 50);
    }
  });
}
