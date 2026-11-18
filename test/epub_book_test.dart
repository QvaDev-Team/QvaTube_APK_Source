import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qvatube_apk/features/reader/epub_book.dart';
import 'package:qvatube_apk/features/reader/epub_chapter_view.dart';

void main() {
  final bytes = File('test/fixtures/epub/sample.epub').readAsBytesSync();

  test('lee título, capítulos e índice del EPUB', () {
    final book = EpubBook.parse(bytes);
    expect(book.title, 'Libro de prueba');
    expect(book.chapters.map((c) => c.path), [
      'OEBPS/text/cap 1.xhtml',
      'OEBPS/text/cap2.xhtml',
    ]);
    expect(book.chapters.first.title, 'Uno');
    expect(book.toc.map((e) => (e.label, e.chapterIndex, e.anchor, e.depth)), [
      ('Uno', 0, null, 0),
      ('Sección', 0, 'sec', 1),
      ('Dos', 1, null, 0),
    ]);
    expect(book.readBytes('OEBPS/images/a.png'), isNotNull);
  });

  test('se puede abrir en otro isolate (compute) y leer después', () async {
    final book = await compute(EpubBook.parse, bytes);
    expect(book.readText(book.chapters.last.path), contains('Fin.'));
  });

  test('rechaza un archivo que no es EPUB', () {
    expect(
      () => EpubBook.parse(
        File('test/fixtures/bspatch/new.bin').readAsBytesSync(),
      ),
      throwsA(isA<EpubException>()),
    );
  });

  testWidgets('muestra el capítulo con texto e imágenes', (tester) async {
    final book = EpubBook.parse(bytes);
    final anchors = <String, GlobalKey>{};
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: EpubChapterView(
            book: book,
            chapterPath: book.chapters.first.path,
            fontSize: 18,
            palette: const ReaderPalette(
              background: Colors.black,
              text: Colors.white,
              muted: Colors.grey,
              link: Colors.orange,
            ),
            anchorKeys: anchors,
          ),
        ),
      ),
    );
    expect(find.text('Capítulo uno'), findsOneWidget);
    expect(
      find.textContaining('Hola mundo y más.', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Segunda\nlínea', findRichText: true),
      findsOneWidget,
    );
    expect(find.byType(Image), findsOneWidget);
    expect(anchors.containsKey('sec'), isTrue);
  });
}
