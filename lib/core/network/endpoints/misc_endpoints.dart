abstract final class MiscEndpoints {
  const MiscEndpoints._();

  /// GET: Public client configuration (bot username, WhatsApp URL, payment info)
  static const String config = '/api/config';

  /// GET: Public site statistics
  static const String stats = '/api/stats';

  /// GET: Android APK availability and size in MB
  static const String apkInfo = '/api/apk-info';

  /// GET: Binary download for the Android APK file
  static const String downloadApk = '/download/qvatube.apk';
}

