import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/platform/device_channel.dart';

/// Binario de TDLib (librería oficial de Telegram) para una arquitectura.
@immutable
class TdBinary {
  const TdBinary({
    required this.abi,
    required this.url,
    required this.gzSha256,
    required this.soSha256,
    required this.gzBytes,
    this.ext = 'so',
  });

  final String abi;

  /// Extensión de la librería: `so` (Android, Linux) o `dll` (Windows).
  final String ext;
  final String url;

  /// SHA-256 del `.so.gz` descargado (descarta descargas incompletas).
  final String gzSha256;

  /// SHA-256 del `.so` ya descomprimido (lo que se carga en memoria).
  final String soSha256;
  final int gzBytes;
}

/// TDLib se descarga **bajo demanda** (solo quien conecta Telegram) en vez de
/// ir dentro del APK: sin comprimir son ~53 MB y la app pesa ~41 MB.
///
/// Se publica en la release `tdlib-1.8.65` del repo público y siempre se
/// comprueba su SHA-256 antes de cargarla: un archivo cambiado o a medias
/// nunca llega a ejecutarse.
abstract final class TdLibrary {
  const TdLibrary._();

  static const String version = '1.8.65';
  static const String _base =
      'https://github.com/QvaDev-Team/QvaTube_APK/releases/download/tdlib-$version';

  static const Map<Abi, TdBinary> binaries = {
    Abi.androidArm64: TdBinary(
      abi: 'arm64-v8a',
      url: '$_base/libtdjson-arm64-v8a.so.gz',
      gzSha256:
          '541d2146f7731a3a7871f50cea15cfbadf8dd2f245972bd64f90b0f847620bb2',
      soSha256:
          '1ddfd787422d81247a1e64160f92dbe8c8cd62b67822e620162e54ce114b9eb9',
      gzBytes: 10453758,
    ),
    Abi.androidArm: TdBinary(
      abi: 'armeabi-v7a',
      url: '$_base/libtdjson-armeabi-v7a.so.gz',
      gzSha256:
          'cb5334e64eb8c5f74378029de97566088c7666c45aa76022b295d6108c67a2f7',
      soSha256:
          'bf154402a5e29768571349c044a9976256bf7a18fb740f1e9cfb92f7905e359c',
      gzBytes: 9776825,
    ),
    // Escritorio: compilados en el CI (.github/workflows/tdlib-escritorio.yml)
    // desde tdlib/td a8f21f52 (1.8.65).
    Abi.linuxX64: TdBinary(
      abi: 'linux-x64',
      url: '$_base/libtdjson-linux-x64.so.gz',
      gzSha256:
          '01fb56f21ab60828bac5c5e951f858b6064854362379b088712ce5991c26ebc4',
      soSha256:
          '4f055018876f4f15dabe85429884f9b53a2fc9e6603275f8aebfca1dce51b46e',
      gzBytes: 14817708,
    ),
    Abi.windowsX64: TdBinary(
      abi: 'windows-x64',
      url: '$_base/tdjson-windows-x64.dll.gz',
      gzSha256:
          '2f2ec374b051cdd8f44c6d8059a292153b3f4777f6a3dc89a4cb7c214a79d81c',
      soSha256:
          '3993afd34f5aec721eaf62d04baefa9e860481df637fed4af0809f6dc9106b8e',
      gzBytes: 12081465,
      ext: 'dll',
    ),
  };

  /// Binario para este equipo, o `null` si la arquitectura no está
  /// soportada (emuladores x86, macOS, Linux/Windows ARM).
  static TdBinary? get current => binaries[Abi.current()];

  static bool get isSupported => current != null;

  static Future<Directory> _dir() async {
    final dir = Directory('${await DeviceChannel.cacheDirectory()}/tdlib');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _soFile(TdBinary bin) async =>
      File('${(await _dir()).path}/libtdjson-${bin.abi}-$version.${bin.ext}');

  /// `true` si la librería ya está descargada y verificada.
  static Future<bool> isInstalled() async {
    final bin = current;
    if (bin == null) return false;
    final so = await _soFile(bin);
    if (!await so.exists()) return false;
    return await compute(_sha256File, so.path) == bin.soSha256;
  }

  /// Descarga, verifica y descomprime la librería si hace falta. Devuelve la
  /// ruta del `.so` listo para cargar. [onProgress] recibe de 0 a 1.
  static Future<String> install({
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final bin = current;
    if (bin == null) {
      throw UnsupportedError(
        'Telegram en la app no está disponible en este dispositivo.',
      );
    }
    final so = await _soFile(bin);
    if (await so.exists() &&
        await compute(_sha256File, so.path) == bin.soSha256) {
      onProgress?.call(1);
      return so.path;
    }

    final dir = await _dir();
    final gz = File('${dir.path}/libtdjson-${bin.abi}.${bin.ext}.gz.part');
    await Dio().download(
      bin.url,
      gz.path,
      cancelToken: cancelToken,
      onReceiveProgress: (received, total) {
        final t = total > 0 ? total : bin.gzBytes;
        onProgress?.call((received / t).clamp(0, 0.99));
      },
    );
    if (await compute(_sha256File, gz.path) != bin.gzSha256) {
      await gz.delete();
      throw StateError(
        'La descarga de Telegram llegó incompleta. Inténtalo de nuevo.',
      );
    }
    final tmp = File('${so.path}.part');
    await compute(_gunzip, [gz.path, tmp.path]);
    await gz.delete();
    if (await compute(_sha256File, tmp.path) != bin.soSha256) {
      await tmp.delete();
      throw StateError('El componente de Telegram no es válido.');
    }
    await tmp.rename(so.path);
    // Borra versiones anteriores de la librería.
    await for (final f in dir.list()) {
      if (f is File &&
          f.path.contains('libtdjson') &&
          f.path.endsWith('.${bin.ext}') &&
          f.path != so.path) {
        await f.delete();
      }
    }
    onProgress?.call(1);
    return so.path;
  }

  /// Borra la librería descargada (al desconectar Telegram, si se quiere
  /// liberar espacio).
  static Future<void> uninstall() async {
    final dir = await _dir();
    await for (final f in dir.list()) {
      if (f is File && f.path.contains('libtdjson')) await f.delete();
    }
  }
}

String _sha256File(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

void _gunzip(List<String> paths) {
  final bytes = gzip.decode(File(paths[0]).readAsBytesSync());
  File(paths[1]).writeAsBytesSync(bytes, flush: true);
}
