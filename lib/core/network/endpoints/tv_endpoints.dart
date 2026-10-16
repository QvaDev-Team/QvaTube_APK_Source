abstract final class TvEndpoints {
  const TvEndpoints._();

  /// GET: Viewer counts per TV channel
  static const String viewers = '/api/tv/viewers';

  /// POST: Presence heartbeat for a live TV channel (sent every ~20 s)
  static const String heartbeat = '/api/tv/heartbeat';

  /// POST: Leave a live TV channel
  static const String leave = '/api/tv/leave';
}

