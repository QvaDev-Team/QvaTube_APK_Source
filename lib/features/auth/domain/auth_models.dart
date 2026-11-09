/// Modelo de usuario de la sesión.
///
/// Respuesta real de `GET /api/auth/me`:
/// ```json
/// {"user": {"id": 1779, "email": "...", "display_name": "...",
///   "telegram_linked": false, "plan": "free", "plan_expires_at": null,
///   "referral_code": "LNL9P9", "avatar_url": null}}
/// ```
class AuthUser {
  const AuthUser({
    this.id,
    this.email,
    this.displayName,
    this.avatarUrl,
    this.plan,
    this.planExpiresAt,
    this.referralCode,
    this.telegramLinked = false,
    this.creator,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    final source = rawUser is Map
        ? Map<String, dynamic>.from(rawUser)
        : Map<String, dynamic>.from(json);

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
        'avatar_url',
        'avatarUrl',
        'avatar',
        'photo_url',
      ]),
      plan: readString(const ['plan', 'plan_key', 'planKey', 'subscription']),
      planExpiresAt: readString(const ['plan_expires_at', 'planExpiresAt']),
      referralCode: readString(const [
        'referral_code',
        'referralCode',
        'invite_code',
      ]),
      telegramLinked: switch (source['telegram_linked'] ??
          source['telegramLinked']) {
        final bool value => value,
        final num value => value != 0,
        final String value => value.toLowerCase() == 'true',
        _ => false,
      },
      creator: source['creator'] is Map
          ? CreatorInfo.fromJson(
              Map<String, dynamic>.from(source['creator'] as Map),
            )
          : null,
    );
  }

  final String? id;
  final String? email;
  final String? displayName;
  final String? avatarUrl;
  final String? plan;
  final String? planExpiresAt;
  final String? referralCode;
  final bool telegramLinked;

  /// Código de creador oficial (`user.creator`). `null` para casi todos los
  /// usuarios y cuando el admin retira el código: decide si hay Modo creador.
  final CreatorInfo? creator;

  String get name => (displayName?.trim().isNotEmpty ?? false)
      ? displayName!.trim()
      : (email?.split('@').first ?? 'Invitado');

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return 'Q';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  AuthUser copyWith({
    String? displayName,
    String? avatarUrl,
    String? plan,
    String? planExpiresAt,
    bool? telegramLinked,
  }) {
    return AuthUser(
      id: id,
      email: email,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      plan: plan ?? this.plan,
      planExpiresAt: planExpiresAt ?? this.planExpiresAt,
      referralCode: referralCode,
      telegramLinked: telegramLinked ?? this.telegramLinked,
      creator: creator,
    );
  }
}

/// `user.creator` de login/registro/me: `{"code": "ALEX", "rate": 0.1}`.
class CreatorInfo {
  const CreatorInfo({required this.code, required this.rate});

  factory CreatorInfo.fromJson(Map<String, dynamic> json) => CreatorInfo(
    code: json['code']?.toString() ?? '',
    rate: (json['rate'] as num?)?.toDouble() ?? 0.1,
  );

  final String code;

  /// Fracción de comisión (0.1 = 10 %).
  final double rate;
}

/// Estado de la verificación por Telegram (gate anti-abuso, spec §6.9).
enum TelegramVerifyStatus { pending, confirmed, failed, expired }

/// Resultado de iniciar/consultar la verificación por Telegram.
///
/// `POST /api/auth/verify/start` -> `{"token": "...", "deep_link": "..."}`.
class TelegramVerification {
  const TelegramVerification({
    this.token,
    this.deepLink,
    this.status = TelegramVerifyStatus.pending,
    this.reason,
    this.sent = false,
    this.user,
  });

  factory TelegramVerification.fromJson(Map<String, dynamic> json) {
    final rawStatus = (json['status'] ?? json['state'] ?? '')
        .toString()
        .toLowerCase();
    final status = switch (rawStatus) {
      'confirmed' || 'verified' || 'ok' => TelegramVerifyStatus.confirmed,
      'failed' || 'error' || 'rejected' => TelegramVerifyStatus.failed,
      'expired' || 'timeout' => TelegramVerifyStatus.expired,
      _ => TelegramVerifyStatus.pending,
    };

    return TelegramVerification(
      token: (json['token'] ?? json['verification_token']) as String?,
      deepLink:
          (json['deep_link'] ?? json['deepLink'] ?? json['bot_link'])
              as String?,
      status: status,
      reason: json['reason'] as String?,
      // `GET /api/auth/verify/status` -> `{"sent": true}` en cuanto el
      // usuario tocó "Iniciar" en el bot y este le mandó el código.
      sent: json['sent'] == true,
      // `POST /api/auth/verify/confirm` -> `{"user": {...}}` al verificar.
      user: json['user'] is Map ? AuthUser.fromJson(json) : null,
    );
  }

  final String? token;
  final String? deepLink;
  final TelegramVerifyStatus status;
  final String? reason;
  final bool sent;
  final AuthUser? user;
}

/// Código corto para vincular la cuenta con Telegram.
///
/// `POST /api/auth/link-code` -> `{"code": "5B291F41", "expires_in": 600}`.
class TelegramLinkCode {
  const TelegramLinkCode({this.code, this.expiresIn});

  factory TelegramLinkCode.fromJson(Map<String, dynamic> json) {
    return TelegramLinkCode(
      code: json['code'] as String?,
      expiresIn: (json['expires_in'] as num?)?.toInt(),
    );
  }

  final String? code;
  final int? expiresIn;
}
