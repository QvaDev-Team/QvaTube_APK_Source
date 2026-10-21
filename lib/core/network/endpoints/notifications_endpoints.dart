final class NotificationsEndpoints {
  const NotificationsEndpoints();

  /// GET: List user notifications and unread counter
  final String notifications = '/api/notifications';

  /// POST: Mark a single notification as read by ID
  final String read = '/api/notifications/read';

  /// POST: Mark all notifications as read
  final String readAll = '/api/notifications/read-all';

  /// POST: Delete all notifications
  final String clearAll = '/api/notifications/clear-all';
}

