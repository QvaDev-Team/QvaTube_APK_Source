final class TvEndpoints {
  const TvEndpoints();

  /// GET: Viewer counts per TV channel
  final String viewers = '/api/tv/viewers';

  /// POST: Presence heartbeat for a live TV channel (sent every ~20 s)
  final String heartbeat = '/api/tv/heartbeat';

  /// POST: Leave a live TV channel
  final String leave = '/api/tv/leave';
}

