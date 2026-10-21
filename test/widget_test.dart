import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qvatube_apk/core/config/app_config.dart';
import 'package:qvatube_apk/core/network/api_client.dart';
import 'package:qvatube_apk/core/network/api_providers.dart';
import 'package:qvatube_apk/core/storage/app_preferences.dart';
import 'package:qvatube_apk/main.dart';

Future<void> _pumpApp(WidgetTester tester, {bool introSeen = true}) async {
  SharedPreferences.setMockInitialValues(
    introSeen ? {AppConfig.introSeenKey: true} : <String, Object>{},
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider
            .overrideWithValue(await SharedPreferences.getInstance()),
        // En los tests no hay red: el cliente lanza el error controlado.
        apiClientProvider.overrideWithValue(
          ApiClient(remoteCallsEnabled: false),
        ),
      ],
      child: const QvaTubeApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('muestra la pantalla de introducción la primera vez',
      (WidgetTester tester) async {
    await _pumpApp(tester, introSeen: false);

    expect(find.text('Comenzar'), findsOneWidget);
    expect(find.textContaining('Streaming cubano'), findsWidgets);
  });

  testWidgets('muestra el login si la introducción ya fue vista',
      (WidgetTester tester) async {
    await _pumpApp(tester);

    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Explorar como invitado'), findsOneWidget);
  });

  testWidgets('el invitado entra al home con barra inferior de 9 secciones',
      (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.ensureVisible(find.text('Explorar como invitado'));
    await tester.pump();
    await tester.tap(find.text('Explorar como invitado'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // La barra inferior tiene 2 vistas a cada lado del Inicio y muestra
    // únicamente iconos (sin etiquetas de texto).
    expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
    expect(find.byIcon(Icons.live_tv), findsOneWidget);
    // La pestaña central está activa, por lo que muestra el icono relleno.
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    expect(find.byIcon(Icons.tv), findsOneWidget);

    // Contenido de la pestaña de Inicio.
    expect(find.text('Sugerir contenido'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Cómo funciona'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Cómo funciona'), findsOneWidget);
  });

  testWidgets('el avatar abre el menú de cuenta', (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.ensureVisible(find.text('Explorar como invitado'));
    await tester.pump();
    await tester.tap(find.text('Explorar como invitado'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('user-avatar')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Mi perfil'), findsOneWidget);
    expect(find.text('Cerrar sesión'), findsOneWidget);
  });
}
