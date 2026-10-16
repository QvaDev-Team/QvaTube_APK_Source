abstract final class AuthEndpoints {
  const AuthEndpoints._();

  /// POST: Create an email + password account
  static const String register = '/api/auth/register';

  /// POST: Log in (sets HttpOnly session cookie `qva_session`)
  static const String login = '/api/auth/login';

  /// POST: Invalidate session on server and clear cookie
  static const String logout = '/api/auth/logout';

  /// GET: Get logged-in user profile
  static const String me = '/api/auth/me';

  /// POST: Upload profile avatar (multipart/form-data)
  /// DELETE: Remove profile photo
  static const String avatar = '/api/auth/avatar';

  /// POST: Update user display name
  static const String updateName = '/api/auth/update-name';

  /// POST: Request password reset code via Telegram
  static const String forgotPassword = '/api/auth/forgot-password';

  /// POST: Reset password using token and verification code
  static const String resetPassword = '/api/auth/reset-password';

  /// POST: Generate short code to link account with Telegram
  static const String linkCode = '/api/auth/link-code';

  /// POST: Start Telegram verification flow (returns token and deep link)
  static const String verifyStart = '/api/auth/verify/start';

  /// POST: Confirm Telegram verification with bot code
  static const String verifyConfirm = '/api/auth/verify/confirm';

  /// GET: Poll Telegram verification status by token
  static const String verifyStatus = '/api/auth/verify/status';
}

