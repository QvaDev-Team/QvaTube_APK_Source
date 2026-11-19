import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_cached_image.dart';
import '../catalog/application/catalog_providers.dart';
import '../catalog/domain/catalog_models.dart';
import '../home/presentation/widgets/media_player_screen.dart';
import '../reader/book_reader_screen.dart';
import 'telegram_files.dart';
import 'telegram_library.dart';
import 'telegram_service.dart';

/// "Mis archivos de Telegram": lo que el bot de QvaTube envió al chat del
/// usuario, para descargarlo cuando quiera y verlo sin conexión.
///
/// Dividido en secciones como el catálogo (Películas, Series, Música…),
/// cada una con buscador y filtro por estado; los episodios se agrupan por
/// serie.
class TelegramFilesList extends ConsumerStatefulWidget {
  const TelegramFilesList({super.key});

  @override
  ConsumerState<TelegramFilesList> createState() => _TelegramFilesListState();
}

class _TelegramFilesListState extends ConsumerState<TelegramFilesList> {
  final TelegramFiles _files = TelegramFiles.instance;
  final TextEditingController _search = TextEditingController();

  TgSection? _section;
  String _query = '';
  TgStatusFilter _status = TgStatusFilter.all;

  /// Series desplegadas (por título en minúsculas).
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _files.addListener(_onChanged);
    TelegramService.instance.online.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _files.removeListener(_onChanged);
    TelegramService.instance.online.removeListener(_onChanged);
    _search.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    // Título y carátula del catálogo (lo enviado con el gestor de
    // descargas). Sin conexión con QvaTube se muestran los nombres de
    // archivo de Telegram.
    unawaited(
      ref
          .read(catalogApiProvider)
          .telegramFiles()
          .then(_files.applyCatalog)
          .catchError((_) {}),
    );
    final config = await ref
        .read(siteConfigProvider.future)
        .catchError((_) => const SiteConfig());
    await _files.load(config.botUsername ?? 'qvatube_bot');
  }

  /// Reproduce [file] y, a continuación, los demás ya descargados de
  /// [queue] (episodios de la misma serie, pistas de la sección…).
  void _play(TgFile file, [List<TgFile>? queue]) {
    final items = (queue ?? [file])
        .where((f) => f.completed && f.playable)
        .toList();
    if (!items.contains(file)) items.insert(0, file);
    openMediaPlayer(
      context,
      initialIndex: items.indexOf(file),
      playlist: [
        for (final f in items)
          PlayableMediaItem(
            chatId: 0,
            msgId: f.messageId,
            title: f.title,
            isAudio: f.kind == TgFileKind.audio,
            localPath: f.localPath,
            posterUrl: f.catalog?.poster,
          ),
      ],
    );
  }

  Future<void> _confirmRemove(TgFile file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar del teléfono'),
        content: Text(
          file.fileId < 0
              // Recibido por Wi-Fi: no está en el chat del bot.
              ? '${file.title} se borrará de tu teléfono. Lo recibiste por '
                    'Wi-Fi: para tenerlo otra vez tendrás que volver a '
                    'recibirlo o descargarlo.'
              : '${file.title} se borrará de tu teléfono para liberar '
                    'espacio. Sigue en el chat del bot por si lo quieres '
                    'descargar otra vez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok == true) await _files.remove(file);
  }

  @override
  Widget build(BuildContext context) {
    final files = _files.files;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Archivos del bot',
                style: AppTextStyles.body(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _files.loading || _files.syncing ? null : _reload,
              icon: const Icon(LucideIcons.refreshCw, size: 20),
            ),
          ],
        ),
        if (_files.syncing && files.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_files.loading && files.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_files.waitingForConnection)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Conectando con Telegram… Tus archivos aparecerán en '
                    'cuanto haya conexión.',
                    style: AppTextStyles.body(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (_files.error != null && files.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              _files.error!,
              style: AppTextStyles.body(fontSize: 13, color: AppColors.danger),
            ),
          )
        else if (files.isEmpty)
          _note(
            'Todavía no hay archivos. Toca "Descargar" en una película o '
            'serie y el bot te los enviará: aparecerán aquí.',
          )
        else
          ..._library(files),
      ],
    );
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      text,
      style: AppTextStyles.body(
        fontSize: 13,
        color: AppColors.textSecondary,
        height: 1.45,
      ),
    ),
  );

  /// Secciones, buscador, filtro y el contenido de la sección elegida.
  List<Widget> _library(List<TgFile> files) {
    final counts = sectionCounts(files);
    final section = counts.containsKey(_section)
        ? _section!
        : counts.keys.first;
    final visible = filterFiles(
      files,
      section: section,
      query: _query,
      status: _status,
    );

    return [
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final entry in counts.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Pill(
                  label: entry.key.label,
                  count: entry.value,
                  selected: entry.key == section,
                  onTap: () => setState(() => _section = entry.key),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _search,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        style: AppTextStyles.body(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Buscar en ${section.label}',
          prefixIcon: const Icon(LucideIcons.search, size: 18),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Borrar búsqueda',
                  icon: const Icon(LucideIcons.x, size: 18),
                  onPressed: () => setState(() {
                    _search.clear();
                    _query = '';
                  }),
                ),
          isDense: true,
          filled: true,
          fillColor: AppColors.surfaceSecondary,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final s in TgStatusFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Pill(
                  label: s.label,
                  selected: s == _status,
                  small: true,
                  onTap: () => setState(() => _status = s),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Desliza un archivo hacia la izquierda para quitarlo del gestor.',
        style: AppTextStyles.body(fontSize: 11.5, color: AppColors.textMuted),
      ),
      const SizedBox(height: 12),
      if (visible.isEmpty)
        _note(
          _query.isNotEmpty
              ? 'Nada en ${section.label} coincide con "$_query".'
              : 'No hay archivos en ${section.label} con este filtro.',
        )
      else if (section == TgSection.all)
        // Todo junto, lo más reciente arriba: los episodios en su serie.
        for (final entry in _mixed(visible)) ...[
          entry,
          const SizedBox(height: 10),
        ]
      else if (section.groupsBySeries)
        for (final group in groupSeries(visible)) ...[
          _seriesCard(group),
          const SizedBox(height: 10),
        ]
      else
        for (final file in visible) ...[
          _tile(file, queue: visible),
          const SizedBox(height: 10),
        ],
    ];
  }

  /// "Todos": películas, música… sueltas y los episodios agrupados en su
  /// serie, ordenado por la fecha del envío más reciente.
  List<Widget> _mixed(List<TgFile> files) {
    final series = <TgFile>[];
    final singles = <TgFile>[];
    for (final f in files) {
      (sectionOf(f).groupsBySeries ? series : singles).add(f);
    }
    final entries = <({DateTime date, Widget widget})>[
      for (final f in singles)
        (
          date: f.date,
          // La cola sigue con archivos de la misma sección (después de una
          // película no debe sonar una canción).
          widget: _tile(
            f,
            queue: [
              for (final o in singles)
                if (sectionOf(o) == sectionOf(f)) o,
            ],
          ),
        ),
      for (final g in groupSeries(series))
        (
          date: g.episodes
              .map((e) => e.date)
              .reduce((a, b) => a.isAfter(b) ? a : b),
          widget: _seriesCard(g),
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));
    return [for (final e in entries) e.widget];
  }

  Widget _tile(TgFile file, {List<TgFile>? queue, String? title}) => _removable(
    key: 'f:${file.messageId}',
    files: [file],
    label: title ?? file.title,
    child: _fileTile(file, queue: queue, title: title),
  );

  Widget _fileTile(TgFile file, {List<TgFile>? queue, String? title}) =>
      _FileTile(
        file: file,
        title: title,
        onDownload: () => _files.download(file),
        onPause: () => _files.pause(file),
        onPlay: () => _play(file, queue),
        onRead: () => openBookReader(
          context,
          chatId: 0,
          msgId: file.messageId,
          title: file.title,
          localPath: file.localPath,
        ),
        onRemove: () => _confirmRemove(file),
      );

  /// Deslizar a la izquierda = quitar del gestor. Si hay algo en el
  /// teléfono se confirma (se borra); si no, se puede deshacer.
  Widget _removable({
    required String key,
    required List<TgFile> files,
    required String label,
    required Widget child,
  }) {
    final local = files.any((f) => f.completed || f.downloaded > 0);
    final received = files.any((f) => f.fileId < 0);
    return Dismissible(
      key: ValueKey(key),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Quitar',
              style: AppTextStyles.body(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(LucideIcons.eyeOff, color: AppColors.danger, size: 20),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        if (!local && !received) return true;
        return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Quitar del gestor'),
                content: Text(
                  received
                      ? '$label se borrará de tu teléfono y del gestor. Lo '
                            'recibiste por Wi-Fi: para tenerlo otra vez '
                            'tendrás que volver a recibirlo.'
                      : '$label se quitará del gestor y lo descargado se '
                            'borrará de tu teléfono. Sigue en el chat del bot.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Quitar'),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) {
        final messenger = ScaffoldMessenger.of(context);
        unawaited(_files.hide(files));
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Quitado: $label'),
              persist: false,
              duration: const Duration(seconds: 4),
              action: received
                  ? null
                  : SnackBarAction(
                      label: 'Deshacer',
                      onPressed: () => _files.unhide(files),
                    ),
            ),
          );
      },
      child: child,
    );
  }

  /// Tarjeta de una serie: carátula, episodios y cuántos están en el
  /// teléfono; al tocarla se despliegan los episodios.
  Widget _seriesCard(TgSeriesGroup group) {
    final key = group.title.toLowerCase();
    final open = _expanded.contains(key) || _query.isNotEmpty;
    final pending = group.episodes
        .where((e) => !e.completed && !e.downloading)
        .toList();
    final poster = absoluteMediaUrl(group.poster);
    final placeholder = const ColoredBox(
      color: AppColors.surface,
      child: Icon(LucideIcons.tv, color: AppColors.accent, size: 22),
    );
    final count = group.episodes.length;

    return _removable(
      key: 'serie:${group.title}',
      files: group.episodes,
      label: group.title,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(AppRadii.md),
              onTap: () => setState(() {
                if (!_expanded.remove(key)) _expanded.add(key);
              }),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 46,
                        height: 66,
                        child: poster.isEmpty
                            ? placeholder
                            : AppCachedImage(
                                imageUrl: poster,
                                placeholder: placeholder,
                                errorWidget: placeholder,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$count ${count == 1 ? 'episodio' : 'episodios'} · '
                            '${group.downloadedCount} en el teléfono',
                            style: AppTextStyles.body(
                              fontSize: 12,
                              color: group.downloadedCount == count
                                  ? AppColors.success
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (pending.isNotEmpty)
                      _RoundAction(
                        icon: LucideIcons.arrowDownToLine,
                        tooltip: 'Descargar los ${pending.length} pendientes',
                        onTap: () => _confirmDownloadAll(group, pending),
                      ),
                    const SizedBox(width: 6),
                    Icon(
                      open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            if (open)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Column(
                  children: [
                    for (final e in group.episodes) ...[
                      _tile(e, queue: group.episodes, title: _episodeTitle(e)),
                      const SizedBox(height: 6),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Descargar todos los episodios pendientes de una serie: pueden ser
  /// decenas de GB, así que se confirma con el total antes de empezar.
  Future<void> _confirmDownloadAll(
    TgSeriesGroup group,
    List<TgFile> pending,
  ) async {
    final bytes = pending.fold<int>(0, (s, e) => s + (e.size - e.downloaded));
    final n = pending.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Descargar $n ${n == 1 ? 'episodio' : 'episodios'}'),
        content: Text(
          'Se descargarán ${_FileTile._size(bytes)} de ${group.title} en tu '
          'teléfono. Asegúrate de tener espacio y, si usas datos móviles, '
          'de que te alcancen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Descargar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final e in pending) {
      await _files.download(e);
    }
  }

  /// "T1 · E07" si se sabe el episodio; si no, el nombre del archivo.
  static String _episodeTitle(TgFile f) {
    final ep = episodeOf(f);
    if (ep == null) return f.title;
    return 'T${ep.season} · E${ep.episode.toString().padLeft(2, '0')}';
  }
}

/// Botón tipo píldora para secciones y filtros.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.small = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent : AppColors.surfaceSecondary,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: small ? 12 : 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStyles.body(
                  fontSize: small ? 12 : 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: AppTextStyles.body(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? Colors.white.withValues(alpha: 0.85)
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    this.title,
    required this.onDownload,
    required this.onPause,
    required this.onPlay,
    required this.onRead,
    required this.onRemove,
  });

  final TgFile file;

  /// Título a mostrar en lugar de [TgFile.title] (p. ej. "T1 · E07"
  /// dentro de la tarjeta de su serie).
  final String? title;
  final VoidCallback onDownload;
  final VoidCallback onPause;
  final VoidCallback onPlay;
  final VoidCallback onRead;
  final VoidCallback onRemove;

  static String _size(int bytes) {
    if (bytes <= 0) return '—';
    const mb = 1024 * 1024;
    if (bytes >= 1024 * mb) {
      return '${(bytes / (1024 * mb)).toStringAsFixed(2)} GB';
    }
    return '${(bytes / mb).toStringAsFixed(bytes >= 100 * mb ? 0 : 1)} MB';
  }

  String get _status {
    if (file.completed) return 'Descargado · ${_size(file.size)}';
    if (file.downloading) {
      // Recién empezada todavía no hay bytes: "0 MB", no "—".
      final done = file.downloaded > 0 ? _size(file.downloaded) : '0 MB';
      // Al abrir la app TDLib puede tardar en conectar: la descarga está
      // en cola, no colgada.
      if (!TelegramService.instance.online.value) {
        return 'Esperando conexión con Telegram… · $done de ${_size(file.size)}';
      }
      return '$done de ${_size(file.size)} · '
          '${(file.progress * 100).floor()} %';
    }
    if (file.downloaded > 0) {
      return 'En pausa · ${_size(file.downloaded)} de ${_size(file.size)}';
    }
    return _size(file.size);
  }

  /// Carátula del catálogo; si no hay, la miniatura que trae el mensaje
  /// de Telegram; si tampoco, un icono.
  Widget _thumb(IconData icon) {
    final fallback = ColoredBox(
      color: AppColors.surface,
      child: Icon(icon, color: AppColors.accent, size: 22),
    );
    final thumb = file.thumbnail;
    final local = thumb != null
        ? Image.memory(thumb, fit: BoxFit.cover, gaplessPlayback: true)
        : fallback;
    final poster = absoluteMediaUrl(file.catalog?.poster);
    if (poster.isEmpty) return local;
    return AppCachedImage(
      imageUrl: poster,
      placeholder: local,
      errorWidget: local,
    );
  }

  @override
  Widget build(BuildContext context) {
    final icon = switch (file.kind) {
      TgFileKind.video => LucideIcons.film,
      TgFileKind.audio => LucideIcons.music,
      TgFileKind.document => LucideIcons.fileText,
    };
    // Cada estado muestra solo lo que se puede hacer en él: ver/leer y
    // borrar solo cuando el archivo ya está en el teléfono.
    final Widget action;
    if (file.completed) {
      action = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (file.playable)
            _RoundAction(
              icon: LucideIcons.play,
              tooltip: 'Ver',
              filled: true,
              onTap: onPlay,
            )
          else if (file.readable)
            _RoundAction(
              icon: LucideIcons.bookOpen,
              tooltip: 'Leer',
              filled: true,
              onTap: onRead,
            ),
          const SizedBox(width: 4),
          _RoundAction(
            icon: LucideIcons.trash2,
            tooltip: 'Borrar del teléfono',
            ghost: true,
            onTap: onRemove,
          ),
        ],
      );
    } else if (file.downloading) {
      action = _RoundAction(
        icon: LucideIcons.pause,
        tooltip: 'Pausar',
        progress: file.progress,
        onTap: onPause,
      );
    } else if (file.downloaded > 0) {
      action = _RoundAction(
        icon: LucideIcons.arrowDownToLine,
        tooltip: 'Reanudar',
        progress: file.progress,
        paused: true,
        onTap: onDownload,
      );
    } else {
      action = _RoundAction(
        icon: LucideIcons.arrowDownToLine,
        tooltip: 'Descargar',
        onTap: onDownload,
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(width: 46, height: 46, child: _thumb(icon)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title ?? file.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _status,
                      style: AppTextStyles.body(
                        fontSize: 11.5,
                        color: file.completed
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              action,
            ],
          ),
        ],
      ),
    );
  }
}

/// Botón redondo de acción de una fila: lleno (ver/leer), con borde
/// (descargar, pausar) o fantasma (borrar). Con [progress] dibuja un aro
/// con el avance de la descarga alrededor.
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.filled = false,
    this.ghost = false,
    this.paused = false,
    this.progress,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool filled;
  final bool ghost;
  final bool paused;
  final double? progress;

  static const double _size = 40;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final iconColor = filled
        ? Colors.white
        : ghost
        ? AppColors.textMuted
        : p != null && !paused
        ? AppColors.textPrimary
        : AppColors.accent;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: _size / 2 + 2,
        child: SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (filled)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.expand(),
                )
              else if (!ghost)
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: p != null ? Colors.transparent : AppColors.border,
                      width: 1.4,
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              if (p != null) ...[
                const SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 2.4,
                    color: AppColors.border,
                  ),
                ),
                SizedBox.expand(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: p.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 400),
                    builder: (context, v, _) => CircularProgressIndicator(
                      value: v,
                      strokeWidth: 2.4,
                      strokeCap: StrokeCap.round,
                      color: paused ? AppColors.textMuted : AppColors.accent,
                    ),
                  ),
                ),
              ],
              Padding(
                // El triángulo de "play" se ve centrado con un poco a la
                // derecha.
                padding: EdgeInsets.only(
                  left: icon == LucideIcons.play ? 2 : 0,
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
