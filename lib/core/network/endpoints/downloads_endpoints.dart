final class DownloadsEndpoints {
  const DownloadsEndpoints();

  /// POST: Authorize a single file download (returns Telegram deep link)
  final String authorize = '/api/download/authorize';

  /// POST: Authorize a full season download (returns Telegram deep link)
  final String authorizeSeason = '/api/download/authorize-season';
}

