import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/platform/device_channel.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../auth/presentation/providers/auth_controller.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/catalog_models.dart';
import 'plan_payment_screen.dart';

/// Plan y suscripción.
///
/// - `GET /api/plans`: catálogo de planes con límites y precios.
/// - `GET /api/plans/me`: plan actual y solicitud de pago pendiente.
/// - Pago por Transfermóvil (CUP), QvaPay (USD) o Saldo Móvil (solo Ultra):
///   ver [PlanPaymentScreen] y [_PlanScreenState._startQvaPay].
/// - Mientras hay un pago en revisión se sondea `/api/plans/me` cada 4 s
///   (igual que la web) para mostrar el resultado en cuanto se resuelve.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  static const _pollInterval = Duration(seconds: 4);

  bool _loadingStatus = true;
  PlanUsage? _usage;
  PendingPlanRequest? _pending;
  ({bool approved, PendingPlanRequest request})? _result;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await ref.read(catalogApiProvider).planStatus();
      if (!mounted) return;
      setState(() {
        _usage = status.usage;
        _pending = status.pending;
        _loadingStatus = false;
      });
      if (status.pending != null) _startPolling();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingStatus = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    final pending = _pending;
    if (pending == null) {
      _pollTimer?.cancel();
      return;
    }
    final ({PlanUsage? usage, PendingPlanRequest? pending}) status;
    try {
      status = await ref.read(catalogApiProvider).planStatus();
    } catch (_) {
      return; // red caída momentáneamente: se reintenta en el próximo tick
    }
    if (!mounted || status.pending != null) return;

    // La solicitud se resolvió: si el plan efectivo es el pedido, se aprobó.
    _pollTimer?.cancel();
    setState(() {
      _usage = status.usage;
      _pending = null;
      _result = (
        approved: status.usage?.plan == pending.planKey,
        request: pending,
      );
    });
    ref.invalidate(planUsageProvider);
    ref.read(authControllerProvider.notifier).restoreSession();
  }

  Future<void> _cancelPending() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar solicitud'),
        content: const Text(
          '¿Cancelar esta solicitud de pago? Si ya pagaste, espera aquí en '
          'vez de esto: se confirma sola.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Seguir esperando'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancelar solicitud'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _pollTimer?.cancel();
    try {
      await ref.read(catalogApiProvider).cancelPendingPlan();
    } catch (_) {
      // Se vuelve a consultar el estado igualmente.
    }
    if (!mounted) return;
    setState(() => _loadingStatus = true);
    await _refreshStatus();
  }

  Future<void> _openPayment(PlanInfo plan, PlanPaymentMethod method) async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => PlanPaymentScreen(plan: plan, method: method),
      ),
    );
    if (submitted == true && mounted) {
      setState(() => _loadingStatus = true);
      await _refreshStatus();
    }
  }

  Future<void> _startQvaPay(PlanInfo plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pagar con QvaPay'),
        content: Text(
          'Vas a pagar \$${_formatPrice(plan.priceUsd)} USD (1 mes) en la web '
          'de QvaPay.\n\nSi no tienes cuenta ahí, te va a pedir crear una '
          'gratis (rápido, con correo) antes de poder completar el pago — así '
          'funciona QvaPay, es normal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Volver'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continuar a QvaPay'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Generando factura de QvaPay...')),
    );
    try {
      final url = await ref.read(catalogApiProvider).subscribeQvaPay(plan.key!);
      await DeviceChannel.openUrl(url);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      setState(() {
        _pending = PendingPlanRequest(planKey: plan.key!, method: 'qvapay');
      });
      _startPolling();
    } on ApiException catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No se pudo iniciar el pago con QvaPay')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = ref.watch(plansProvider);
    final isLoggedIn =
        ref.watch(authControllerProvider).status == AuthStatus.authenticated;

    Widget body;
    if (_loadingStatus) {
      body = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_result != null) {
      body = _PaymentResultView(
        approved: _result!.approved,
        request: _result!.request,
        usage: _usage,
        onDone: () => setState(() => _result = null),
      );
    } else if (_pending != null) {
      body = _PendingView(pending: _pending!, onCancel: _cancelPending);
    } else {
      body = RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        onRefresh: () async {
          ref.invalidate(plansProvider);
          await Future.wait([ref.read(plansProvider.future), _refreshStatus()]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            if (_usage != null) ...[
              _CurrentPlanCard(usage: _usage!),
              const SizedBox(height: 20),
            ],
            Text(
              'Elige tu plan',
              style: AppTextStyles.display(fontSize: 22, letterSpacing: 0.5),
            ),
            if (!isLoggedIn) ...[
              const SizedBox(height: 6),
              Text(
                'Inicia sesión para contratar un plan.',
                style: AppTextStyles.body(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 16),
            plans.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (error, stack) =>
                  const Text('No se pudo cargar el catálogo de planes.'),
              data: (items) => Column(
                children: [
                  for (final plan in items)
                    _PlanCard(
                      plan: plan,
                      isCurrent: _usage?.plan == plan.key,
                      enabled: isLoggedIn,
                      onPay: (method) => method == PlanPaymentMethod.qvapay
                          ? _startQvaPay(plan)
                          : _openPayment(plan, method),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Plan y suscripción'),
      ),
      body: body,
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({required this.usage});

  final PlanUsage usage;

  @override
  Widget build(BuildContext context) {
    String quota(String label, int? used, int? limit) {
      if (limit == null) return '$label: ilimitado';
      return '$label: ${used ?? 0}/$limit';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tu plan actual',
            style: AppTextStyles.body(
              fontSize: 11.5,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            usage.planName ?? usage.plan ?? 'Gratis',
            style: AppTextStyles.display(fontSize: 18, letterSpacing: 0.3),
          ),
          const SizedBox(height: 8),
          for (final line in [
            quota('Descargas', usage.downloadsUsed, usage.downloadLimit),
            quota(
              'Reproducciones online',
              usage.streamsUsed,
              usage.streamLimit,
            ),
            quota(
              'Música',
              usage.musicStreamsUsed,
              usage.musicStreamLimit,
            ),
          ])
            Text(
              line,
              style: AppTextStyles.body(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Las cuotas se reinician cada 12 horas.',
            style: AppTextStyles.body(fontSize: 10.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _PendingView extends StatelessWidget {
  const _PendingView({required this.pending, required this.onCancel});

  final PendingPlanRequest pending;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final weeks = pending.weeks ?? 1;
    final String message;
    if (pending.isQvaPay) {
      message =
          'Abrimos la página de pago de QvaPay en el navegador. En cuanto se '
          'confirme el pago (automático, normalmente en segundos o minutos), '
          'tu plan ${pending.planKey} se activa solo.';
    } else {
      final weeksNote = weeks > 1
          ? ' ($weeks semanas'
                '${pending.totalCup != null ? ' · ${pending.totalCup} CUP' : ''})'
          : '';
      message =
          'Enviamos tu comprobante para el plan ${pending.planKey}$weeksNote.\n'
          'Esto puede tardar hasta 1-2 horas. Después de las 10 de la noche '
          'puede demorar más por el horario nocturno.\n'
          'Esta pantalla se actualiza sola en cuanto haya novedades.';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 28),
      children: [
        const Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          pending.isQvaPay
              ? 'Esperando confirmación de QvaPay'
              : 'Revisando tu pago',
          textAlign: TextAlign.center,
          style: AppTextStyles.display(fontSize: 20, letterSpacing: 0.4),
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.body(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bolt, size: 14, color: AppColors.accent),
            const SizedBox(width: 4),
            Text(
              'Comprobando en vivo…',
              style: AppTextStyles.body(fontSize: 11.5, color: AppColors.accent),
            ),
          ],
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: onCancel,
          child: const Text('Cancelar solicitud'),
        ),
      ],
    );
  }
}

class _PaymentResultView extends StatelessWidget {
  const _PaymentResultView({
    required this.approved,
    required this.request,
    required this.usage,
    required this.onDone,
  });

  final bool approved;
  final PendingPlanRequest request;
  final PlanUsage? usage;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 28),
      children: [
        Icon(
          approved ? Icons.check_circle : Icons.cancel,
          size: 56,
          color: approved ? AppColors.success : AppColors.danger,
        ),
        const SizedBox(height: 16),
        Text(
          approved ? '¡Pago aprobado!' : 'Pago no aprobado',
          textAlign: TextAlign.center,
          style: AppTextStyles.display(fontSize: 22, letterSpacing: 0.4),
        ),
        const SizedBox(height: 10),
        Text(
          approved
              ? 'Tu plan ${usage?.planName ?? request.planKey} ya está activo. '
                    '¡Disfrútalo!'
              : 'No pudimos confirmar tu pago. Si crees que es un error, '
                    'escríbenos por la comunidad con tu comprobante.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body(
            fontSize: 13,
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: onDone,
          child: Text(approved ? 'Continuar' : 'Volver a los planes'),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.enabled,
    required this.onPay,
  });

  final PlanInfo plan;
  final bool isCurrent;
  final bool enabled;
  final ValueChanged<PlanPaymentMethod> onPay;

  @override
  Widget build(BuildContext context) {
    final isFree = (plan.priceCup ?? 0) <= 0;
    final priceText = isFree
        ? 'Gratis'
        : '${_formatPrice(plan.priceCup)} CUP/sem · '
              '\$${_formatPrice(plan.priceUsd)} USD/mes';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: isCurrent ? AppColors.accent : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name ?? plan.key ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.display(
                    fontSize: 18,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    priceText,
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    style: AppTextStyles.body(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isFree
                          ? AppColors.textSecondary
                          : AppColors.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (isCurrent)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Tu plan actual',
                style: AppTextStyles.body(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          const SizedBox(height: 8),
          for (final feature in _featuresFor(plan))
            _PlanFeature(icon: feature.icon, label: feature.label),
          if (!isFree) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 43,
                    child: ElevatedButton(
                      onPressed: enabled
                          ? () => onPay(PlanPaymentMethod.transfermovil)
                          : null,
                      child: const Text('Pagar en CUP'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 43,
                    child: OutlinedButton(
                      onPressed: enabled
                          ? () => onPay(PlanPaymentMethod.qvapay)
                          : null,
                      style: _secondaryButtonStyle,
                      child: const Text('QvaPay (USD)'),
                    ),
                  ),
                ),
              ],
            ),
            if (plan.key == 'ultra') ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 43,
                child: OutlinedButton(
                  onPressed: enabled
                      ? () => onPay(PlanPaymentMethod.mobileBalance)
                      : null,
                  style: _secondaryButtonStyle,
                  child: const Text('Pagar con Saldo Móvil'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  ButtonStyle get _secondaryButtonStyle {
    return OutlinedButton.styleFrom(
      backgroundColor: AppColors.surfaceSecondary,
      foregroundColor: AppColors.textPrimary,
      side: const BorderSide(color: AppColors.border),
    );
  }
}

class _PlanFeature extends StatelessWidget {
  const _PlanFeature({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1.5),
            child: Icon(icon, size: 13, color: AppColors.accent),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.body(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanFeatureData {
  const _PlanFeatureData(this.icon, this.label);

  final IconData icon;
  final String label;
}

List<_PlanFeatureData> _featuresFor(PlanInfo plan) {
  return [
    _PlanFeatureData(
      Icons.movie_outlined,
      plan.downloadLimit == null
          ? 'Descargas ilimitadas'
          : '${plan.downloadLimit} '
                '${_plural(plan.downloadLimit!, 'descarga', 'descargas')} '
                'por periodo',
    ),
    _PlanFeatureData(
      Icons.movie_outlined,
      plan.streamLimit == null
          ? 'Reproducción online ilimitada'
          : plan.streamLimit == 0
          ? 'Sin reproducción online'
          : '${plan.streamLimit} '
                '${_plural(plan.streamLimit!, 'reproducción', 'reproducciones')} '
                'online',
    ),
    _PlanFeatureData(
      Icons.music_note,
      plan.musicStreamLimit == null
          ? 'Música ilimitada'
          : plan.musicStreamLimit == 0
          ? 'Sin reproducción de música'
          : '${plan.musicStreamLimit} '
                '${_plural(plan.musicStreamLimit!, 'reproducción', 'reproducciones')} '
                'de música',
    ),
    _PlanFeatureData(
      Icons.music_note,
      plan.musicDownloadLimit == null
          ? 'Descargas de música ilimitadas'
          : plan.musicDownloadLimit == 0
          ? 'Sin descargas de música'
          : '${plan.musicDownloadLimit} '
                '${_plural(plan.musicDownloadLimit!, 'descarga', 'descargas')} '
                'de música',
    ),
    if (plan.key == 'ultra') ...[
      const _PlanFeatureData(Icons.download_outlined, 'Descargas en lote'),
      const _PlanFeatureData(Icons.share_outlined, 'Sistema de referidos'),
    ],
  ];
}

String _plural(int value, String singular, String plural) {
  return value == 1 ? singular : plural;
}

String _formatPrice(double? value) {
  if (value == null) return '0';
  return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
}
