import 'package:flutter_test/flutter_test.dart';
import 'package:qvatube_apk/core/update/app_update_service.dart';

void main() {
  test('lee sha256 y parches diferenciales de latest.json', () {
    final info = AppUpdateInfo.fromJson({
      'version_code': 40,
      'version_name': '1.1.0',
      'url': 'https://example.com/qvatube.apk',
      'size_mb': 25.8,
      'sha256': 'ABCDEF',
      'patches': [
        {
          'from_version_code': 31,
          'from_sha256': '81D7A9',
          'size_bytes': 3820873,
          'sha256': 'c43907',
          'url': 'https://example.com/qvatube-31-to-40.bsdiff',
        },
        // Entradas incompletas se descartan.
        {'from_version_code': 30},
      ],
    });

    expect(info.sha256, 'abcdef');
    expect(info.patches, hasLength(1));
    expect(info.patches.single.fromSha256, '81d7a9');
    expect(info.patches.single.sizeMb, 3.6);
    // Sin parche aplicable se descarga el APK completo.
    expect(info.downloadSizeMb, 25.8);
    expect(
      info.copyWith(applicablePatch: info.patches.single).downloadSizeMb,
      3.6,
    );
  });

  test('un manifiesto viejo sin parches sigue funcionando', () {
    final info = AppUpdateInfo.fromJson({
      'version_code': 31,
      'url': 'https://example.com/qvatube.apk',
    });
    expect(info.patches, isEmpty);
    expect(info.sha256, isNull);
  });
}
