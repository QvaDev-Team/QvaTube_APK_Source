/// Modelo de usuario de la sesión.
///
/// `doc/openapi.json` no define esquemas de respuesta (solo descripciones),
/// por lo que el parseo es tolerante: se aceptan varias claves habituales.
class AuthUser {
  const AuthUser({
    this.id,
    this.email,
    this.displayName,
    this.avatarUrl,
    this.plan,
    this.telegramLinked = false,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    final source = user is Map ? Map<String, dynamic>.from(user) : json;

    String? readString(List<String> keys) {
      for (final key in keys) {
        final value = source[key];
        if (value is String && value.isNotEmpty) return value;
        if (value is num) return value.toString();
      }
      return null;
    }

    return AuthUser(
      id: readString(const ['id', 'user_id', 'userId']),
      email: readString(const ['email', 'mail']),
      displayName: readString(const [
        'display_name',
        'displayName',
        'name',
        'username',
      ]),
      avatarUrl: readString(const [
        'avatar',
        'avatar_url',
        'avatarUrl',
        'photo_url',
        'photo',
      ]),
      plan: readString(const ['plan', 'plan_key', 'planKey', 'subscription']),
      telegramLinked: switch (source['telegram_linked'] ?? source['telegramLinked']) {
        final bool value => value,
        final num value => value != 0,
        final String value => value.toLowerCase() == 'true',
        _ => false,
      },
    );
  }

  final String? id;
  final String? email;
  final String? displayName;
  final String? avatarUrl;
  final String? plan;
  final bool telegramLinked;

  String get name => (displayName?.trim().isNotEmpty ?? false)
      ? displayName!.trim()
      : (email?.split('@').first ?? 'Invitado');

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return 'Q';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  AuthUser copyWith({
    String? displayName,
    String? avatarUrl,
    String? plan,
    bool? telegramLinked,
  }) {
    return AuthUser(
      id: id,
      email: email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      plan: plan ?? this.plan,
      telegramLinked: telegramLinked ?? this.telegramLinked,
    );
  }
}

/// Estado de la verificación por Telegram (gate anti-abuso, spec §6.9).
enum TelegramVerifyStatus { pending, confirmed, failed, expired }

/// Resultado de iniciar/consultar la verificación por Telegram.
class TelegramVerification {
  const TelegramVerification({
    this.token,
    this.deepLink,
    this.status = TelegramVerifyStatus.pending,
  });

  factory TelegramVerification.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] ?? json['state'] ?? '').toString().toLowerCase();
    final status = switch (rawStatus) {
      'confirmed' || 'verified' || 'ok' => TelegramVerifyStatus.confirmed,
      'failed' || 'error' || 'rejected' => TelegramVerifyStatus.failed,
      'expired' || 'timeout' => TelegramVerifyStatus.expired,
      _ => TelegramVerifyStatus.pending,
    };

    return TelegramVerification(
      token: (json['token'] ?? json['verification_token']) as String?,
      deepLink: (json['deep_link'] ?? json['deepLink'] ?? json['bot_link']) as String?,
      status: status,
    );
  }

  final String? token;
  final String? deepLink;
  final TelegramVerifyStatus status;
}
