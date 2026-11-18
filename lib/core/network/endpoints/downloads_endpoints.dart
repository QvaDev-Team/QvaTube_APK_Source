final class DownloadsEndpoints {
  const DownloadsEndpoints();

  /// POST: Authorize a single file download (returns Telegram deep link)
  final String authorize = '/api/download/authorize';

  /// POST: Authorize a full season download (returns Telegram deep link)
  final String authorizeSeason = '/api/download/authorize-season';

  /// POST: Authorize a full music album download (Ultra; returns deep link)
  final String authorizeAlbum = '/api/download/authorize-album';

  /// POST: Authorize a free selection of files, 1–200 (Ultra; returns deep link)
  final String authorizeBatch = '/api/download/authorize-batch';

  /// GET: Files the bot sent straight to the user's chat (`delivery: "app"`)
  final String telegramFiles = '/api/telegram-files';
}
