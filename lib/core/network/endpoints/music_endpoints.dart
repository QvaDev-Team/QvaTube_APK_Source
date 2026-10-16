abstract final class MusicEndpoints {
  const MusicEndpoints._();

  /// GET: All tracks of a music category
  static const String categoryTracks = '/api/category-tracks';

  /// GET: Tracks of an album/artist group
  static const String albumTracks = '/api/album-tracks';
}

