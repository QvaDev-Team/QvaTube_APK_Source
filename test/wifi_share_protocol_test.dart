import 'package:flutter_test/flutter_test.dart';
import 'package:qvatube_apk/features/share/wifi_share_protocol.dart';

void main() {
  test('ShareQrPayload codifica y decodifica múltiples IPs y tildes', () {
    const original = ShareQrPayload(
      hosts: ['192.168.43.1', '192.168.1.25'],
      port: 41234,
      pin: '4821',
      name: 'Teléfono de José',
    );
    final raw = original.toUriString();
    expect(raw, startsWith('qvatube://share?'));

    final parsed = ShareQrPayload.tryParse(raw);
    expect(parsed, isNotNull);
    expect(parsed!.hosts, ['192.168.43.1', '192.168.1.25']);
    expect(parsed.port, 41234);
    expect(parsed.pin, '4821');
    expect(parsed.name, 'Teléfono de José');
  });

  test('ShareQrPayload rechaza QRs ajenos o incompletos', () {
    expect(ShareQrPayload.tryParse('https://qvatube.net'), isNull);
    expect(
      ShareQrPayload.tryParse('qvatube://other?h=1.2.3.4&p=80&k=1234'),
      isNull,
    );
    expect(ShareQrPayload.tryParse('qvatube://share?h=&p=80&k=1234'), isNull);
    expect(
      ShareQrPayload.tryParse('qvatube://share?h=1.2.3.4&p=0&k=1234'),
      isNull,
    );
    expect(
      ShareQrPayload.tryParse('qvatube://share?h=1.2.3.4&p=80&k='),
      isNull,
    );
  });

  test('ShareQrPayload usa la primera IP si el nombre viene vacío', () {
    final parsed = ShareQrPayload.tryParse(
      'qvatube://share?h=192.168.43.1&p=40000&k=9999',
    );
    expect(parsed, isNotNull);
    expect(parsed!.name, '192.168.43.1');
  });
}
