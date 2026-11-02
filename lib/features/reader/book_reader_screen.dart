import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_providers.dart';
import '../../core/network/endpoints/playback_endpoints.dart';
import '../../core/platform/device_channel.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../catalog/application/catalog_providers.dart';
import '../catalog/domain/catalog_models.dart';
import 'epub_book.dart';
import 'epub_chapter_view.dart';
import 'pdf_pages_view.dart';

/// Abre el lector de libros (EPUB o PDF) a pantalla completa.
Future<void> openBookReader(
  BuildContext context, {
  required int chatId,
  required int msgId,
  required String title,
  double? initialPositionSeconds,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (_) => BookReaderScreen(
        chatId: chatId,
        msgId: msgId,
        title: title,
        initialPositionSeconds: initialPositionSeconds,
      ),
    ),
  );
}

enum _ReaderTheme { dark, sepia, light }

const _palettes = {
  _ReaderTheme.dark: ReaderPalette(
    background: Color(0xFF0D0E11),
    text: Color(0xFFE6E6E6),
    muted: Color(0xFF9A9AA0),
    link: Color(0xFFFF6B4A),
  ),
  _ReaderTheme.sepia: ReaderPalette(
    background: Color(0xFFF4ECD8),
    text: Color(0xFF3B2F22),
    muted: Color(0xFF7A6A55),
    link: Color(0xFFB4441F),
  ),
  _ReaderTheme.light: ReaderPalette(
    background: Color(0xFFFFFFFF),
    text: Color(0xFF1A1A1A),
    muted: Color(0xFF6B6B6B),
    link: Color(0xFFD63A12),
  ),
};

const _themeLabels = {
  _ReaderTheme.dark: 'Oscuro',
  _ReaderTheme.sepia: 'Sepia',
  _ReaderTheme.light: 'Claro',
};

/// Lector de libros integrado, equivalente a `reader.js` de la web: baja el
/// archivo de `/read/{chat}/{msg}` con la sesión, abre los EPUB capítulo a
/// capítulo con el tema de QvaTube y los PDF página a página. Guarda la
/// posición en el teléfono y en el servidor ("Seguir donde quedaste", con la
/// escala 0–1000 que usa la web).
class BookReaderScreen extends ConsumerStatefulWidget {
  const BookReaderScreen({
    super.key,
    required this.chatId,
    required this.msgId,
    required this.title,
    this.initialPositionSeconds,
  });

  final int chatId;
  final int msgId;
  final String title;

  /// Progreso guardado en el servidor (0–1000), si se abrió desde
  /// "Seguir donde quedaste".
  final double? initialPositionSeconds;

  @override
  ConsumerState<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends ConsumerState<BookReaderScreen> {
  static const _fontMin = 14.0, _fontMax = 28.0, _fontStep = 2.0;
  static const _prefsKey = 'qvatube:reader:prefs';

  String get _posKey => 'qvatube:read:${widget.chatId}:${widget.msgId}';

  final _scroll = ScrollController();

  /// Progreso del libro (0–1) para la barra inferior: se actualiza al hacer
  /// scroll sin reconstruir (ni volver a parsear) el capítulo.
  final _progress = ValueNotifier<double>(0);
  final CancelToken _cancel = CancelToken();
  Timer? _saveTimer;
  Timer? _serverTimer;

  bool _loading = true;
  double? _downloadProgress;
  String? _error;

  EpubBook? _epub;
  List<Size>? _pdfSizes;
  File? _pdfFile;
  final _pdfKey = GlobalKey<PdfPagesViewState>();

  int _chapter = 0;
  Map<String, GlobalKey> _anchors = {};
  int _pdfPage = 0;
  int _pdfTotal = 0;

  double _fontSize = 18;
  _ReaderTheme _theme = _ReaderTheme.dark;
  bool _showBars = true;

  ReaderPalette get _palette => _palettes[_theme]!;

  int get _total => _epub?.chapters.length ?? _pdfTotal;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _cancel.cancel();
    _saveTimer?.cancel();
    _serverTimer?.cancel();
    if (_epub != null || _pdfTotal > 0) {
      _saveLocal();
      _syncServer();
    }
    if (_pdfFile != null) {
      DeviceChannel.pdfClose().whenComplete(() {
        _pdfFile?.delete().catchError((_) => _pdfFile!);
      });
    }
    _scroll.dispose();
    _progress.dispose();
    super.dispose();
  }

  // ── Carga ───────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _downloadProgress = null;
    });

    final prefs = await SharedPreferences.getInstance();
    try {
      final saved = jsonDecode(prefs.getString(_prefsKey) ?? '{}') as Map;
      _fontSize = ((saved['size'] as num?)?.toDouble() ?? _fontSize).clamp(
        _fontMin,
        _fontMax,
      );
      _theme = _ReaderTheme.values.firstWhere(
        (t) => t.name == saved['theme'],
        orElse: () => _ReaderTheme.dark,
      );
    } catch (_) {}

    final Response<List<int>> response;
    try {
      response = await ref
          .read(apiClientProvider)
          .dio
          .get<List<int>>(
            absoluteMediaUrl(
              PlaybackEndpoints.read(widget.chatId, widget.msgId),
            ),
            cancelToken: _cancel,
            options: Options(
              responseType: ResponseType.bytes,
              validateStatus: (_) => true,
              receiveTimeout: const Duration(seconds: 60),
            ),
            onReceiveProgress: (received, total) {
              if (!mounted || total <= 0) return;
              setState(() => _downloadProgress = received / total);
            },
          );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e) || !mounted) return;
      setState(() {
        _loading = false;
        _error = 'Error de conexión. Intenta de nuevo.';
      });
      return;
    }
    if (!mounted) return;

    final status = response.statusCode ?? 0;
    final bytes = Uint8List.fromList(response.data ?? const []);
    if (status < 200 || status >= 300) {
      setState(() {
        _loading = false;
        _error = _statusMessage(status, bytes);
      });
      return;
    }

    final format =
        response.headers.value('x-book-format') ??
        (response.headers.value('content-type')?.contains('pdf') == true ||
                (bytes.length > 4 &&
                    String.fromCharCodes(bytes.sublist(0, 4)) == '%PDF')
            ? 'pdf'
            : 'epub');

    final pos = _savedPosition(prefs);
    if (format == 'pdf') {
      try {
        // PdfRenderer necesita un archivo: se guarda en la caché y se borra
        // al cerrar el lector.
        final file = File(
          '${Directory.systemTemp.path}/book_${widget.chatId}_${widget.msgId}.pdf',
        );
        await file.writeAsBytes(bytes, flush: true);
        final sizes = await DeviceChannel.pdfOpen(file.path);
        if (!mounted) return;
        if (sizes.isEmpty) throw const FormatException('PDF vacío');
        _pdfFile = file;
        var page = pos.$1;
        final server = _pendingServerFraction;
        if (server != null) {
          _pendingServerFraction = null;
          page = (server * sizes.length).floor();
        }
        setState(() {
          _pdfSizes = sizes;
          _pdfTotal = sizes.length;
          _pdfPage = page.clamp(0, sizes.length - 1);
          _loading = false;
        });
        _progress.value = _overall();
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'No se pudo abrir este PDF.';
        });
      }
      return;
    }

    try {
      final book = await compute(EpubBook.parse, bytes);
      if (!mounted) return;
      setState(() {
        _epub = book;
        _chapter = pos.$1.clamp(0, book.chapters.length - 1);
        _anchors = {};
        _loading = false;
      });
      _jumpToFraction(pos.$2);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is EpubException ? e.message : 'No se pudo abrir el libro.';
      });
    }
  }

  String _statusMessage(int status, Uint8List body) {
    switch (status) {
      case 401:
        return 'Inicia sesión para leer este libro.';
      case 403:
        return 'Alcanzaste el límite de tu plan. Para aumentarlo, adquiere un plan.';
      case 404:
        return 'Este libro ya no está disponible.';
      case 413:
        return 'Este libro es muy grande para leerlo en pantalla. Descárgalo.';
      case 415:
        return 'Este libro no se puede leer en pantalla (el formato solo se puede descargar).';
      case 503:
        return 'El servicio de lectura está al máximo de su capacidad. Intenta de nuevo en unos segundos.';
    }
    final text = utf8.decode(body, allowMalformed: true).trim();
    return text.isNotEmpty && text.length < 200
        ? text
        : 'No se pudo abrir este libro.';
  }

  /// (capítulo o página, fracción dentro de él). Primero la posición del
  /// teléfono; si no hay, la del servidor (escala 0–1000 del libro entero).
  (int, double) _savedPosition(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_posKey);
      if (raw != null) {
        final m = jsonDecode(raw) as Map;
        return (
          (m['i'] as num?)?.toInt() ?? 0,
          (m['f'] as num?)?.toDouble() ?? 0,
        );
      }
    } catch (_) {}
    final server = (widget.initialPositionSeconds ?? 0) / 1000;
    if (server <= 0) return (0, 0);
    _pendingServerFraction = server.clamp(0, 1).toDouble();
    return (0, 0);
  }

  /// Progreso del servidor a aplicar cuando se sepa el total de capítulos o
  /// páginas.
  double? _pendingServerFraction;

  void _applyServerFraction() {
    final f = _pendingServerFraction;
    if (f == null || _total <= 0) return;
    _pendingServerFraction = null;
    final exact = f * _total;
    final idx = exact.floor().clamp(0, _total - 1);
    if (_epub != null) {
      setState(() {
        _chapter = idx;
        _anchors = {};
      });
      _jumpToFraction(exact - idx);
    }
  }

  // ── Posición ────────────────────────────────────────────────────────────

  double _fraction() {
    if (!_scroll.hasClients) return 0;
    final max = _scroll.position.maxScrollExtent;
    return max > 0 ? (_scroll.offset / max).clamp(0, 1) : 0;
  }

  double _overall() {
    if (_total <= 0) return 0;
    final current = _epub != null
        ? _chapter + _fraction()
        : (_pdfPage + 1).toDouble();
    return (current / _total).clamp(0, 1);
  }

  void _jumpToFraction(double f) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      if (!_applyAnchor()) {
        _scroll.jumpTo(f * _scroll.position.maxScrollExtent);
      }
      _progress.value = _overall();
    });
  }

  String? _pendingAnchor;

  bool _applyAnchor() {
    final anchor = _pendingAnchor;
    _pendingAnchor = null;
    final ctx = anchor == null ? null : _anchors[anchor]?.currentContext;
    if (ctx == null) return false;
    Scrollable.ensureVisible(ctx);
    return true;
  }

  void _onScroll() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _savePosition);
    _progress.value = _overall();
  }

  void _savePosition() {
    _saveLocal();
    _serverTimer?.cancel();
    _serverTimer = Timer(const Duration(seconds: 8), _syncServer);
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final value = _epub != null
        ? {'i': _chapter, 'f': double.parse(_fraction().toStringAsFixed(4))}
        : {'i': _pdfPage, 'f': 0};
    await prefs.setString(_posKey, jsonEncode(value));
  }

  void _syncServer() {
    if (_total <= 0) return;
    ref
        .read(catalogApiProvider)
        .saveProgress(
          chatId: widget.chatId,
          msgId: widget.msgId,
          positionSeconds: (_overall() * 1000).roundToDouble(),
          durationSeconds: 1000,
          kind: 'book',
        );
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode({'size': _fontSize, 'theme': _theme.name}),
    );
  }

  // ── Navegación ──────────────────────────────────────────────────────────

  void _goToChapter(int idx, {String? anchor}) {
    final book = _epub;
    if (book == null || idx < 0 || idx >= book.chapters.length) return;
    setState(() {
      _chapter = idx;
      _anchors = {};
    });
    _pendingAnchor = anchor;
    _jumpToFraction(0);
    _savePosition();
  }

  void _openToc() {
    final book = _epub;
    if (book == null) return;
    final entries = book.toc.isNotEmpty
        ? book.toc
        : [
            for (var i = 0; i < book.chapters.length; i++)
              EpubTocEntry(label: book.chapters[i].title, chapterIndex: i),
          ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Índice',
                style: AppTextStyles.body(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  final e = entries[i];
                  final active = e.chapterIndex == _chapter;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.only(
                      left: 20 + 16.0 * e.depth,
                      right: 20,
                    ),
                    title: Text(
                      e.label,
                      style: AppTextStyles.body(
                        fontSize: 13.5,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        color: active ? AppColors.accent : Colors.white,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _goToChapter(e.chapterIndex, anchor: e.anchor);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _changeFont(double delta) {
    final next = (_fontSize + delta).clamp(_fontMin, _fontMax);
    if (next == _fontSize) return;
    final f = _fraction();
    setState(() => _fontSize = next);
    _jumpToFraction(f);
    _savePrefs();
  }

  void _cycleTheme() {
    final values = _ReaderTheme.values;
    setState(() => _theme = values[(_theme.index + 1) % values.length]);
    _savePrefs();
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    final isEpub = _epub != null;
    final dark = _theme == _ReaderTheme.dark || !isEpub;
    final barColor = dark ? const Color(0xFF16181D) : palette.background;
    final barText = dark ? Colors.white : palette.text;

    return Scaffold(
      backgroundColor: isEpub ? palette.background : const Color(0xFF0D0E11),
      appBar: (_showBars || (!isEpub && _pdfSizes == null))
          ? AppBar(
              backgroundColor: barColor,
              foregroundColor: barText,
              elevation: 0,
              titleSpacing: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _epub?.title ?? widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: barText,
                    ),
                  ),
                  if (isEpub)
                    Text(
                      _epub!.chapters[_chapter].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(
                        fontSize: 11.5,
                        color: barText.withValues(alpha: 0.65),
                      ),
                    ),
                ],
              ),
              actions: [
                if (isEpub) ...[
                  IconButton(
                    tooltip: 'Índice',
                    onPressed: _openToc,
                    icon: const Icon(LucideIcons.list),
                  ),
                  IconButton(
                    tooltip: 'Letra más pequeña',
                    onPressed: _fontSize > _fontMin
                        ? () => _changeFont(-_fontStep)
                        : null,
                    icon: const Icon(LucideIcons.aArrowDown),
                  ),
                  IconButton(
                    tooltip: 'Letra más grande',
                    onPressed: _fontSize < _fontMax
                        ? () => _changeFont(_fontStep)
                        : null,
                    icon: const Icon(LucideIcons.aArrowUp),
                  ),
                  IconButton(
                    tooltip: 'Tema: ${_themeLabels[_theme]}',
                    onPressed: _cycleTheme,
                    icon: Icon(
                      _theme == _ReaderTheme.dark
                          ? LucideIcons.moon
                          : _theme == _ReaderTheme.sepia
                          ? LucideIcons.coffee
                          : LucideIcons.sun,
                    ),
                  ),
                ],
              ],
            )
          : null,
      body: SafeArea(child: _buildBody(palette)),
      bottomNavigationBar: (isEpub || _pdfSizes != null) && _showBars
          ? _buildBottomBar(barColor, barText)
          : null,
    );
  }

  Widget _buildBody(ReaderPalette palette) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 180,
              child: LinearProgressIndicator(
                value: _downloadProgress,
                color: AppColors.accent,
                backgroundColor: Colors.white12,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _downloadProgress == null
                  ? 'Abriendo libro…'
                  : 'Descargando libro… ${(_downloadProgress! * 100).round()}%',
              style: AppTextStyles.body(fontSize: 13, color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.menu_book_outlined,
                color: AppColors.accent,
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTextStyles.body(fontSize: 13.5, color: Colors.white),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final pdfSizes = _pdfSizes;
    if (pdfSizes != null) {
      return PdfPagesView(
        key: _pdfKey,
        pageSizes: pdfSizes,
        initialPage: _pdfPage,
        onTap: () => setState(() => _showBars = !_showBars),
        onPageChanged: (page) {
          _pdfPage = page;
          _progress.value = _overall();
          _savePosition();
        },
      );
    }

    final book = _epub!;
    if (_pendingServerFraction != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _applyServerFraction(),
      );
    }
    return GestureDetector(
      onTap: () => setState(() => _showBars = !_showBars),
      child: Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          key: ValueKey('chapter-$_chapter'),
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EpubChapterView(
                book: book,
                chapterPath: book.chapters[_chapter].path,
                fontSize: _fontSize,
                palette: palette,
                anchorKeys: _anchors,
              ),
              const SizedBox(height: 24),
              if (_chapter < book.chapters.length - 1)
                Center(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                    ),
                    onPressed: () => _goToChapter(_chapter + 1),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Siguiente capítulo'),
                  ),
                )
              else
                Center(
                  child: Text(
                    'Fin del libro',
                    style: TextStyle(color: palette.muted, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(Color barColor, Color barText) {
    final isPdf = _pdfSizes != null;
    final index = isPdf ? _pdfPage : _chapter;
    void go(int target) {
      if (isPdf) {
        _pdfKey.currentState?.jumpToPage(target);
      } else {
        _goToChapter(target);
      }
    }

    return Material(
      color: barColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ValueListenableBuilder<double>(
            valueListenable: _progress,
            builder: (context, value, _) {
              final current = isPdf ? _pdfPage : index;
              return Row(
                children: [
                  IconButton(
                    tooltip: isPdf ? 'Página anterior' : 'Capítulo anterior',
                    color: barText,
                    onPressed: current > 0 ? () => go(current - 1) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      '${isPdf ? 'Pág.' : 'Cap.'} ${current + 1}/$_total · '
                      '${(value * 100).round()}%',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.mono(fontSize: 12, color: barText),
                    ),
                  ),
                  IconButton(
                    tooltip: isPdf ? 'Página siguiente' : 'Capítulo siguiente',
                    color: barText,
                    onPressed: current < _total - 1
                        ? () => go(current + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
