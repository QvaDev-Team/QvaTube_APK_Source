import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/otp_code_input.dart';
import '../application/auth_controller.dart';
import 'widgets/auth_scaffold.dart';

/// Recuperación de contraseña en dos pasos.
///
/// 1. `POST /api/auth/forgot-password` con el email (el backend responde con
///    el token de recuperación y envía el código por Telegram).
/// 2. `POST /api/auth/reset-password` con { token, code, new_password }.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _working = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _working = true);

    final token = await ref
        .read(authControllerProvider.notifier)
        .requestPasswordReset(_emailController.text.trim());

    if (!mounted) return;
    if (token == null) {
      setState(() => _working = false);
      return;
    }
    setState(() => _working = false);
    context.go('/restablecer-clave', extra: token);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AuthBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: () => context.go('/login'),
                          icon: const Icon(Icons.arrow_back),
                          style: IconButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(32, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const AuthHeader(
                        title: 'Recuperar contraseña',
                        subtitle: 'Te enviaremos un código por Telegram para '
                            'restablecer tu contraseña.',
                      ),
                      const SizedBox(height: 22),
                      if (authState.error != null) ...[
                        AuthNotice(message: authState.error!),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _requestCode(),
                        autocorrect: false,
                        style: AppTextStyles.body(fontSize: 14),
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                          prefixIcon: Icon(Icons.alternate_email, size: 18),
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) {
                            return 'Ingresa tu correo electrónico.';
                          }
                          if (!RegExp(
                            r'^[\w.+-]+@[\w-]+\.[\w.-]+$',
                          ).hasMatch(text)) {
                            return 'El correo no tiene un formato válido.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _working || authState.isWorking
                              ? null
                              : _requestCode,
                          child: _working || authState.isWorking
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.accentInk,
                                  ),
                                )
                              : const Text('Enviar código'),
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
}

/// Segundo paso: código de 6 dígitos recibido por Telegram + nueva contraseña.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.token});

  final String? token;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String _code = '';
  bool _working = false;
  bool _hasError = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_code.length < 6) {
      setState(() => _hasError = true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _hasError = false;
    });

    final ok = await ref.read(authControllerProvider.notifier).resetPassword(
          token: widget.token ?? '',
          code: _code,
          newPassword: _passwordController.text,
        );
    if (!mounted) return;
    if (!ok) {
      setState(() => _hasError = true);
      return;
    }
    setState(() => _working = false);
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: AuthBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          onPressed: () => context.go('/recuperar-clave'),
                          icon: const Icon(Icons.arrow_back),
                          style: IconButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(32, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const AuthHeader(
                        title: 'Nueva contraseña',
                        subtitle: 'Introduce el código de 6 dígitos que '
                            'recibiste por Telegram.',
                      ),
                      const SizedBox(height: 22),
                      if (authState.error != null) ...[
                        AuthNotice(message: authState.error!),
                        const SizedBox(height: 14),
                      ],
                      OtpCodeInput(
                        hasError: _hasError,
                        onChanged: (value) {
                          if (_hasError) {
                            setState(() => _hasError = false);
                          }
                          setState(() => _code = value);
                        },
                        onCompleted: (_) => _submit(),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        textInputAction: TextInputAction.next,
                        style: AppTextStyles.body(fontSize: 14),
                        decoration: const InputDecoration(
                          labelText: 'Nueva contraseña',
                          helperText: 'Mínimo 8 caracteres',
                          prefixIcon: Icon(Icons.lock_outline, size: 18),
                        ),
                        validator: (value) {
                          if ((value ?? '').isEmpty) {
                            return 'Escribe la nueva contraseña.';
                          }
                          if (value!.length < 8) {
                            return 'Debe tener al menos 8 caracteres.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmController,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        style: AppTextStyles.body(fontSize: 14),
                        decoration: const InputDecoration(
                          labelText: 'Repite la nueva contraseña',
                          prefixIcon: Icon(Icons.lock_reset, size: 18),
                        ),
                        validator: (value) {
                          if (value != _passwordController.text) {
                            return 'Las contraseñas no coinciden.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _working || authState.isWorking
                              ? null
                              : _submit,
                          child: _working || authState.isWorking
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.accentInk,
                                  ),
                                )
                              : const Text('Restablecer contraseña'),
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
}
