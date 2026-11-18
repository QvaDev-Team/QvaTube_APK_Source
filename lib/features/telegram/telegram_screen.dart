import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import 'tdlib/td_library.dart';
import 'telegram_service.dart';

/// Cuenta → Telegram: conectar la cuenta de Telegram para gestionar desde
/// QvaTube los archivos que envía el bot.
class TelegramScreen extends ConsumerStatefulWidget {
  const TelegramScreen({super.key});

  @override
  ConsumerState<TelegramScreen> createState() => _TelegramScreenState();
}

class _TelegramScreenState extends ConsumerState<TelegramScreen> {
  final TelegramService _tg = TelegramService.instance;
  final _input = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _tg.addListener(_onChanged);
  }

  @override
  void dispose() {
    _tg.removeListener(_onChanged);
    _input.dispose();
    super.dispose();
  }

  TgStage? _lastStage;
  void _onChanged() {
    if (!mounted) return;
    // Cada paso nuevo empieza con el campo vacío.
    if (_tg.stage != _lastStage) {
      _lastStage = _tg.stage;
      _input.clear();
      _sending = false;
    }
    setState(() {});
  }

  Future<void> _submit() async {
    final value = _input.text;
    if (value.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    switch (_tg.stage) {
      case TgStage.waitPhone:
        await _tg.sendPhone(value);
      case TgStage.waitCode:
        await _tg.sendCode(value);
      case TgStage.waitPassword:
        await _tg.sendPassword(value);
      default:
        break;
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _confirmDisconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desconectar Telegram'),
        content: const Text(
          'Se cerrará la sesión de Telegram en QvaTube. Los archivos que ya '
          'descargaste siguen en tu teléfono.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (ok == true) await _tg.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Telegram'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [..._body()],
      ),
    );
  }

  List<Widget> _body() {
    final stage = _tg.stage;
    final error = _tg.error;
    final errorText = error == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error,
              style: AppTextStyles.body(fontSize: 13, color: AppColors.danger),
            ),
          );

    switch (stage) {
      case TgStage.unavailable:
        return [
          _info(
            Icons.info_outline,
            'Telegram en la app no está disponible en este dispositivo. '
            'Puedes seguir recibiendo tus descargas en el bot de Telegram '
            'como siempre.',
          ),
        ];
      case TgStage.disconnected:
      case TgStage.error:
        final mb = (TdLibrary.current?.gzBytes ?? 10000000) / 1048576;
        return [
          _info(
            Icons.send,
            'Conecta tu cuenta de Telegram para ver y descargar desde QvaTube '
            'los archivos que te envía el bot, sin abrir Telegram.',
          ),
          const SizedBox(height: 14),
          _bullet('QvaTube solo lee el chat del bot de QvaTube.'),
          _bullet(
            'La sesión aparece en Telegram → Ajustes → Dispositivos y la '
            'puedes cerrar cuando quieras.',
          ),
          _bullet(
            'La primera vez se descarga el componente de Telegram '
            '(${mb.toStringAsFixed(1)} MB).',
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _tg.connect(ref.read(sharedPreferencesProvider)),
            icon: const Icon(Icons.link),
            label: const Text('Conectar Telegram'),
          ),
          ?errorText,
        ];
      case TgStage.installing:
        final mb = (TdLibrary.current?.gzBytes ?? 0) / 1048576;
        return [
          _info(Icons.download, 'Descargando el componente de Telegram…'),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: _tg.progress,
            color: AppColors.accent,
            backgroundColor: AppColors.border,
          ),
          const SizedBox(height: 8),
          Text(
            '${(mb * _tg.progress).toStringAsFixed(1)} de '
            '${mb.toStringAsFixed(1)} MB',
            style: AppTextStyles.body(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ];
      case TgStage.starting:
        return [
          const SizedBox(height: 40),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'Conectando con Telegram…',
              style: AppTextStyles.body(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ];
      case TgStage.waitPhone:
        return _step(
          title: 'Tu número de Telegram',
          help: 'Con el código del país, por ejemplo +53 5xxxxxxx.',
          hint: '+53 5…',
          keyboard: TextInputType.phone,
          errorText: errorText,
        );
      case TgStage.waitCode:
        return _step(
          title: 'Código de verificación',
          help: _tg.codeHint ?? 'Escribe el código que te envió Telegram.',
          hint: '12345',
          keyboard: TextInputType.number,
          errorText: errorText,
        );
      case TgStage.waitPassword:
        final hint = _tg.passwordHint;
        return _step(
          title: 'Contraseña de Telegram',
          help: hint == null || hint.isEmpty
              ? 'Tu cuenta tiene verificación en dos pasos.'
              : 'Tu cuenta tiene verificación en dos pasos. Pista: $hint',
          hint: 'Contraseña',
          keyboard: TextInputType.visiblePassword,
          obscure: true,
          errorText: errorText,
        );
      case TgStage.ready:
        final user = _tg.user;
        return [
          _info(
            Icons.check_circle,
            user == null
                ? 'Telegram conectado.'
                : 'Conectado como ${user.name}'
                      '${user.phone.isEmpty ? '' : ' (+${user.phone})'}.',
            color: AppColors.success,
          ),
          const SizedBox(height: 14),
          _bullet(
            'Pronto verás aquí los archivos que te envía el bot para '
            'descargarlos cuando quieras.',
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _confirmDisconnect,
            icon: const Icon(Icons.link_off),
            label: const Text('Desconectar Telegram'),
          ),
        ];
    }
  }

  List<Widget> _step({
    required String title,
    required String help,
    required String hint,
    required TextInputType keyboard,
    bool obscure = false,
    Widget? errorText,
  }) {
    return [
      Text(
        title,
        style: AppTextStyles.body(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      Text(
        help,
        style: AppTextStyles.body(fontSize: 13, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _input,
        autofocus: true,
        keyboardType: keyboard,
        obscureText: obscure,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(hintText: hint),
      ),
      ?errorText,
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: _sending ? null : _submit,
        child: Text(_sending ? 'Comprobando…' : 'Continuar'),
      ),
    ];
  }

  Widget _info(IconData icon, String text, {Color color = AppColors.accent}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body(fontSize: 13.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Icon(Icons.circle, size: 6, color: AppColors.accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.body(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );
}
