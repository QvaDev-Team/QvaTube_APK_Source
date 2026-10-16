abstract final class FavoritesProgressEndpoints {
  const FavoritesProgressEndpoints._();

  /// GET: List user's favorite content items
  /// POST: Set/unset favorite on a single file
  static const String favorites = '/api/favorites';

  /// POST: Set/unset favorite on a series/album group
  static const String seriesFavorites = '/api/favorites/series';

  /// GET: Get playback position of a file
  /// POST: Save playback position
  /// DELETE: Delete playback position
  static const String progress = '/api/progress';

  /// GET: Continue watching list
  static const String continueWatching = '/api/continue-watching';

  /// POST: Mark a single file as watched
  static const String watched = '/api/watched';

  /// POST: Mark an entire series as watched
  static const String seriesWatched = '/api/watched/series';
}

