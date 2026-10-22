final class FavoritesProgressEndpoints {
  const FavoritesProgressEndpoints();

  /// GET: List user's favorite content items
  /// POST: Set/unset favorite on a single file
  final String favorites = '/api/favorites';

  /// POST: Set/unset favorite on a series/album group
  final String seriesFavorites = '/api/favorites/series';

  /// GET: Get playback position of a file
  /// POST: Save playback position
  /// DELETE: Delete playback position
  final String progress = '/api/progress';

  /// GET: Continue watching list
  final String continueWatching = '/api/continue-watching';

  /// POST: Mark a single file as watched
  final String watched = '/api/watched';

  /// POST: Mark an entire series as watched
  final String seriesWatched = '/api/watched/series';
}

