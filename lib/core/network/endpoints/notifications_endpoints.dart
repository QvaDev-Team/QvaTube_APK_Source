abstract final class NotificationsEndpoints {
  const NotificationsEndpoints._();

  /// GET: List user notifications and unread counter
  static const String notifications = '/api/notifications';

  /// POST: Mark a single notification as read by ID
  static const String read = '/api/notifications/read';

  /// POST: Mark all notifications as read
  static const String readAll = '/api/notifications/read-all';

  /// POST: Delete all notifications
  static const String clearAll = '/api/notifications/clear-all';
}

