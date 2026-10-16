abstract final class CatalogEndpoints {
  const CatalogEndpoints._();

  /// GET: List content categories that have at least one mapped channel
  static const String categories = '/api/categories';

  /// GET: Main paginated catalog endpoint (movies, series, anime, novelas, books, etc.)
  static const String movies = '/api/movies';

  /// GET: Episodes of a series/anime/novela
  static const String episodes = '/api/episodes';

  /// GET: Genres of a specific category
  static const String genres = '/api/genres';

  /// GET: Genre rows for the home screen
  static const String homeGenres = '/api/home-genres';

  /// GET: Metadata (TMDb) of a title
  static const String info = '/api/info';

  /// GET: Recommended content for the home screen
  static const String recommendations = '/api/recommendations';

  /// GET: Resolve a shared link (cat + id / slug) into a catalog item
  static const String resolve = '/api/resolve';

  /// GET: Get a share slug/index for an item
  static const String shareIndex = '/api/share-index';

  /// GET: Catalog version integer for offline sync comparison
  static const String syncManifest = '/api/sync-manifest';

  /// GET: Full catalog snapshot for offline use
  static const String syncCatalogFull = '/api/sync-catalog-full';

  /// GET: Unseen new content counter per category
  static const String newContentCounts = '/api/new-content/counts';

  /// POST: Mark new content items as seen
  static const String newContentSeen = '/api/new-content/seen';
}

