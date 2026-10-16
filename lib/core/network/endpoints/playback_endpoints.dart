abstract final class PlaybackEndpoints {
  const PlaybackEndpoints._();

  /// GET: Stream a media file (raw media bytes with HTTP Range 206 support)
  /// Path: `/watch/{chat_id}/{msg_id}`
  static const String watchTemplate = '/watch/{chat_id}/{msg_id}';

  /// Helper to generate the streaming URL for a given media file
  static String watch(int chatId, int msgId) => '/watch/$chatId/$msgId';

  /// GET: Read a book file (cached server-side)
  /// Path: `/read/{chat_id}/{msg_id}`
  static const String readTemplate = '/read/{chat_id}/{msg_id}';

  /// Helper to generate the book reading URL for a given book file
  static String read(int chatId, int msgId) => '/read/$chatId/$msgId';
}

