// Herramienta para aplicar un tema (temporada) a los assets de la app.
//
//   dart run tool/apply_theme.dart               -> aplica el tema "active"
//   dart run tool/apply_theme.dart halloween     -> aplica un tema concreto
//   dart run tool/apply_theme.dart --list        -> lista los temas
//   dart run tool/apply_theme.dart halloween --sync-logo
//                                                 -> además copia el logo a
//                                                    assets/ (README, web...)
//   dart run tool/apply_theme.dart halloween --sync-pubspec
//                                                 -> declara la carpeta del
//                                                    tema en pubspec.yaml
//                                                    (Flutter no empaqueta
//                                                    subcarpetas)
//
// Qué hace:
//  1. Copia los iconos del tema a android/app/src/main/res/mipmap-*/
//     (el icono del launcher es nativo de Android, no se puede cambiar en
//      runtime, por eso se regenera aquí).
//  2. Con --sync-logo copia el logo y el favicon del tema a assets/ para que
//     el README, la web y el backend usen la imagen de la temporada activa.
//
// Los assets que usa la app en pantalla se resuelven en runtime desde
// assets/theme.json (ver lib/core/theme/app_assets.dart).

import 'dart:convert';
import 'dart:io';

const String manifestPath = 'assets/theme.json';

Future<void> main(List<String> args) async {
  final wantsList = args.contains('--list');
  final syncLogo = args.contains('--sync-logo');
  final syncPubspec = args.contains('--sync-pubspec');
  final themeArg = args.where((a) => !a.startsWith('--')).toList();

  final manifestFile = File(manifestPath);
  if (!manifestFile.existsSync()) {
    stderr.writeln('No se encontró $manifestPath');
    exit(1);
  }

  final manifest = jsonDecode(manifestFile.readAsStringSync())
      as Map<String, dynamic>;
  final themes = (manifest['themes'] as Map?)?.cast<String, dynamic>() ?? {};

  if (wantsList) {
    stdout.writeln('Temas disponibles en $manifestPath:');
    themes.forEach((id, value) {
      final label = (value as Map)['label']?.toString() ?? id;
      final path = value['path']?.toString() ?? '';
      final active = manifest['active']?.toString() == id;
      stdout.writeln('  ${active ? '*' : ' '} $id  ($label)  ->  $path');
    });
    return;
  }

  final themeId = themeArg.isNotEmpty ? themeArg.first : manifest['active']?.toString();
  final theme = themes[themeId];
  if (theme == null) {
    stderr.writeln('Tema desconocido: $themeId');
    stderr.writeln('Usa --list para ver los disponibles.');
    exit(1);
  }

  final themeMap = theme as Map<String, dynamic>;
  final basePath = themeMap['path']?.toString() ?? 'assets';
  final assets = (themeMap['assets'] as Map?)?.cast<String, dynamic>() ?? {};
  final icons = (assets['icons'] as Map?)?.cast<String, dynamic>() ?? {};

  stdout.writeln('Aplicando el tema "$themeId" (${themeMap['label']})');

  // 1) Icono del launcher de Android.
  //    Los iconos de la temporada viven en <path>/icons/.
  final iconPaths = <String, String>{};
  icons.forEach((size, file) {
    iconPaths[file.toString()] = '$basePath/icons/$file';
  });

  final launcher = (manifest['androidLauncher'] as Map?)?.cast<String, dynamic>() ?? {};
  launcher.forEach((density, file) {
    final source = File(iconPaths[file.toString()] ?? '$basePath/$file');
    final target = File(
      'android/app/src/main/res/$density/ic_launcher.png',
    );
    if (!source.existsSync()) {
      stderr.writeln('  ! no existe ${source.path}');
      return;
    }
    target.parent.createSync(recursive: true);
    source.copySync(target.path);
    stdout.writeln('  -> ${target.path}');
  });

  // 2) (Opcional) Logo y favicon "canónicos" en assets/.
  if (syncLogo) {
    for (final slot in ['logo', 'logoWebp', 'favicon', 'faviconIco']) {
      final file = assets[slot]?.toString();
      if (file == null) continue;
      final source = File('$basePath/$file');
      if (!source.existsSync()) continue;
      final target = File('assets/$file');
      source.copySync(target.path);
      stdout.writeln('  -> ${target.path}');
    }
  }

  // 3) Declara la carpeta del tema en pubspec.yaml (Flutter solo empaqueta
  //    el contenido de las carpetas declaradas, no sus subcarpetas).
  if (syncPubspec) {
    final pubspec = File('pubspec.yaml');
    final entry = '    - $basePath/';
    var content = pubspec.readAsStringSync();
    if (!content.contains(entry)) {
      content = content.replaceAll('    - assets/themes/', entry);
      if (!content.contains(entry)) {
        content = content.replaceAll(
          '  assets:\n',
          '  assets:\n$entry\n',
        );
      }
      pubspec.writeAsStringSync(content);
      stdout.writeln('  -> pubspec.yaml ($entry)');
    } else {
      stdout.writeln('  -> pubspec.yaml ya declara $entry');
    }
  }

  // 4) Deja el manifiesto apuntando al tema aplicado.
  manifest['active'] = themeId;
  manifestFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );
  stdout.writeln('Manifiesto actualizado: active = $themeId');
  stdout.writeln(
    'Recuerda reconstruir: flutter run  (oflutter build apk --release)',
  );
}
