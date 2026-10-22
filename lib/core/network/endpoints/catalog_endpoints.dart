final class CatalogEndpoints {
  const CatalogEndpoints();

  /// GET: List content categories that have at least one mapped channel
  final String categories = '/api/categories';

  /// GET: Main paginated catalog endpoint (movies, series, anime, novelas, books, etc.)
  final String movies = '/api/movies';

  /// GET: Episodes of a series/anime/novela
  final String episodes = '/api/episodes';

  /// GET: Genres of a specific category
  final String genres = '/api/genres';

  /// GET: Genre rows for the home screen
  final String homeGenres = '/api/home-genres';

  /// GET: Metadata (TMDb) of a title
  final String info = '/api/info';

  /// GET: Recommended content for the home screen
  final String recommendations = '/api/recommendations';

  /// GET: Resolve a shared link (cat + id / slug) into a catalog item
  final String resolve = '/api/resolve';

  /// GET: Get a share slug/index for an item
  final String shareIndex = '/api/share-index';

  /// GET: Catalog version integer for offline sync comparison
  final String syncManifest = '/api/sync-manifest';

  /// GET: Full catalog snapshot for offline use
  final String syncCatalogFull = '/api/sync-catalog-full';

  /// GET: Unseen new content counter per category
  final String newContentCounts = '/api/new-content/counts';

  /// POST: Mark new content items as seen
  final String newContentSeen = '/api/new-content/seen';
}

