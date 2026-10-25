import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/otp_code_input.dart';
import '../providers/auth_providers.dart';
import '../../data/auth_repository.dart';
import '../../domain/auth_models.dart';
import '../widgets/auth_scaffold.dart';

/// Puerta de verificación anti-abuso por Telegram (spec §6.9).
///
/// Flujo: `POST /api/auth/verify/start` -> el usuario recibe el código en el
/// bot -> `POST /api/auth/verify/confirm` -> `GET /api/auth/verify/status`
/// para confirmar el estado.
class TelegramVerificationScreen extends ConsumerStatefulWidget {
  const TelegramVerificationScreen({super.key});

  @override
  ConsumerState<TelegramVerificationScreen> createState() =>
      _TelegramVerificationScreenState();
}

class _TelegramVerificationScreenState
    extends ConsumerState<TelegramVerificationScreen> {
  static const Duration _pollInterval = Duration(seconds: 5);

  String _input = '';
  String? _token;
  String? _deepLink;
  bool _hasError = false;
  bool _working = false;
  String? _error;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final verification = await ref
          .read(authRepositoryProvider)
          .startTelegramVerification();
      if (!mounted) return;
      setState(() {
        _working = false;
        _token = verification.token;
        _deepLink = verification.deepLink;
      });
      _startPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = authErrorMessage(error);
      });
    }
  }

  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    if (!mounted) return;
    try {
      final status = await ref
          .read(authRepositoryProvider)
          .telegramVerificationStatus(token: _token);
      if (!mounted) return;
      if (status.status == TelegramVerifyStatus.confirmed) {
        _poller?.cancel();
        setState(() => _error = null);
      }
    } catch (_) {
      // El sondeo es best-effort: no interrumpe el flujo.
    }
  }

  Future<void> _confirm() async {
    if (_input.length < 6 || _token == null) {
      setState(() => _hasError = true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _hasError = false;
      _error = null;
    });
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .confirmTelegramVerification(token: _token!, code: _input);
      if (!mounted) return;
      if (result.status == TelegramVerifyStatus.failed) {
        setState(() {
          _working = false;
          _hasError = true;
          _error = 'El código no es válido. Inténtalo de nuevo.';
        });
        return;
      }
      setState(() => _working = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _hasError = true;
        _error = authErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                    const _TelegramBadge(),
                    const SizedBox(height: 18),
                    Text(
                      'Verifica tu cuenta',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enviamos un código de 6 dígitos a tu Telegram. '
                      'Escríbelo aquí para continuar.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_error != null) ...[
                      AuthNotice(message: _error!),
                      const SizedBox(height: 16),
                    ],
                    Center(
                      child: OtpCodeInput(
                        hasError: _hasError,
                        enabled: !_working,
                        onChanged: (value) {
                          if (_hasError) {
                            setState(() => _hasError = false);
                          }
                          setState(() => _input = value);
                        },
                        onCompleted: (_) => _confirm(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _working ? null : _confirm,
                        child: _working
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accentInk,
                                ),
                              )
                            : const Text('Verificar'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_deepLink != null)
                      TextButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.telegram, size: 18),
                        label: const Text('Abrir el bot de Telegram'),
                      ),
                    TextButton(
                      onPressed: _working ? null : _start,
                      child: const Text('Reenviar código'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TelegramBadge extends StatelessWidget {
  const _TelegramBadge();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: AppColors.telegram.withValues(alpha: 0.14),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.telegram),
        ),
        child: const Icon(Icons.telegram, color: AppColors.telegram, size: 30),
      ),
    );
  }
}
