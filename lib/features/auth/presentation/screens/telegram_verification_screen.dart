import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/platform/device_channel.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/otp_code_input.dart';
import '../../data/auth_repository.dart';
import '../providers/auth_controller.dart';
import '../providers/auth_providers.dart';
import '../widgets/auth_scaffold.dart';

/// Verificación de Telegram obligatoria (gate anti-abuso, spec §6.9).
///
/// El router manda aquí a toda cuenta con `telegram_linked == false` y no la
/// deja salir hasta verificar o cerrar sesión. Mismo flujo que `verify.js`
/// de la web:
///   1. `POST /api/auth/verify/start` -> abre el deep link del bot.
///   2. Sondea `GET /api/auth/verify/status?token=` hasta `sent: true` (el
///      usuario tocó "Iniciar" y el bot le mandó el código).
///   3. Código de 6 dígitos -> `POST /api/auth/verify/confirm` -> `{user}`.
class TelegramVerificationScreen extends ConsumerStatefulWidget {
  const TelegramVerificationScreen({super.key});

  @override
  ConsumerState<TelegramVerificationScreen> createState() =>
      _TelegramVerificationScreenState();
}

enum _Step { open, waiting, code }

class _TelegramVerificationScreenState
    extends ConsumerState<TelegramVerificationScreen>
    with WidgetsBindingObserver {
  static const Duration _pollInterval = Duration(milliseconds: 2500);
  static const int _resendCooldownSeconds = 20;

  _Step _step = _Step.open;
  String? _token;
  String? _deepLink;
  bool _working = false;
  bool _hasError = false;
  String? _error;
  Timer? _poller;
  Timer? _cooldownTimer;
  int _resendCooldown = 0;

  /// Cambia la clave del campo OTP para vaciarlo tras un código incorrecto.
  int _otpGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver de Telegram se consulta enseguida, sin esperar al timer.
    if (state == AppLifecycleState.resumed && _step == _Step.waiting) {
      _poll();
    }
  }

  void _stopPolling() {
    _poller?.cancel();
    _poller = null;
  }

  Future<void> _startVerification() async {
    _stopPolling();
    setState(() {
      _working = true;
      _error = null;
      _hasError = false;
    });
    try {
      final verification = await ref
          .read(authRepositoryProvider)
          .startTelegramVerification();
      final token = verification.token;
      final link = verification.deepLink;
      if (token == null || link == null || link.isEmpty) {
        throw const ApiException('No se pudo iniciar la verificación.');
      }
      if (!mounted) return;
      setState(() {
        _working = false;
        _token = token;
        _deepLink = link;
        _step = _Step.waiting;
      });
      await DeviceChannel.openUrl(link);
      _poller = Timer.periodic(_pollInterval, (_) => _poll());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _step = _Step.open;
        _error = authErrorMessage(error);
      });
    }
  }

  Future<void> _poll() async {
    final token = _token;
    if (!mounted || token == null || _step != _Step.waiting) return;
    try {
      final status = await ref
          .read(authRepositoryProvider)
          .telegramVerificationStatus(token: token);
      if (!mounted || _step != _Step.waiting) return;
      if (status.sent) {
        _stopPolling();
        _showCodeStep();
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      // Sin red: se sigue sondeando. Respuesta de error: el token expiró.
      if (error.statusCode == null) return;
      _stopPolling();
      setState(() {
        _step = _Step.open;
        _error = 'El enlace expiró. Intenta de nuevo.';
      });
    } catch (_) {
      // Best-effort: el siguiente tick reintenta.
    }
  }

  void _showCodeStep() {
    setState(() {
      _step = _Step.code;
      _error = null;
      _hasError = false;
      _otpGeneration++;
      _resendCooldown = _resendCooldownSeconds;
    });
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendCooldown--);
      if (_resendCooldown <= 0) timer.cancel();
    });
  }

  Future<void> _confirm(String code) async {
    final token = _token;
    if (code.length < 6 || token == null || _working) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _hasError = false;
      _error = null;
    });
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .confirmTelegramVerification(token: token, code: code);
      if (!mounted) return;
      _cooldownTimer?.cancel();
      // El router saca al usuario de esta pantalla en cuanto queda vinculado.
      ref
          .read(authControllerProvider.notifier)
          .completeTelegramVerification(result.user);
    } on ApiException catch (error) {
      if (!mounted) return;
      final reason = error.details?['reason']?.toString();
      if (reason == 'expired' || reason == 'already_linked') {
        _cooldownTimer?.cancel();
        setState(() {
          _working = false;
          _step = _Step.open;
          _error = reason == 'expired'
              ? 'El código expiró. Genera uno nuevo.'
              : 'Esa cuenta de Telegram ya está vinculada a otra cuenta. '
                    'Solo se permite una cuenta por cada Telegram.';
        });
        return;
      }
      setState(() {
        _working = false;
        _hasError = true;
        _otpGeneration++;
        _error = authErrorMessage(error);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _hasError = true;
        _error = authErrorMessage(error);
      });
    }
  }

  void _backToOpen() {
    _stopPolling();
    _cooldownTimer?.cancel();
    setState(() {
      _step = _Step.open;
      _error = null;
      _hasError = false;
    });
  }

  Future<void> _logout() async {
    _stopPolling();
    _cooldownTimer?.cancel();
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Paso obligatorio: el botón atrás no lo salta.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step != _Step.open) _backToOpen();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: AuthBackdrop(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_step != _Step.open)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _working ? null : _backToOpen,
                            icon: const Icon(Icons.arrow_back, size: 16),
                            label: const Text('Volver'),
                          ),
                        ),
                      const SizedBox(height: 8),
                      _TelegramBadge(spinning: _step == _Step.waiting),
                      const SizedBox(height: 18),
                      ..._buildStep(context),
                      const SizedBox(height: 28),
                      TextButton(
                        onPressed: _working ? null : _logout,
                        child: Text(
                          'Cerrar sesión',
                          style: AppTextStyles.body(
                            fontSize: 12.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildStep(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.headlineLarge;
    final hintStyle = AppTextStyles.body(
      fontSize: 12.5,
      color: AppColors.textSecondary,
      height: 1.45,
    );
    final error = _error == null
        ? const <Widget>[]
        : [AuthNotice(message: _error!), const SizedBox(height: 16)];

    switch (_step) {
      case _Step.open:
        return [
          Text(
            'Verifica tu cuenta',
            textAlign: TextAlign.center,
            style: titleStyle,
          ),
          const SizedBox(height: 8),
          Text(
            'Por seguridad, toda cuenta necesita confirmarse una vez con '
            'Telegram. Así evitamos cuentas falsas y abuso del servicio.',
            textAlign: TextAlign.center,
            style: hintStyle,
          ),
          const SizedBox(height: 24),
          ...error,
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _working ? null : _startVerification,
              icon: _working
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accentInk,
                      ),
                    )
                  : const Icon(Icons.telegram, size: 20),
              label: Text(
                _working ? 'Abriendo Telegram...' : 'Verificar con Telegram',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Se abrirá Telegram. Toca "Iniciar" ahí y vuelve a esta pantalla.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body(
              fontSize: 11.5,
              color: AppColors.textMuted,
            ),
          ),
        ];
      case _Step.waiting:
        return [
          Text(
            'Esperando Telegram...',
            textAlign: TextAlign.center,
            style: titleStyle,
          ),
          const SizedBox(height: 8),
          Text(
            'Toca "Iniciar" en el chat del bot. En cuanto lo hagas te '
            'mandamos el código y esta pantalla avanza sola.',
            textAlign: TextAlign.center,
            style: hintStyle,
          ),
          const SizedBox(height: 24),
          ...error,
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _deepLink == null
                  ? null
                  : () => DeviceChannel.openUrl(_deepLink!),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Volver a abrir Telegram'),
            ),
          ),
        ];
      case _Step.code:
        return [
          Text(
            'Ingresa el código',
            textAlign: TextAlign.center,
            style: titleStyle,
          ),
          const SizedBox(height: 8),
          Text(
            'Te lo mandamos por Telegram. No lo compartas con nadie.',
            textAlign: TextAlign.center,
            style: hintStyle,
          ),
          const SizedBox(height: 24),
          ...error,
          Center(
            child: OtpCodeInput(
              key: ValueKey(_otpGeneration),
              hasError: _hasError,
              enabled: !_working,
              onChanged: (_) {
                if (_hasError) setState(() => _hasError = false);
              },
              onCompleted: _confirm,
            ),
          ),
          const SizedBox(height: 20),
          if (_working)
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _resendCooldown > 0 ? null : _startVerification,
              child: Text(
                _resendCooldown > 0
                    ? 'Reenviar código (${_resendCooldown}s)'
                    : '¿No te llegó? Reenviar código',
              ),
            ),
        ];
    }
  }
}

class _TelegramBadge extends StatelessWidget {
  const _TelegramBadge({this.spinning = false});

  final bool spinning;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 72,
        height: 72,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (spinning)
              const SizedBox(
                width: 72,
                height: 72,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.telegram,
                ),
              ),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.telegram.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.telegram),
              ),
              child: const Icon(
                Icons.telegram,
                color: AppColors.telegram,
                size: 30,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
