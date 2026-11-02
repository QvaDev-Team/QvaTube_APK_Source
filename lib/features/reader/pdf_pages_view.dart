import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/platform/device_channel.dart';
import '../../core/theme/app_colors.dart';

/// PDF página a página, dibujado por el `PdfRenderer` de Android (ver
/// `PdfPages` en MainActivity.kt). Las páginas se piden al hacer scroll y se
/// guardan en memoria solo las últimas, para no gastar RAM en libros largos.
class PdfPagesView extends StatefulWidget {
  const PdfPagesView({
    super.key,
    required this.pageSizes,
    required this.initialPage,
    required this.onPageChanged,
    this.onTap,
  });

  /// Tamaño (en puntos) de cada página, de `DeviceChannel.pdfOpen`.
  final List<Size> pageSizes;
  final int initialPage;
  final ValueChanged<int> onPageChanged;
  final VoidCallback? onTap;

  @override
  State<PdfPagesView> createState() => PdfPagesViewState();
}

class PdfPagesViewState extends State<PdfPagesView> {
  static const _spacing = 8.0;
  static const _cacheSize = 8;

  final _scroll = ScrollController();
  final _cache = <int, Future<Uint8List?>>{};
  double _width = 0;
  late int _page = widget.initialPage;
  bool _jumped = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _pageHeight(int i) {
    final s = widget.pageSizes[i];
    return _width * s.height / s.width + _spacing;
  }

  double _offsetOf(int page) {
    var offset = 0.0;
    for (var i = 0; i < page; i++) {
      offset += _pageHeight(i);
    }
    return offset;
  }

  void jumpToPage(int page) {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(
      _offsetOf(page.clamp(0, widget.pageSizes.length - 1))
          .clamp(0, _scroll.position.maxScrollExtent),
    );
  }

  void _onScroll() {
    // Página actual = la que ocupa el centro de la pantalla.
    final center = _scroll.offset + _scroll.position.viewportDimension / 2;
    var offset = 0.0;
    var page = 0;
    for (var i = 0; i < widget.pageSizes.length; i++) {
      offset += _pageHeight(i);
      if (offset > center) {
        page = i;
        break;
      }
      page = i;
    }
    if (page != _page) {
      _page = page;
      widget.onPageChanged(page);
    }
  }

  Future<Uint8List?> _render(int index, int pixelWidth) {
    final cached = _cache.remove(index);
    if (cached != null) {
      _cache[index] = cached;
      return cached;
    }
    final future = DeviceChannel.pdfRenderPage(index, pixelWidth);
    _cache[index] = future;
    while (_cache.length > _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - 16;
        if (width != _width) {
          _width = width;
          _cache.clear();
        }
        if (!_jumped) {
          _jumped = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => jumpToPage(widget.initialPage),
          );
        }
        final pixelWidth = (width * dpr).round();
        return GestureDetector(
          onTap: widget.onTap,
          child: Scrollbar(
            controller: _scroll,
            interactive: true,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: widget.pageSizes.length,
              itemExtentBuilder: (i, _) => _pageHeight(i),
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: _spacing),
                child: FutureBuilder<Uint8List?>(
                  future: _render(i, pixelWidth),
                  builder: (context, snapshot) {
                    final bytes = snapshot.data;
                    if (bytes == null) {
                      return Container(
                        color: Colors.white10,
                        alignment: Alignment.center,
                        child: snapshot.hasError
                            ? const Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white38,
                              )
                            : const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accent,
                                ),
                              ),
                      );
                    }
                    return Image.memory(
                      bytes,
                      fit: BoxFit.fill,
                      gaplessPlayback: true,
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
