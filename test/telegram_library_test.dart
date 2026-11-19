import 'package:flutter_test/flutter_test.dart';
import 'package:qvatube_apk/features/telegram/telegram_files.dart';
import 'package:qvatube_apk/features/telegram/telegram_library.dart';

TgFile _file(
  String name, {
  TgFileKind kind = TgFileKind.video,
  Map<String, dynamic>? catalog,
  bool completed = false,
  int id = 1,
}) {
  final f = TgFile(
    messageId: id,
    fileId: id,
    name: name,
    kind: kind,
    date: DateTime(2026, 11, 18).add(Duration(minutes: id)),
  )..completed = completed;
  if (catalog != null) f.catalog = TgCatalogInfo.fromJson(catalog);
  return f;
}

void main() {
  test('la categoría del catálogo manda sobre el nombre', () {
    expect(
      sectionOf(
        _file('x.mp4', catalog: {'title': 'X', 'category_key': 'anime'}),
      ),
      TgSection.anime,
    );
    expect(
      sectionOf(
        _file('x.mp4', catalog: {'title': 'X', 'category_key': 'movie'}),
      ),
      TgSection.movies,
    );
  });

  test('sin catálogo se deduce por tipo y nombre', () {
    expect(sectionOf(_file('a.m4a', kind: TgFileKind.audio)), TgSection.music);
    expect(
      sectionOf(_file('libro.epub', kind: TgFileKind.document)),
      TgSection.books,
    );
    expect(sectionOf(_file('The Bear 2x05.mp4')), TgSection.series);
    expect(sectionOf(_file('Dark.S01E03.720p.mkv')), TgSection.series);
    final pitt = _file('The Pitt E15 @Cineclubar.mkv');
    expect(sectionOf(pitt), TgSection.series);
    expect(episodeOf(pitt), (season: 1, episode: 15));
    expect(seriesTitleOf(pitt), 'The Pitt');
    expect(sectionOf(_file('Los Simpson Capítulo 5.mp4')), TgSection.series);
    expect(seriesTitleOf(_file('[Grupo] Naruto - Ep 03.mkv')), 'Naruto');
    expect(sectionOf(_file('Ep1c Movie 2020.mkv')), TgSection.movies);
    expect(
      sectionOf(_file('Pirates Of The Caribbean 2017.mkv')),
      TgSection.movies,
    );
    expect(
      sectionOf(_file('cosa.zip', kind: TgFileKind.document)),
      TgSection.other,
    );
  });

  test('agrupa episodios por serie y los ordena', () {
    final groups = groupSeries([
      _file('The Bear 1x02.mp4', id: 1),
      _file('Dark.S01E01.mkv', id: 2),
      _file('The Bear 1x01.mp4', id: 3),
      _file(
        'The Midnight Gospel 1x07.mp4',
        id: 4,
        catalog: {'title': 'The Midnight Gospel', 'season': 1, 'episode': 7},
      ),
    ]);
    expect(groups.map((g) => g.title), [
      'The Bear',
      'Dark',
      'The Midnight Gospel',
    ]);
    expect(groups.first.episodes.map((e) => e.name), [
      'The Bear 1x01.mp4',
      'The Bear 1x02.mp4',
    ]);
    expect(episodeOf(groups[1].episodes.first), (season: 1, episode: 1));
  });

  test('buscador sin tildes ni mayúsculas y filtro por estado', () {
    final files = [
      _file(
        'Pirates.mkv',
        id: 1,
        completed: true,
        catalog: {
          'title': 'Piratas del Caribe: La venganza de Salazar',
          'category_key': 'movie',
        },
      ),
      _file('Kong.mkv', id: 2),
    ];
    expect(
      filterFiles(
        files,
        section: TgSection.movies,
        query: 'VENGANZA salazar',
      ).map((f) => f.id),
      [1],
    );
    expect(
      filterFiles(
        files,
        section: TgSection.movies,
        query: 'caribe pirates',
      ).length,
      1,
    );
    expect(
      filterFiles(
        files,
        section: TgSection.movies,
        status: TgStatusFilter.pending,
      ).map((f) => f.name),
      ['Kong.mkv'],
    );
    expect(sectionCounts(files), {TgSection.all: 2, TgSection.movies: 2});
    expect(filterFiles(files, section: TgSection.all).length, 2);
  });

  test('agrupa música por artista y álbum', () {
    final groups = groupAlbums([
      _file(
        'Starset - My Demons.mp3',
        id: 1,
        kind: TgFileKind.audio,
        completed: true,
      ),
      _file('STARSET | AD ASTRA.m4a', id: 2, kind: TgFileKind.audio),
      _file(
        'INDUSTRY BABY.mp3',
        id: 3,
        kind: TgFileKind.audio,
        catalog: {
          'title': 'INDUSTRY BABY',
          'artist': 'Lil Nas X',
          'album': 'MONTERO',
          'category_key': 'music',
        },
      ),
    ]);
    expect(groups.length, 2);
    expect(groups[0].title, 'Starset');
    expect(groups[0].tracks.length, 2);
    expect(groups[0].downloadedCount, 1);
    expect(trackTitleOf(groups[0].tracks[0]), 'My Demons');
    expect(trackTitleOf(groups[0].tracks[1]), 'AD ASTRA');
    expect(groups[1].title, 'MONTERO');
    expect(groups[1].artist, 'Lil Nas X');
  });
}

extension on TgFile {
  int get id => messageId;
}
