abstract final class DownloadsEndpoints {
  const DownloadsEndpoints._();

  /// POST: Authorize a single file download (returns Telegram deep link)
  static const String authorize = '/api/download/authorize';

  /// POST: Authorize a full season download (returns Telegram deep link)
  static const String authorizeSeason = '/api/download/authorize-season';
}

