import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/platform/device_channel.dart';
import '../../core/storage/app_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../auth/presentation/providers/auth_controller.dart';
import '../share/received_store.dart';
import '../share/wifi_share_screen.dart';
import 'storage_location_screen.dart';
import 'tdlib/td_library.dart';
import 'telegram_delivery.dart';
import 'telegram_files.dart';
import 'telegram_files_list.dart';
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
    // Lo recibido por Wi-Fi aparece al momento (también sin Telegram).
    ReceivedStore.instance.addListener(_onChanged);
    // `telegram_user_id` llega en /api/auth/me; si la sesión guardada no lo
    // tiene (verificó hace poco o venía de una versión vieja), se refresca
    // para poder comparar las cuentas.
    final user = ref.read(authControllerProvider).user;
    if (user != null && user.telegramLinked && user.telegramUserId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(authControllerProvider.notifier).restoreSession();
        }
      });
    }
  }

  @override
  void dispose() {
    _tg.removeListener(_onChanged);
    ReceivedStore.instance.removeListener(_onChanged);
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

  /// Panel "Cuenta de Telegram": con qué cuenta está conectada la app y
  /// si coincide con la verificada en QvaTube.
  void _showAccountSheet() {
    final user = _tg.user;
    final match = telegramAccountMatch(ref.read(authControllerProvider).user);
    _sheet(
      icon: LucideIcons.circleUser,
      iconColor: match == TgAccountMatch.different
          ? AppColors.danger
          : AppColors.success,
      title: 'Cuenta de Telegram',
      children: [
        _sheetRow(
          'Conectado como',
          user == null || user.name.isEmpty ? 'Telegram' : user.name,
        ),
        if (user != null && user.phone.isNotEmpty)
          _sheetRow('Teléfono', '+${user.phone}'),
        _sheetRow(
          'Cuenta verificada en QvaTube',
          switch (match) {
            TgAccountMatch.same => 'Sí, es la misma',
            TgAccountMatch.different => 'No, es otra cuenta',
            _ => 'Comprobando…',
          },
          color: switch (match) {
            TgAccountMatch.same => AppColors.success,
            TgAccountMatch.different => AppColors.danger,
            _ => AppColors.textSecondary,
          },
        ),
        const SizedBox(height: 12),
        Text(
          match == TgAccountMatch.different
              ? 'El bot envía tus descargas a la cuenta que verificaste en '
                    'QvaTube. Desconecta y entra con esa cuenta para verlas '
                    'aquí.'
              : 'QvaTube solo lee el chat del bot de QvaTube. La sesión '
                    'aparece en Telegram → Ajustes → Dispositivos y la puedes '
                    'cerrar desde ahí cuando quieras.',
          style: AppTextStyles.body(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  /// Panel "Desconectar Telegram" con la confirmación dentro.
  void _showDisconnectSheet() {
    _sheet(
      icon: LucideIcons.unlink,
      iconColor: AppColors.danger,
      title: 'Desconectar Telegram',
      children: [
        Text(
          'Se cerrará la sesión de Telegram en QvaTube y se pausarán las '
          'descargas en curso. Lo que ya descargaste sigue en tu teléfono '
          'y tus archivos siguen en el chat del bot.',
          style: AppTextStyles.body(
            fontSize: 13.5,
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: () async {
            Navigator.of(context).pop();
            TelegramFiles.instance.clear();
            await _tg.disconnect();
          },
          icon: const Icon(LucideIcons.unlink, size: 18),
          label: const Text('Desconectar'),
        ),
        const SizedBox(height: 8),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  void _sheet({
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<Widget> children,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceSecondary,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: iconColor, size: 26),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: AppTextStyles.body(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetRow(String label, String value, {Color? color}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.body(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppTextStyles.body(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(LucideIcons.arrowLeft),
        ),
        title: const Text('Gestor de descargas'),
        // Con Telegram conectado, la cuenta y "Desconectar" van en dos
        // botones arriba a la derecha (cada uno abre su panel) para dejar
        // todo el espacio a los archivos.
        actions: [
          // Compartir por Wi-Fi: también sin Telegram conectado (para
          // recibir de otro teléfono).
          IconButton(
            tooltip: 'Compartir por Wi-Fi',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const WifiShareScreen()),
            ),
            icon: const Icon(LucideIcons.wifi, size: 21),
          ),
          // Dónde se guardan los archivos: memoria interna o tarjeta SD.
          if (Platform.isAndroid)
            IconButton(
              tooltip: 'Ubicación de almacenamiento',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const StorageLocationScreen(),
                ),
              ),
              icon: const Icon(Icons.sd_storage_outlined, size: 21),
            ),
          if (_tg.stage == TgStage.ready) ...[
            IconButton(
              tooltip: 'Cuenta de Telegram',
              onPressed: _showAccountSheet,
              icon: _AccountIcon(
                warning:
                    telegramAccountMatch(
                      ref.watch(authControllerProvider).user,
                    ) ==
                    TgAccountMatch.different,
              ),
            ),
            IconButton(
              tooltip: 'Desconectar Telegram',
              onPressed: _showDisconnectSheet,
              icon: const Icon(LucideIcons.unlink, size: 21),
            ),
          ],
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          ..._body(),
          // Sin Telegram conectado, lo recibido por Wi-Fi se ve igual.
          if (_tg.stage != TgStage.ready &&
              ReceivedStore.instance.files.isNotEmpty) ...[
            const SizedBox(height: 24),
            const TelegramFilesList(),
          ],
        ],
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
            LucideIcons.info,
            DeviceChannel.isDesktop
                ? 'En la computadora, tus descargas siguen llegando al bot de '
                      'Telegram. Aquí puedes recibir películas, series y '
                      'música desde un teléfono con QvaTube por Wi-Fi, y verlas '
                      'sin conexión.'
                : 'Telegram en la app no está disponible en este dispositivo. '
                      'Puedes seguir recibiendo tus descargas en el bot de '
                      'Telegram como siempre.',
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const WifiShareScreen(initialTab: 1),
              ),
            ),
            icon: const Icon(LucideIcons.wifi, size: 20),
            label: const Text('Compartir por Wi-Fi'),
          ),
        ];
      case TgStage.disconnected:
      case TgStage.error:
        final mb = (TdLibrary.current?.gzBytes ?? 10000000) / 1048576;
        return [
          _info(
            LucideIcons.send,
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
            icon: const Icon(LucideIcons.link, size: 18),
            label: const Text('Conectar Telegram'),
          ),
          ?errorText,
        ];
      case TgStage.installing:
        final mb = (TdLibrary.current?.gzBytes ?? 0) / 1048576;
        return [
          _info(LucideIcons.download, 'Descargando el componente de Telegram…'),
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
        final match = telegramAccountMatch(
          ref.watch(authControllerProvider).user,
        );
        return [
          // Este aviso sí se queda a la vista: con otra cuenta los archivos
          // no llegarían aquí.
          if (match == TgAccountMatch.different) ...[
            _info(
              LucideIcons.triangleAlert,
              'Esta no es la cuenta de Telegram que verificaste en QvaTube. '
              'El bot envía tus descargas a la cuenta verificada, así que no '
              'aparecerán aquí. Desconecta y entra con esa cuenta.',
              color: AppColors.danger,
            ),
            const SizedBox(height: 14),
          ],
          const TelegramFilesList(),
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

/// Icono de la cuenta con un punto verde (conectada) o rojo (otra cuenta).
class _AccountIcon extends StatelessWidget {
  const _AccountIcon({required this.warning});

  final bool warning;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(LucideIcons.circleUser, size: 22),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: warning ? AppColors.danger : AppColors.success,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
