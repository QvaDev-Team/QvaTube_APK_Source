abstract final class MediaEndpoints {
  const MediaEndpoints._();

  /// GET: Poster image served from the server cache
  /// Path: `/poster/{name}`
  static const String posterTemplate = '/poster/{name}';

  /// Helper to generate the poster image URL
  static String poster(String name) => '/poster/$name';

  /// GET: Music cover image (embedded cover or online lookup)
  /// Path: `/cover/{chat_id}/{msg_id}`
  static const String coverTemplate = '/cover/{chat_id}/{msg_id}';

  /// Helper to generate the music cover image URL
  static String cover(int chatId, int msgId) => '/cover/$chatId/$msgId';

  /// GET: Book cover image generated/cached from the book file
  /// Path: `/bookcover/{chat_id}/{msg_id}`
  static const String bookcoverTemplate = '/bookcover/{chat_id}/{msg_id}';

  /// Helper to generate the book cover image URL
  static String bookcover(int chatId, int msgId) => '/bookcover/$chatId/$msgId';
}

