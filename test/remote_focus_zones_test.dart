import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qvatube_apk/core/widgets/remote_focus_zones.dart';

/// Mando de la tele: las flechas tienen que poder salir del contenido (que
/// vive en su propio Navigator, como cada pestaña de la app) hacia el menú,
/// la barra superior y el mini reproductor, y volver.
void main() {
  late Map<String, FocusNode> nodes;

  Widget boton(String id) =>
      TextButton(focusNode: nodes[id], onPressed: () {}, child: Text(id));

  Future<void> montar(WidgetTester tester) async {
    nodes = {
      for (final id in [
        'buscar', 'avatar', 'menu0', 'menu1', 'menu2', //
        'oculto', 'c1', 'c2', 'c3', 'pausa', 'cerrar',
      ])
        id: FocusNode(debugLabel: id),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteFocusZones(
            menuNodes: [nodes['menu0']!, nodes['menu1']!, nodes['menu2']!],
            menuIndex: 1,
            top: Row(children: [boton('buscar'), boton('avatar')]),
            menu: SizedBox(
              width: 120,
              child: Column(
                children: [boton('menu0'), boton('menu1'), boton('menu2')],
              ),
            ),
            // Como las pestañas de la app: un Navigator propio y otra
            // sección montada pero oculta (Offstage).
            content: Stack(
              children: [
                Offstage(child: boton('oculto')),
                Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => Column(
                      children: [
                        Row(children: [boton('c1'), boton('c2')]),
                        boton('c3'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            mini: Row(children: [boton('pausa'), boton('cerrar')]),
            layout: (top, menu, content, mini) => Column(
              children: [
                top,
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      menu,
                      Expanded(child: content),
                    ],
                  ),
                ),
                mini,
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String? enfocado() => FocusManager.instance.primaryFocus?.debugLabel;

  Future<void> tecla(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  testWidgets(
    '← desde el contenido va a la sección activa del menú y → vuelve',
    (tester) async {
      await montar(tester);
      nodes['c1']!.requestFocus();
      await tester.pumpAndSettle();

      await tecla(tester, LogicalKeyboardKey.arrowLeft);
      expect(enfocado(), 'menu1');

      await tecla(tester, LogicalKeyboardKey.arrowRight);
      expect(enfocado(), 'c1', reason: 'vuelve a la última carátula');
    },
  );

  testWidgets('dentro del contenido las flechas siguen moviendo el foco', (
    tester,
  ) async {
    await montar(tester);
    nodes['c1']!.requestFocus();
    await tester.pumpAndSettle();

    await tecla(tester, LogicalKeyboardKey.arrowRight);
    expect(enfocado(), 'c2');
    await tecla(tester, LogicalKeyboardKey.arrowLeft);
    expect(enfocado(), 'c1');
  });

  testWidgets('↑ desde el contenido sube a la barra y ↓ baja de nuevo', (
    tester,
  ) async {
    await montar(tester);
    nodes['c1']!.requestFocus();
    await tester.pumpAndSettle();

    await tecla(tester, LogicalKeyboardKey.arrowUp);
    expect(enfocado(), 'buscar');

    await tecla(tester, LogicalKeyboardKey.arrowDown);
    expect(enfocado(), 'c1');
  });

  testWidgets('↓ al final del contenido llega al mini reproductor y ↑ vuelve', (
    tester,
  ) async {
    await montar(tester);
    nodes['c3']!.requestFocus();
    await tester.pumpAndSettle();

    await tecla(tester, LogicalKeyboardKey.arrowDown);
    expect(enfocado(), 'pausa');
    await tecla(tester, LogicalKeyboardKey.arrowRight);
    expect(enfocado(), 'cerrar', reason: 'el botón de cerrar es alcanzable');

    await tecla(tester, LogicalKeyboardKey.arrowUp);
    expect(enfocado(), 'c3');
  });

  testWidgets(
    '→ desde el menú sin foco previo no entra en una sección oculta',
    (tester) async {
      await montar(tester);
      nodes['menu1']!.requestFocus();
      await tester.pumpAndSettle();

      await tecla(tester, LogicalKeyboardKey.arrowRight);
      expect(enfocado(), 'c1');
    },
  );
}
