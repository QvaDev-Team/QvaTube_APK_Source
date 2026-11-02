import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'epub_book.dart';

/// Colores del lector (oscuro, sepia o claro, como en la web).
class ReaderPalette {
  const ReaderPalette({
    required this.background,
    required this.text,
    required this.muted,
    required this.link,
  });

  final Color background;
  final Color text;
  final Color muted;
  final Color link;
}

enum _BlockKind { paragraph, heading, quote, listItem, pre }

/// Muestra un capítulo XHTML con el tema de QvaTube: se ignoran los estilos y
/// scripts del libro y se convierten párrafos, títulos, citas, listas e
/// imágenes en widgets nativos (no hace falta un WebView).
class EpubChapterView extends StatelessWidget {
  const EpubChapterView({
    super.key,
    required this.book,
    required this.chapterPath,
    required this.fontSize,
    required this.palette,
    this.anchorKeys,
  });

  final EpubBook book;
  final String chapterPath;
  final double fontSize;
  final ReaderPalette palette;

  /// Si se da, recibe una `GlobalKey` por cada `id` del capítulo, para poder
  /// saltar a un ancla del índice.
  final Map<String, GlobalKey>? anchorKeys;

  @override
  Widget build(BuildContext context) {
    final text = book.readText(chapterPath);
    if (text == null) {
      return Text(
        'No se pudo leer este capítulo.',
        style: TextStyle(color: palette.muted),
      );
    }
    final doc = html_parser.parse(text);
    final body = doc.body ?? doc.documentElement;
    if (body == null) return const SizedBox.shrink();

    final builder = _ChapterBuilder(
      book: book,
      baseDir: EpubBook.dirOf(chapterPath),
      fontSize: fontSize,
      palette: palette,
      anchorKeys: anchorKeys,
    )..visit(body);
    builder.flush();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: builder.widgets,
    );
  }
}

class _InlineStyle {
  const _InlineStyle({
    this.italic = false,
    this.bold = false,
    this.link = false,
    this.small = false,
    this.mono = false,
  });

  final bool italic;
  final bool bold;
  final bool link;
  final bool small;
  final bool mono;

  _InlineStyle copyWith({
    bool? italic,
    bool? bold,
    bool? link,
    bool? small,
    bool? mono,
  }) => _InlineStyle(
    italic: italic ?? this.italic,
    bold: bold ?? this.bold,
    link: link ?? this.link,
    small: small ?? this.small,
    mono: mono ?? this.mono,
  );
}

class _ChapterBuilder {
  _ChapterBuilder({
    required this.book,
    required this.baseDir,
    required this.fontSize,
    required this.palette,
    this.anchorKeys,
  });

  final EpubBook book;
  final String baseDir;
  final double fontSize;
  final ReaderPalette palette;
  final Map<String, GlobalKey>? anchorKeys;

  final widgets = <Widget>[];
  final _spans = <InlineSpan>[];
  _BlockKind _kind = _BlockKind.paragraph;
  int _headingLevel = 0;
  int _quoteDepth = 0;
  int _listDepth = 0;
  String? _pendingAnchor;

  static const _skip = {
    'script',
    'style',
    'head',
    'title',
    'meta',
    'link',
    'noscript',
  };
  static const _blocks = {
    'p',
    'div',
    'section',
    'article',
    'header',
    'footer',
    'aside',
    'nav',
    'main',
    'figure',
    'figcaption',
    'center',
    'table',
    'tr',
    'tbody',
    'thead',
    'dl',
    'dt',
    'dd',
    'body',
    'html',
    'address',
    'caption',
  };

  void visit(dom.Node node, [_InlineStyle style = const _InlineStyle()]) {
    if (node is dom.Text) {
      _addText(node.text, style);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName?.toLowerCase() ?? '';
    if (_skip.contains(tag)) return;

    final id = node.attributes['id'];
    if (id != null && anchorKeys != null) _pendingAnchor = id;

    switch (tag) {
      case 'br':
        _spans.add(const TextSpan(text: '\n'));
        return;
      case 'hr':
        flush();
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: palette.muted.withValues(alpha: 0.4)),
          ),
        );
        return;
      case 'img':
      case 'image':
        _addImage(node);
        return;
      case 'svg':
        // SVG en línea: casi siempre la portada con un <image> dentro.
        for (final img in node.querySelectorAll('image')) {
          _addImage(img);
        }
        return;
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        flush();
        _kind = _BlockKind.heading;
        _headingLevel = int.parse(tag.substring(1));
        _children(node, style.copyWith(bold: true));
        flush();
        return;
      case 'blockquote':
        flush();
        _quoteDepth++;
        _children(node, style);
        flush();
        _quoteDepth--;
        return;
      case 'ul':
      case 'ol':
        flush();
        _listDepth++;
        _children(node, style);
        flush();
        _listDepth--;
        return;
      case 'li':
        flush();
        _kind = _BlockKind.listItem;
        _children(node, style);
        flush();
        return;
      case 'pre':
        flush();
        _kind = _BlockKind.pre;
        _children(node, style.copyWith(mono: true));
        flush();
        return;
      case 'em':
      case 'i':
      case 'cite':
      case 'dfn':
        _children(node, style.copyWith(italic: true));
        return;
      case 'strong':
      case 'b':
        _children(node, style.copyWith(bold: true));
        return;
      case 'a':
        _children(node, style.copyWith(link: node.attributes['href'] != null));
        return;
      case 'sup':
      case 'sub':
      case 'small':
        _children(node, style.copyWith(small: true));
        return;
      case 'code':
      case 'kbd':
      case 'tt':
        _children(node, style.copyWith(mono: true));
        return;
    }

    if (_blocks.contains(tag) || tag == 'td' || tag == 'th') {
      flush();
      _children(node, tag == 'th' ? style.copyWith(bold: true) : style);
      flush();
      return;
    }
    _children(node, style);
  }

  void _children(dom.Element el, _InlineStyle style) {
    for (final child in el.nodes) {
      visit(child, style);
    }
  }

  void _addText(String raw, _InlineStyle style) {
    var text = _kind == _BlockKind.pre
        ? raw
        : raw.replaceAll(RegExp(r'\s+'), ' ');
    if (_spans.isEmpty && _kind != _BlockKind.pre) text = text.trimLeft();
    if (text.isEmpty) return;
    _spans.add(
      TextSpan(
        text: text,
        style: TextStyle(
          fontStyle: style.italic ? FontStyle.italic : null,
          fontWeight: style.bold ? FontWeight.w700 : null,
          color: style.link ? palette.link : null,
          decoration: style.link ? TextDecoration.underline : null,
          decorationColor: palette.link,
          fontSize: style.small ? fontSize * 0.72 : null,
          fontFamily: style.mono ? 'monospace' : null,
        ),
      ),
    );
  }

  void _addImage(dom.Element el) {
    final ref =
        el.attributes['src'] ??
        el.attributes['href'] ??
        el.attributes['xlink:href'];
    if (ref == null || ref.startsWith('data:')) return;
    final path = EpubBook.resolvePath(
      baseDir,
      Uri.decodeFull(ref.split('#').first),
    );
    final bytes = book.readBytes(path);
    if (bytes == null) return;
    flush();
    final isSvg = path.toLowerCase().endsWith('.svg');
    widgets.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: isSvg
              ? SvgPicture.memory(bytes, fit: BoxFit.contain)
              : Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
        ),
      ),
    );
  }

  /// Cierra el bloque en curso y lo convierte en un widget.
  void flush() {
    while (_spans.isNotEmpty &&
        _spans.last is TextSpan &&
        ((_spans.last as TextSpan).text ?? '').trim().isEmpty &&
        (_spans.last as TextSpan).text != '\n') {
      _spans.removeLast();
    }
    final hasText = _spans.any(
      (s) => s is TextSpan && (s.text ?? '').trim().isNotEmpty,
    );
    if (!hasText) {
      _spans.clear();
      _kind = _BlockKind.paragraph;
      return;
    }

    final base = TextStyle(
      color: palette.text,
      fontSize: fontSize,
      height: 1.6,
    );
    TextStyle style = base;
    TextAlign align = TextAlign.start;
    EdgeInsets padding = const EdgeInsets.only(bottom: 12);
    switch (_kind) {
      case _BlockKind.heading:
        const scale = [1.6, 1.4, 1.25, 1.12, 1.05, 1.0];
        style = base.copyWith(
          fontSize: fontSize * scale[(_headingLevel - 1).clamp(0, 5)],
          fontWeight: FontWeight.w700,
          height: 1.3,
        );
        align = _headingLevel <= 2 ? TextAlign.center : TextAlign.start;
        padding = const EdgeInsets.only(top: 12, bottom: 14);
      case _BlockKind.pre:
        style = base.copyWith(
          fontFamily: 'monospace',
          fontSize: fontSize * 0.85,
        );
      case _BlockKind.listItem:
      case _BlockKind.quote:
      case _BlockKind.paragraph:
        break;
    }

    Widget block = Text.rich(
      TextSpan(style: style, children: List.of(_spans)),
      textAlign: align,
    );
    if (_kind == _BlockKind.listItem) {
      block = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: base),
          Expanded(child: block),
        ],
      );
    }
    final indent = 18.0 * (_listDepth > 1 ? _listDepth - 1 : 0);
    if (_quoteDepth > 0) {
      block = Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: palette.muted.withValues(alpha: 0.5),
              width: 3,
            ),
          ),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: palette.muted, fontStyle: FontStyle.italic),
          child: block,
        ),
      );
    }

    final anchor = _pendingAnchor;
    _pendingAnchor = null;
    widgets.add(
      Padding(
        key: anchor != null ? (anchorKeys![anchor] ??= GlobalKey()) : null,
        padding: padding.copyWith(left: indent + 14.0 * _quoteDepth),
        child: block,
      ),
    );
    _spans.clear();
    _kind = _BlockKind.paragraph;
  }
}
