import 'package:flutter/foundation.dart';

import 'telegram_files.dart';

/// Sección de "Mis archivos de Telegram" (mismas categorías que el
/// catálogo de QvaTube, más "Otros").
enum TgSection {
  movies('Películas', 'movie'),
  series('Series', 'series'),
  anime('Anime', 'anime'),
  novelas('Novelas', 'novela'),
  music('Música', 'music'),
  books('Libros', 'book'),
  other('Otros', null);

  const TgSection(this.label, this.categoryKey);

  final String label;

  /// Clave de categoría del catálogo (`category_key`).
  final String? categoryKey;

  /// Secciones donde los archivos son episodios y se agrupan por serie.
  bool get groupsBySeries =>
      this == TgSection.series ||
      this == TgSection.anime ||
      this == TgSection.novelas;
}

/// Filtro por estado de la descarga en el teléfono.
enum TgStatusFilter {
  all('Todos'),
  downloaded('Descargados'),
  downloading('En descarga'),
  pending('Sin descargar');

  const TgStatusFilter(this.label);

  final String label;

  bool matches(TgFile f) => switch (this) {
    TgStatusFilter.all => true,
    TgStatusFilter.downloaded => f.completed,
    TgStatusFilter.downloading => f.downloading && !f.completed,
    TgStatusFilter.pending => !f.completed && !f.downloading,
  };
}

final RegExp _episodePattern = RegExp(
  r'(?:\b|_)(?:s(\d{1,2})[ ._-]?e(\d{1,3})|(\d{1,2})x(\d{1,3}))(?:\b|_)',
  caseSensitive: false,
);

final RegExp _bookExtension = RegExp(
  r'\.(pdf|epub|mobi|azw3?|cbz|cbr|djvu|fb2)$',
  caseSensitive: false,
);

/// Solo número de episodio, sin temporada: "E15", "Ep 3", "Cap 05",
/// "Capítulo 5", "Episodio 2" (se toma como temporada 1).
final RegExp _episodeOnlyPattern = RegExp(
  r'(?:^|[\s._\-\[(])(?:e|ep|cap|cap[ií]tulo|episodio)[\s._\-]?(\d{1,3})(?=$|[\s._\-\])@])',
  caseSensitive: false,
);

/// Temporada, episodio y dónde empieza la marca en el nombre del archivo.
({int season, int episode, int start})? _parseEpisode(String name) {
  final m = _episodePattern.firstMatch(name);
  if (m != null) {
    return (
      season: int.parse(m.group(1) ?? m.group(3)!),
      episode: int.parse(m.group(2) ?? m.group(4)!),
      start: m.start,
    );
  }
  final e = _episodeOnlyPattern.firstMatch(name);
  if (e != null) {
    return (season: 1, episode: int.parse(e.group(1)!), start: e.start);
  }
  return null;
}

/// Sección de un archivo: la categoría del catálogo si el bot lo envió con
/// el gestor de descargas; si no (archivos antiguos del chat), se deduce
/// por el tipo y el nombre.
TgSection sectionOf(TgFile f) {
  final key = f.catalog?.categoryKey;
  if (key != null) {
    for (final s in TgSection.values) {
      if (s.categoryKey == key) return s;
    }
  }
  if (f.kind == TgFileKind.audio) return TgSection.music;
  if (_bookExtension.hasMatch(f.name)) return TgSection.books;
  final isVideo =
      f.kind == TgFileKind.video ||
      RegExp(
        r'\.(mp4|mkv|avi|mov|webm|m4v|ts)$',
        caseSensitive: false,
      ).hasMatch(f.name);
  if (!isVideo) {
    return RegExp(
          r'\.(mp3|m4a|flac|ogg|opus|wav)$',
          caseSensitive: false,
        ).hasMatch(f.name)
        ? TgSection.music
        : TgSection.other;
  }
  return _parseEpisode(f.name) != null ? TgSection.series : TgSection.movies;
}

/// Temporada y episodio de un archivo: los del catálogo o, si no hay, los
/// del nombre ("1x07", "S01E07").
({int season, int episode})? episodeOf(TgFile f) {
  final c = f.catalog;
  if (c?.season != null && c?.episode != null) {
    return (season: c!.season!, episode: c.episode!);
  }
  final p = _parseEpisode(f.name);
  return p == null ? null : (season: p.season, episode: p.episode);
}

/// Nombre de la serie: el del catálogo o el nombre del archivo hasta el
/// "1x07" / "S01E07" (sin puntos ni guiones bajos).
String seriesTitleOf(TgFile f) {
  final title = f.catalog?.title;
  if (title != null && title.isNotEmpty) return title;
  final name = f.name;
  final p = _parseEpisode(name);
  final raw = p == null
      ? name.replaceFirst(RegExp(r'\.[^.]+$'), '')
      : name.substring(0, p.start);
  final clean = raw
      // Etiquetas de canales ("@Cineclubar") y corchetes de grupos.
      .replaceAll(RegExp(r'@\w+'), ' ')
      .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
      .replaceAll(RegExp(r'[._]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[\s\-–]+$'), '')
      .trim();
  return clean.isEmpty ? name : clean;
}

/// Serie con sus episodios descargables.
@immutable
class TgSeriesGroup {
  const TgSeriesGroup({required this.title, required this.episodes});

  final String title;

  /// Ordenados por temporada y episodio.
  final List<TgFile> episodes;

  String? get poster => episodes
      .map((e) => e.catalog?.poster)
      .firstWhere((p) => p != null && p.isNotEmpty, orElse: () => null);

  int get downloadedCount => episodes.where((e) => e.completed).length;
  int get totalSize => episodes.fold(0, (s, e) => s + e.size);
}

/// Agrupa episodios por serie (las series en el orden en que llegó su
/// último episodio; los episodios por temporada y número).
List<TgSeriesGroup> groupSeries(List<TgFile> files) {
  final groups = <String, List<TgFile>>{};
  for (final f in files) {
    groups.putIfAbsent(seriesTitleOf(f).toLowerCase(), () => []).add(f);
  }
  return [
    for (final list in groups.values)
      TgSeriesGroup(
        title: seriesTitleOf(list.first),
        episodes: [...list]
          ..sort((a, b) {
            final ea = episodeOf(a), eb = episodeOf(b);
            if (ea == null || eb == null) return a.date.compareTo(b.date);
            final s = ea.season.compareTo(eb.season);
            return s != 0 ? s : ea.episode.compareTo(eb.episode);
          }),
      ),
  ];
}

String _fold(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áàä]'), 'a')
    .replaceAll(RegExp('[éèë]'), 'e')
    .replaceAll(RegExp('[íìï]'), 'i')
    .replaceAll(RegExp('[óòö]'), 'o')
    .replaceAll(RegExp('[úùü]'), 'u')
    .replaceAll('ñ', 'n');

/// Archivos de [section] que pasan el buscador y el filtro de estado.
/// El buscador ignora mayúsculas y tildes y mira el título del catálogo,
/// el nombre del archivo y el nombre de la serie.
List<TgFile> filterFiles(
  List<TgFile> files, {
  required TgSection section,
  String query = '',
  TgStatusFilter status = TgStatusFilter.all,
}) {
  final words = _fold(query.trim())
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  return [
    for (final f in files)
      if (sectionOf(f) == section && status.matches(f))
        if (words.isEmpty ||
            words.every(
              (w) =>
                  _fold('${f.title} ${f.name} ${seriesTitleOf(f)}').contains(w),
            ))
          f,
  ];
}

/// Cuántos archivos hay en cada sección (solo las que tienen alguno, en
/// el orden de [TgSection]).
Map<TgSection, int> sectionCounts(List<TgFile> files) {
  final counts = <TgSection, int>{};
  for (final f in files) {
    final s = sectionOf(f);
    counts[s] = (counts[s] ?? 0) + 1;
  }
  return {
    for (final s in TgSection.values)
      if ((counts[s] ?? 0) > 0) s: counts[s]!,
  };
}
