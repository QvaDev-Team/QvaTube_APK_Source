import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/network/api_client.dart';
import '../../core/platform/device_channel.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../auth/presentation/providers/auth_controller.dart';
import 'creator_api.dart';

/// Panel del programa de creadores oficiales, igual que `creator.js` en la
/// web: código para compartir, contadores, dónde cobrar, solicitud de pago,
/// referidos y pagos. Solo se llega desde el menú si `user.creator != null`.
class CreatorScreen extends ConsumerStatefulWidget {
  const CreatorScreen({super.key});

  @override
  ConsumerState<CreatorScreen> createState() => _CreatorScreenState();
}

class _CreatorScreenState extends ConsumerState<CreatorScreen>
    with WidgetsBindingObserver {
  final _payoutController = TextEditingController();

  CreatorPanel? _panel;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _payoutController.dispose();
    super.dispose();
  }

  // Los montos cambian cuando el admin aprueba pagos: dato fresco al volver.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = _panel == null;
        _error = null;
      });
    }
    try {
      final panel = await ref.read(creatorApiProvider).panel();
      if (!mounted) return;
      final firstLoad = _panel == null;
      setState(() {
        _panel = panel;
        _loading = false;
      });
      if (firstLoad || _payoutController.text.isEmpty) {
        _payoutController.text = panel.payoutInfo;
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404 || e.statusCode == 401) {
        // Código retirado (o sesión caída): fuera el Modo creador.
        await ref.read(authControllerProvider.notifier).restoreSession();
        if (!mounted) return;
        _toast(e.statusCode == 404 ? 'Ya no eres creador oficial.' : e.message);
        Navigator.of(context).maybePop();
        return;
      }
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<String?> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await action();
      if (message != null) _toast(message);
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load(silent: true);
  }

  Future<String?> _savePayoutInfo() async {
    final saved = await ref
        .read(creatorApiProvider)
        .savePayoutInfo(_payoutController.text.trim());
    _payoutController.text = saved;
    return 'Datos de cobro guardados.';
  }

  /// Como la web: guarda primero dónde cobrar y luego solicita, para no
  /// obligar a pulsar "Guardar" antes.
  Future<String?> _requestPayout() async {
    final api = ref.read(creatorApiProvider);
    final info = _payoutController.text.trim();
    if (info != (_panel?.payoutInfo ?? '')) {
      _payoutController.text = await api.savePayoutInfo(info);
    }
    final amount = await api.requestPayout();
    return 'Pago de ${formatCup(amount)} solicitado. Te avisaremos cuando se envíe.';
  }

  Future<String?> _cancelPayout() async {
    final ok = await ref.read(creatorApiProvider).cancelPayout();
    return ok ? 'Solicitud de pago cancelada.' : 'No había ninguna solicitud abierta.';
  }

  Future<void> _share(CreatorPanel panel) async {
    final pct = (panel.rate * 100).round();
    final text = 'Crea tu cuenta en QvaTube con mi código ${panel.code} y '
        'recibe 1 día de Ultra gratis: películas, series, anime, música, '
        'libros y TV en un solo lugar. https://qvatube.hidenplay.net';
    final shared = await DeviceChannel.shareText(text);
    if (!shared) {
      await Clipboard.setData(ClipboardData(text: panel.code));
      _toast('Código copiado ($pct %).');
    }
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
        title: const Text('Modo creador'),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    final panel = _panel;
    if (panel == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? 'No se pudo cargar el panel.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body(fontSize: 13.5),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final pct = (panel.rate * 100).toStringAsFixed(
      panel.rate * 100 % 1 == 0 ? 0 : 1,
    );
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: () => _load(silent: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _codeCard(panel, pct),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _stat('${panel.registered}', 'Registrados')),
              const SizedBox(width: 10),
              Expanded(child: _stat('${panel.buyers}', 'Compraron')),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _stat(formatCup(panel.totalCup), 'Generado en total')),
              const SizedBox(width: 10),
              Expanded(
                child: _stat(
                  formatCup(panel.pendingCup),
                  'Pendiente de cobro',
                  highlight: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _caption('Ya cobrado: ', formatCup(panel.paidCup)),
          if (panel.requestedCup > 0)
            _caption('En proceso de pago: ', formatCup(panel.requestedCup)),
          const SizedBox(height: 18),
          _sectionTitle(LucideIcons.share2, 'Dónde cobrar'),
          const SizedBox(height: 4),
          Text(
            'Tarjeta o teléfono de Transfermóvil donde quieres recibir tus pagos.',
            style: AppTextStyles.body(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _payoutController,
                  maxLength: 120,
                  style: AppTextStyles.mono(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Ej. 9200 1234 5678 9012',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _run(_savePayoutInfo),
                  child: const Text('Guardar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _payoutAction(panel),
          const SizedBox(height: 24),
          _sectionTitle(LucideIcons.user, 'Tus referidos'),
          const SizedBox(height: 8),
          if (panel.referred.isEmpty)
            _empty('Todavía nadie se registró con tu código. ¡Compártelo!')
          else
            for (final r in panel.referred) _referralRow(r),
          const SizedBox(height: 24),
          _sectionTitle(LucideIcons.check, 'Tus pagos'),
          const SizedBox(height: 8),
          if (panel.payouts.isEmpty)
            _empty('Aún no tienes pagos.')
          else
            for (final p in panel.payouts) _payoutRow(p),
          const SizedBox(height: 28),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Volver a modo usuario'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeCard(CreatorPanel panel, String pct) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.star, size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                'TU CÓDIGO DE CREADOR',
                style: AppTextStyles.body(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: panel.code));
                    _toast('Código copiado.');
                  },
                  child: Text(
                    panel.code,
                    style: AppTextStyles.mono(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ).copyWith(letterSpacing: 4),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copiar código',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: panel.code));
                  _toast('Código copiado.');
                },
                icon: const Icon(LucideIcons.copy, size: 18, color: AppColors.textSecondary),
              ),
              IconButton.filled(
                tooltip: 'Compartir código',
                style: IconButton.styleFrom(backgroundColor: AppColors.accentSoft),
                onPressed: () => _share(panel),
                icon: const Icon(LucideIcons.share2, size: 18, color: AppColors.accent),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Quien cree su cuenta con este código recibe 1 día de Ultra de '
            'regalo, y tú generas el $pct% de su primera compra por '
            'Transfermóvil (CUP).',
            style: AppTextStyles.body(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? AppColors.accentSoft : AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: highlight ? AppColors.accent : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: highlight ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.body(
              fontSize: 12,
              color: highlight ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _caption(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text.rich(
        TextSpan(
          text: label,
          style: AppTextStyles.body(fontSize: 12.5, color: AppColors.textSecondary),
          children: [
            TextSpan(
              text: value,
              style: AppTextStyles.body(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          title.toUpperCase(),
          style: AppTextStyles.body(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _empty(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTextStyles.body(fontSize: 13, color: AppColors.textSecondary),
      ),
    );
  }

  Widget _payoutAction(CreatorPanel panel) {
    if (panel.hasOpenRequest) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tienes un pago solicitado de ${formatCup(panel.requestedCup)}. '
              'Te avisaremos cuando se haga la transferencia.',
              style: AppTextStyles.body(fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(_cancelPayout),
              child: const Text('Cancelar solicitud'),
            ),
          ],
        ),
      );
    }
    final enabled = panel.canRequest && !_busy;
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.45),
          disabledForegroundColor: AppColors.accentInk.withValues(alpha: 0.75),
        ),
        onPressed: enabled ? () => _run(_requestPayout) : null,
        child: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accentInk,
                ),
              )
            : Text(
                panel.canRequest
                    ? 'Solicitar pago de ${formatCup(panel.pendingCup)}'
                    : 'Sin saldo pendiente para cobrar',
              ),
      ),
    );
  }

  Widget _referralRow(CreatorReferral r) {
    final bought = r.amountCup != null;
    return _row(
      title: r.displayName?.isNotEmpty == true ? r.displayName! : 'Usuario',
      subtitle: r.createdAt != null ? 'Se unió el ${formatDate(r.createdAt!)}' : null,
      chip: bought ? 'Compró · +${formatCup(r.amountCup!)}' : 'Registrado',
      chipColor: bought ? AppColors.success : AppColors.textSecondary,
    );
  }

  Widget _payoutRow(CreatorPayout p) {
    final (label, color) = switch (p.status) {
      'paid' => ('Pagado', AppColors.success),
      'cancelled' => ('Cancelado', AppColors.textMuted),
      _ => ('Solicitado', AppColors.accent),
    };
    final date = p.paidAt ?? p.requestedAt;
    return _row(
      title: formatCup(p.amountCup),
      subtitle: [
        if (date != null) formatDate(date),
        if (p.note?.isNotEmpty == true) p.note!,
      ].join(' · '),
      chip: label,
      chipColor: color,
    );
  }

  Widget _row({
    required String title,
    String? subtitle,
    required String chip,
    required Color chipColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: AppTextStyles.body(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: chipColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              chip,
              style: AppTextStyles.body(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: chipColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `2000` → `2 000 CUP` (miles separados con espacio, como pide el backend).
String formatCup(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer(amount < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return '$buffer CUP';
}

String formatDate(DateTime date) {
  const months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
