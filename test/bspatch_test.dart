import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qvatube_apk/core/update/bspatch.dart';

/// Los fixtures se generaron con `bsdiff4.diff(old, new)` (Python), que
/// produce el mismo formato BSDIFF40 que el `bsdiff` de Ubuntu usado en CI.
void main() {
  Uint8List fixture(String name) =>
      File('test/fixtures/bspatch/$name').readAsBytesSync();

  test('reconstruye el archivo nuevo byte a byte', () {
    final result = bspatch(fixture('old.bin'), fixture('old_to_new.bsdiff'));
    expect(result, equals(fixture('new.bin')));
  });

  test('rechaza un archivo que no es un parche BSDIFF40', () {
    expect(
      () => bspatch(fixture('old.bin'), fixture('new.bin')),
      throwsA(isA<BsPatchException>()),
    );
  });

  test('rechaza un parche truncado', () {
    final patch = fixture('old_to_new.bsdiff');
    expect(
      () => bspatch(fixture('old.bin'), Uint8List.sublistView(patch, 0, 40)),
      throwsA(isA<BsPatchException>()),
    );
  });
}
