import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:qvatube_apk/features/share/received_store.dart';
import 'package:qvatube_apk/features/share/wifi_share_client.dart';
import 'package:qvatube_apk/features/share/wifi_share_protocol.dart';
import 'package:qvatube_apk/features/share/wifi_share_server.dart';
import 'package:qvatube_apk/features/telegram/telegram_files.dart';

// Compartir por Wi-Fi de punta a punta en la misma máquina (es lo que hace
// la versión de escritorio): servidor con PIN, lista, archivo y reanudación.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter test simula las conexiones HTTP: aquí se usa red de verdad.
  setUpAll(() => HttpOverrides.global = null);

  test('enviar y recibir un archivo con PIN', () async {
    final dir = await Directory.systemTemp.createTemp('qvashare_test');
    final src = File('${dir.path}/pelicula.mp4');
    final bytes = List<int>.generate(3 * 1024 * 1024 + 123, (i) => i % 251);
    await src.writeAsBytes(bytes);

    final file =
        TgFile(
            messageId: 1,
            fileId: 1,
            name: 'Pelicula de prueba ${Random().nextInt(1 << 30)}.mp4',
            kind: TgFileKind.video,
            date: DateTime(2026),
          )
          ..size = bytes.length
          ..completed = true
          ..localPath = src.path;

    final server = WifiShareServer(deviceName: 'PC de prueba');
    await server.start([file]);
    addTearDown(server.stop);
    expect(server.running, isTrue);
    expect(server.pin, hasLength(4));

    final client = WifiShareClient();
    // PIN incorrecto → no deja ver nada.
    await expectLater(
      client.manifest('127.0.0.1', server.port, '0000'),
      throwsA(isA<ShareAuthException>()),
    );

    final m = await client.manifest('127.0.0.1', server.port, server.pin);
    expect(m.name, 'PC de prueba');
    expect(m.items.single.size, bytes.length);

    await client.receive('127.0.0.1', server.port, server.pin, m.items);
    expect(client.failed, isEmpty);
    expect(client.done, contains(m.items.single.id));

    final recibido = ReceivedStore.instance.files.firstWhere(
      (r) => r.item.name == file.name,
    );
    expect(await File(recibido.path).readAsBytes(), bytes);
    expect(ReceivedStore.instance.has(m.items.single), isTrue);

    // Limpieza: lo recibido sale del gestor y del disco.
    await ReceivedStore.instance.delete(
      ReceivedStore.instance.asTgFiles.firstWhere(
        (f) => f.localPath == recibido.path,
      ),
    );
    expect(await File(recibido.path).exists(), isFalse);
    await dir.delete(recursive: true);
    client.dispose();
  });

  test('el QR lleva la red del punto de acceso', () {
    const p = ShareQrPayload(
      hosts: ['192.168.43.1'],
      port: 40123,
      pin: '4821',
      name: 'Roger',
      ssid: 'AndroidShare_1234',
      password: 'clave secreta',
    );
    final back = ShareQrPayload.tryParse(p.toUriString())!;
    expect(back.ssid, 'AndroidShare_1234');
    expect(back.password, 'clave secreta');
    expect(back.hosts, ['192.168.43.1']);
    expect(ShareQrPayload.tryParse('https://otra.cosa'), isNull);
  });
}
