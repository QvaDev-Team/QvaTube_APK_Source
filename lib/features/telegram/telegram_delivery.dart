import '../auth/domain/auth_models.dart';
import 'telegram_service.dart';

/// Relación entre la cuenta de Telegram conectada en la app y la cuenta
/// verificada en QvaTube (a la que el bot envía los archivos).
enum TgAccountMatch {
  /// Telegram no está conectado en la app.
  notConnected,

  /// No se puede comparar: el servidor no mandó `telegram_user_id` o TDLib
  /// todavía no cargó el usuario.
  unknown,

  /// Es la misma cuenta: el bot envía y la app encuentra el archivo.
  same,

  /// Son cuentas distintas: el bot enviaría los archivos a otro chat.
  different,
}

TgAccountMatch telegramAccountMatch(AuthUser? user) {
  final tg = TelegramService.instance;
  if (!tg.isReady) return TgAccountMatch.notConnected;
  final connected = tg.user?.id;
  final verified = user?.telegramUserId;
  if (connected == null || verified == null) return TgAccountMatch.unknown;
  return connected == verified ? TgAccountMatch.same : TgAccountMatch.different;
}

/// `true` si "Descargar" debe pedir `delivery: "app"` en vez de abrir el
/// bot. Solo cuando se sabe que es la misma cuenta; en cualquier otro caso
/// se sigue con el deep link de siempre.
bool canDeliverToApp(AuthUser? user) =>
    telegramAccountMatch(user) == TgAccountMatch.same;
