final class MiscEndpoints {
  const MiscEndpoints();

  /// GET: Public client configuration (bot username, WhatsApp URL, payment info)
  final String config = '/api/config';

  /// GET: Public site statistics
  final String stats = '/api/stats';

  /// GET: Android APK availability and size in MB
  final String apkInfo = '/api/apk-info';

  /// GET: Binary download for the Android APK file
  final String downloadApk = '/download/qvatube.apk';
}

