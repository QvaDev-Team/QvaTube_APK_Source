import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Error al aplicar un parche binario (formato inválido o corrupto).
class BsPatchException implements Exception {
  const BsPatchException(this.message);

  final String message;

  @override
  String toString() => 'BsPatchException: $message';
}

/// Implementación de `bspatch` para parches `BSDIFF40` (el formato clásico de
/// Colin Percival, el que generan `bsdiff` de Debian/Ubuntu y `bsdiff4` de
/// Python).
///
/// Estructura del parche:
///
/// | Offset | Tamaño | Contenido                                  |
/// | ------ | ------ | ------------------------------------------ |
/// | 0      | 8      | `BSDIFF40`                                 |
/// | 8      | 8      | longitud X del bloque de control (bzip2)   |
/// | 16     | 8      | longitud Y del bloque de diferencias (bz2) |
/// | 24     | 8      | tamaño del archivo nuevo                   |
/// | 32     | X      | control: tripletas (add, copy, seek)       |
/// | 32+X   | Y      | diferencias (se suman byte a byte al viejo)|
/// | 32+X+Y | resto  | extra (bytes nuevos que se copian tal cual)|
///
/// Es código puro de Dart para poder ejecutarlo en un `Isolate` y probarlo
/// con `flutter test` sin depender de librerías nativas.
Uint8List bspatch(Uint8List oldBytes, Uint8List patch) {
  if (patch.length < 32) {
    throw const BsPatchException('Parche demasiado corto');
  }
  const magic = 'BSDIFF40';
  for (var i = 0; i < magic.length; i++) {
    if (patch[i] != magic.codeUnitAt(i)) {
      throw const BsPatchException('Cabecera BSDIFF40 inválida');
    }
  }

  final ctrlLen = _offtin(patch, 8);
  final diffLen = _offtin(patch, 16);
  final newSize = _offtin(patch, 24);
  if (ctrlLen < 0 ||
      diffLen < 0 ||
      newSize < 0 ||
      32 + ctrlLen + diffLen > patch.length) {
    throw const BsPatchException('Cabecera con longitudes corruptas');
  }

  final decoder = BZip2Decoder();
  Uint8List block(int start, int end) {
    try {
      return decoder.decodeBytes(Uint8List.sublistView(patch, start, end));
    } catch (_) {
      throw const BsPatchException('Bloque bzip2 corrupto');
    }
  }

  final ctrl = block(32, 32 + ctrlLen);
  final diff = block(32 + ctrlLen, 32 + ctrlLen + diffLen);
  final extra = block(32 + ctrlLen + diffLen, patch.length);

  final out = Uint8List(newSize);
  final oldSize = oldBytes.length;
  var newPos = 0;
  var oldPos = 0;
  var ctrlPos = 0;
  var diffPos = 0;
  var extraPos = 0;

  while (newPos < newSize) {
    if (ctrlPos + 24 > ctrl.length) {
      throw const BsPatchException('Bloque de control truncado');
    }
    final addLen = _offtin(ctrl, ctrlPos);
    final copyLen = _offtin(ctrl, ctrlPos + 8);
    final seek = _offtin(ctrl, ctrlPos + 16);
    ctrlPos += 24;

    if (addLen < 0 ||
        newPos + addLen > newSize ||
        diffPos + addLen > diff.length) {
      throw const BsPatchException('Instrucción de suma fuera de rango');
    }
    for (var i = 0; i < addLen; i++) {
      final o = oldPos + i;
      final base = (o >= 0 && o < oldSize) ? oldBytes[o] : 0;
      out[newPos + i] = (diff[diffPos + i] + base) & 0xFF;
    }
    diffPos += addLen;
    newPos += addLen;
    oldPos += addLen;

    if (copyLen < 0 ||
        newPos + copyLen > newSize ||
        extraPos + copyLen > extra.length) {
      throw const BsPatchException('Instrucción de copia fuera de rango');
    }
    out.setRange(newPos, newPos + copyLen, extra, extraPos);
    extraPos += copyLen;
    newPos += copyLen;
    oldPos += seek;
  }

  return out;
}

/// Entero de 64 bits en signo-magnitud little-endian (formato de bsdiff).
int _offtin(Uint8List buf, int offset) {
  var y = buf[offset + 7] & 0x7F;
  for (var i = 6; i >= 0; i--) {
    y = (y << 8) | buf[offset + i];
  }
  return (buf[offset + 7] & 0x80) != 0 ? -y : y;
}
