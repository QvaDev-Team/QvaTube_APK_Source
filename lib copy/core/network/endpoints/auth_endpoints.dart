final class AuthEndpoints {
  const AuthEndpoints();

  /// POST: Create an email + password account
  final String register = '/api/auth/register';

  /// POST: Log in (sets HttpOnly session cookie `qva_session`)
  final String login = '/api/auth/login';

  /// POST: Invalidate session on server and clear cookie
  final String logout = '/api/auth/logout';

  /// GET: Get logged-in user profile
  final String me = '/api/auth/me';

  /// POST: Upload profile avatar (multipart/form-data)
  /// DELETE: Remove profile photo
  final String avatar = '/api/auth/avatar';

  /// POST: Update user display name
  final String updateName = '/api/auth/update-name';

  /// POST: Request password reset code via Telegram
  final String forgotPassword = '/api/auth/forgot-password';

  /// POST: Reset password using token and verification code
  final String resetPassword = '/api/auth/reset-password';

  /// POST: Generate short code to link account with Telegram
  final String linkCode = '/api/auth/link-code';

  /// POST: Start Telegram verification flow (returns token and deep link)
  final String verifyStart = '/api/auth/verify/start';

  /// POST: Confirm Telegram verification with bot code
  final String verifyConfirm = '/api/auth/verify/confirm';

  /// GET: Poll Telegram verification status by token
  final String verifyStatus = '/api/auth/verify/status';
}

