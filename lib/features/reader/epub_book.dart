import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Error al abrir un EPUB dañado o con una estructura que no se entiende.
class EpubException implements Exception {
  const EpubException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Capítulo del orden de lectura (spine) del EPUB.
class EpubChapter {
  const EpubChapter({required this.path, required this.title});

  /// Ruta del XHTML dentro del zip.
  final String path;
  final String title;
}

/// Entrada del índice (TOC).
class EpubTocEntry {
  const EpubTocEntry({
    required this.label,
    required this.chapterIndex,
    this.anchor,
    this.depth = 0,
  });

  final String label;
  final int chapterIndex;
  final String? anchor;
  final int depth;
}

/// EPUB abierto en memoria: el zip, el orden de lectura y el índice.
/// Igual que el lector de la web (reader.js), sin librerías de terceros
/// más allá de descomprimir el zip y leer el XML del paquete.
class EpubBook {
  EpubBook._(this._files, this.title, this.chapters, this.toc);

  final Map<String, ArchiveFile> _files;
  final String? title;
  final List<EpubChapter> chapters;
  final List<EpubTocEntry> toc;

  static EpubBook parse(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const EpubException('El archivo no es un EPUB válido.');
    }
    final files = <String, ArchiveFile>{
      for (final f in archive.files)
        if (f.isFile) f.name: f,
    };

    String readText(String path) {
      final file = files[path];
      if (file == null) throw EpubException('Falta $path en el libro.');
      return utf8.decode(file.content as List<int>, allowMalformed: true);
    }

    // 1) container.xml → ruta del paquete OPF.
    final container = XmlDocument.parse(readText('META-INF/container.xml'));
    final opfPath = container
        .findAllElements('rootfile')
        .map((e) => e.getAttribute('full-path'))
        .whereType<String>()
        .firstOrNull;
    if (opfPath == null) {
      throw const EpubException('El libro no tiene paquete OPF.');
    }
    final opfDir = dirOf(opfPath);
    final opf = XmlDocument.parse(readText(opfPath));

    final title = opf
        .findAllElements('title', namespaceUri: '*')
        .map((e) => e.innerText.trim())
        .where((t) => t.isNotEmpty)
        .firstOrNull;

    // 2) manifest (id → ruta) y spine (orden de lectura).
    final manifest = <String, ({String path, String type, String props})>{};
    for (final item in opf.findAllElements('item', namespaceUri: '*')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = (
        path: resolvePath(opfDir, Uri.decodeFull(href)),
        type: item.getAttribute('media-type') ?? '',
        props: item.getAttribute('properties') ?? '',
      );
    }

    final spinePaths = <String>[];
    final spineEl = opf.findAllElements('spine', namespaceUri: '*').firstOrNull;
    for (final ref in opf.findAllElements('itemref', namespaceUri: '*')) {
      final entry = manifest[ref.getAttribute('idref')];
      if (entry != null && files.containsKey(entry.path)) {
        spinePaths.add(entry.path);
      }
    }
    if (spinePaths.isEmpty) {
      throw const EpubException('El libro no tiene capítulos.');
    }
    final chapterIndex = {
      for (var i = 0; i < spinePaths.length; i++) spinePaths[i]: i,
    };

    // 3) Índice: nav de EPUB 3 o toc.ncx de EPUB 2.
    final toc = <EpubTocEntry>[];
    void addEntry(String label, String href, String baseDir, int depth) {
      final parts = Uri.decodeFull(href).split('#');
      final idx = chapterIndex[resolvePath(baseDir, parts.first)];
      final clean = label.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (idx == null || clean.isEmpty) return;
      toc.add(
        EpubTocEntry(
          label: clean,
          chapterIndex: idx,
          anchor: parts.length > 1 ? parts[1] : null,
          depth: depth,
        ),
      );
    }

    final nav = manifest.values
        .where((m) => m.props.split(' ').contains('nav'))
        .firstOrNull;
    final ncxId = spineEl?.getAttribute('toc');
    final ncx =
        manifest[ncxId] ??
        manifest.values
            .where((m) => m.type == 'application/x-dtbncx+xml')
            .firstOrNull;
    try {
      if (nav != null && files.containsKey(nav.path)) {
        final doc = XmlDocument.parse(readText(nav.path));
        final tocNav = doc
            .findAllElements('nav', namespaceUri: '*')
            .where(
              (n) =>
                  (n.getAttribute('epub:type') ??
                      n.getAttribute('type', namespaceUri: '*') ??
                      '') ==
                  'toc',
            );
        final root =
            tocNav.firstOrNull ??
            doc.findAllElements('nav', namespaceUri: '*').firstOrNull;
        if (root != null) {
          for (final a in root.findAllElements('a', namespaceUri: '*')) {
            final href = a.getAttribute('href');
            if (href == null) continue;
            final depth =
                a.ancestors
                    .whereType<XmlElement>()
                    .where((e) => e.localName == 'ol')
                    .length -
                1;
            addEntry(a.innerText, href, dirOf(nav.path), depth.clamp(0, 4));
          }
        }
      }
      if (toc.isEmpty && ncx != null && files.containsKey(ncx.path)) {
        final doc = XmlDocument.parse(readText(ncx.path));
        for (final point in doc.findAllElements(
          'navPoint',
          namespaceUri: '*',
        )) {
          final label =
              point
                  .findElements('navLabel', namespaceUri: '*')
                  .firstOrNull
                  ?.innerText ??
              '';
          final src = point
              .findElements('content', namespaceUri: '*')
              .firstOrNull
              ?.getAttribute('src');
          if (src == null) continue;
          final depth = point.ancestors
              .whereType<XmlElement>()
              .where((e) => e.localName == 'navPoint')
              .length;
          addEntry(label, src, dirOf(ncx.path), depth.clamp(0, 4));
        }
      }
    } catch (_) {
      // Un índice roto no impide leer: se sigue sin él.
    }

    final titles = <int, String>{};
    for (final e in toc) {
      titles.putIfAbsent(e.chapterIndex, () => e.label);
    }
    final chapters = [
      for (var i = 0; i < spinePaths.length; i++)
        EpubChapter(
          path: spinePaths[i],
          title: titles[i] ?? 'Capítulo ${i + 1}',
        ),
    ];

    return EpubBook._(files, title, chapters, toc);
  }

  String? readText(String path) {
    final file = _files[path];
    if (file == null) return null;
    return utf8.decode(file.content as List<int>, allowMalformed: true);
  }

  Uint8List? readBytes(String path) {
    final file = _files[path];
    if (file == null) return null;
    return file.content;
  }

  static String dirOf(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  /// Resuelve [href] (relativo, con `..`) respecto a la carpeta [baseDir].
  static String resolvePath(String baseDir, String href) {
    if (href.startsWith('/')) href = href.substring(1);
    final parts = <String>[
      if (baseDir.isNotEmpty) ...baseDir.split('/'),
      ...href.split('/'),
    ];
    final out = <String>[];
    for (final p in parts) {
      if (p.isEmpty || p == '.') continue;
      if (p == '..') {
        if (out.isNotEmpty) out.removeLast();
      } else {
        out.add(p);
      }
    }
    return out.join('/');
  }
}
