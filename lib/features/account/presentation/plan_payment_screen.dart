import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/platform/device_channel.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/catalog_models.dart';

/// Forma de pago de un plan.
enum PlanPaymentMethod { transfermovil, qvapay, mobileBalance }

/// Precio fijo del plan Ultra pagado con Saldo Móvil (1 mes), igual que la web.
const int mobileBalancePriceCup = 120;

/// Total en CUP con el descuento por semanas (espejo de
/// `services/plans.py:compute_cup_total`; solo para mostrarlo: el backend
/// recalcula el monto real al crear la solicitud).
({int total, bool discounted}) computeCupTotal({
  required double pricePerWeek,
  required int weeks,
  required int discountMinWeeks,
  required double discountRate,
}) {
  final subtotal = pricePerWeek * weeks;
  final discounted = weeks >= discountMinWeeks;
  return (
    total: (discounted ? subtotal * (1 - discountRate) : subtotal).round(),
    discounted: discounted,
  );
}

/// Formulario de pago por Transfermóvil (CUP, con semanas y descuento) o por
/// Saldo Móvil (solo Ultra). Devuelve `true` al hacer `pop` si la solicitud
/// se envió: la pantalla de planes pasa entonces a "Revisando tu pago".
///
/// La captura se sube en cuanto se elige (`POST /api/plans/upload-proof`) para
/// que "Enviar comprobante" solo confirme con el token y se sienta inmediato
/// aunque la conexión sea lenta, igual que la web.
class PlanPaymentScreen extends ConsumerStatefulWidget {
  const PlanPaymentScreen({
    super.key,
    required this.plan,
    required this.method,
  });

  final PlanInfo plan;
  final PlanPaymentMethod method;

  @override
  ConsumerState<PlanPaymentScreen> createState() => _PlanPaymentScreenState();
}

enum _UploadState { idle, uploading, ready, error }

class _PlanPaymentScreenState extends ConsumerState<PlanPaymentScreen> {
  static const int _maxPhotoBytes = 8 * 1024 * 1024;

  final _phoneController = TextEditingController();
  late int _weeks = widget.plan.cupMinWeeks ?? 1;
  String? _photoPath;
  String? _uploadToken;
  Future<void>? _uploadFuture;
  _UploadState _uploadState = _UploadState.idle;
  bool _submitting = false;
  String? _error;

  bool get _isMobileBalance =>
      widget.method == PlanPaymentMethod.mobileBalance;
  int get _minWeeks => widget.plan.cupMinWeeks ?? 1;
  int get _maxWeeks => widget.plan.cupMaxWeeks ?? 52;
  int get _discountMinWeeks => widget.plan.cupDiscountMinWeeks ?? 4;
  double get _discountRate => widget.plan.cupDiscountRate ?? 0.10;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _setWeeks(int value) {
    setState(() => _weeks = value.clamp(_minWeeks, _maxWeeks));
  }

  Future<void> _pickPhoto() async {
    final path = await DeviceChannel.pickImage();
    if (!mounted || path == null || path.isEmpty) return;
    if (File(path).lengthSync() > _maxPhotoBytes) {
      setState(() => _error = 'La imagen no puede superar los 8 MB.');
      return;
    }
    setState(() {
      _photoPath = path;
      _uploadToken = null;
      _uploadState = _UploadState.uploading;
      _error = null;
    });
    _uploadFuture = _upload(path);
  }

  Future<void> _upload(String path) async {
    try {
      final token = await ref.read(catalogApiProvider).uploadPlanProof(path);
      if (!mounted || _photoPath != path) return;
      setState(() {
        _uploadToken = token;
        _uploadState = _UploadState.ready;
      });
    } catch (_) {
      if (!mounted || _photoPath != path) return;
      setState(() => _uploadState = _UploadState.error);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final photo = _photoPath;
    final senderPhone = _phoneController.text.trim();

    if (_isMobileBalance) {
      final destination = _destinationPhone;
      if (destination.isEmpty) {
        setState(
          () => _error =
              'Este método de pago todavía no está configurado. Contacta con soporte.',
        );
        return;
      }
      final digits = senderPhone.replaceAll(RegExp(r'\D'), '');
      if (!RegExp(r'^[+]?[-()\s\d]{7,20}$').hasMatch(senderPhone) ||
          digits.length < 7) {
        setState(
          () => _error = 'Introduce el número de teléfono del comprobante.',
        );
        return;
      }
    }
    if (photo == null) {
      setState(() => _error = 'Adjunta la captura del comprobante primero.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    final api = ref.read(catalogApiProvider);
    try {
      if (_uploadState == _UploadState.uploading) await _uploadFuture;
      if (_isMobileBalance) {
        final token = _uploadToken ?? await api.uploadPlanProof(photo);
        await api.subscribeMobileBalance(
          uploadToken: token,
          senderPhone: senderPhone,
        );
      } else {
        // Sin token (falló la pre-subida) se manda la foto en el mismo POST.
        await api.subscribePlan(
          planKey: widget.plan.key!,
          weeks: _weeks,
          uploadToken: _uploadToken,
          photoPath: _uploadToken == null ? photo : null,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'No se pudo enviar el comprobante.';
      });
    }
  }

  String get _destinationPhone =>
      ref.read(siteConfigProvider).value?.mobileBalancePhone?.trim() ?? '';

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(siteConfigProvider).value;
    final plan = widget.plan;
    final cup = computeCupTotal(
      pricePerWeek: plan.priceCup ?? 0,
      weeks: _weeks,
      discountMinWeeks: _discountMinWeeks,
      discountRate: _discountRate,
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          _isMobileBalance ? 'Pagar QvaTube Ultra' : 'Pagar ${plan.name ?? ''}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          if (!_isMobileBalance) ...[
            _WeeksPicker(
              weeks: _weeks,
              onChanged: _setWeeks,
              discountMinWeeks: _discountMinWeeks,
              discountPct: (_discountRate * 100).round(),
            ),
            const SizedBox(height: 14),
          ],
          _InfoBox(
            children: _isMobileBalance
                ? [
                    Text.rich(
                      TextSpan(
                        text: 'Transfiere ',
                        children: [
                          _bold('$mobileBalancePriceCup CUP'),
                          const TextSpan(
                            text: ' de saldo móvil por 1 mes a:',
                          ),
                        ],
                      ),
                    ),
                    _CopyRow(
                      label: 'Número a recargar',
                      value: config?.mobileBalancePhone ?? '',
                    ),
                  ]
                : [
                    Text.rich(
                      TextSpan(
                        text: 'Transfiere ',
                        children: [
                          _bold('${cup.total} CUP'),
                          const TextSpan(text: ' por Transfermóvil a:'),
                        ],
                      ),
                    ),
                    _CopyRow(
                      label: 'Tarjeta',
                      value: config?.paymentCard ?? '',
                    ),
                    _CopyRow(
                      label: 'Número de confirmación',
                      value: config?.paymentPhone ?? '',
                    ),
                    Text.rich(
                      TextSpan(
                        text: 'A nombre de: ',
                        children: [_bold(config?.paymentName ?? 'QvaTube')],
                      ),
                    ),
                  ],
          ),
          const SizedBox(height: 10),
          _Warning(
            text: _isMobileBalance
                ? 'Escribe abajo el número de teléfono del comprobante: lo '
                      'usamos para ubicar tu recarga y activar tu plan.'
                : 'Usa ese número de confirmación para el pago: es la única '
                      'forma que tenemos de contactarte si hay algún problema.',
          ),
          if (!_isMobileBalance && _weeks > 1) ...[
            const SizedBox(height: 8),
            Text(
              cup.discounted
                  ? 'Son $_weeks semanas — ${cup.total} CUP en vez de '
                        '${((plan.priceCup ?? 0) * _weeks).round()} CUP '
                        '(${(_discountRate * 100).round()}% off aplicado).'
                  : 'Son $_weeks semanas de '
                        '${(plan.priceCup ?? 0).round()} CUP cada una.',
              style: AppTextStyles.body(
                fontSize: 12,
                color: cup.discounted
                    ? AppColors.success
                    : AppColors.textSecondary,
              ),
            ),
          ],
          if (_isMobileBalance) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              maxLength: 20,
              decoration: const InputDecoration(
                counterText: '',
                labelText: 'Número de teléfono del comprobante',
                hintText: 'Número desde el que recargaste',
              ),
            ),
          ],
          const SizedBox(height: 14),
          _PhotoPicker(
            path: _photoPath,
            state: _uploadState,
            onTap: _submitting ? null : _pickPhoto,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: AppTextStyles.body(fontSize: 12.5, color: AppColors.danger),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Enviando…' : 'Enviar comprobante'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 46,
            child: OutlinedButton(
              onPressed: _submitting
                  ? null
                  : () => Navigator.of(context).maybePop(),
              child: const Text('Volver'),
            ),
          ),
        ],
      ),
    );
  }

  static TextSpan _bold(String text) => TextSpan(
    text: text,
    style: const TextStyle(fontWeight: FontWeight.w800),
  );
}

class _WeeksPicker extends StatelessWidget {
  const _WeeksPicker({
    required this.weeks,
    required this.onChanged,
    required this.discountMinWeeks,
    required this.discountPct,
  });

  final int weeks;
  final ValueChanged<int> onChanged;
  final int discountMinWeeks;
  final int discountPct;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '¿Cuántas semanas quieres pagar?',
          style: AppTextStyles.body(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: () => onChanged(weeks - 1),
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Text(
                '$weeks ${weeks == 1 ? 'semana' : 'semanas'}',
                textAlign: TextAlign.center,
                style: AppTextStyles.display(fontSize: 20),
              ),
            ),
            IconButton.filledTonal(
              onPressed: () => onChanged(weeks + 1),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.bolt, size: 14, color: AppColors.accent),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Paga $discountMinWeeks+ semanas juntas y llévate '
                '$discountPct% de descuento.',
                style: AppTextStyles.body(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: DefaultTextStyle.merge(
        style: AppTextStyles.body(fontSize: 13, height: 1.6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final configured = value.trim().isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              text: '$label: ',
              children: [
                TextSpan(
                  text: configured ? value : 'No configurado',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
        if (configured)
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text('$label copiado.')));
            },
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: AppColors.accent,
            ),
            icon: const Icon(Icons.copy, size: 14),
            label: const Text('Copiar'),
          ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.flag_outlined, size: 14, color: AppColors.danger),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.body(
              fontSize: 12,
              color: AppColors.danger,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.path,
    required this.state,
    required this.onTap,
  });

  final String? path;
  final _UploadState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (IconData? icon, String status, Color color) = switch (state) {
      _UploadState.uploading => (null, 'Subiendo captura…', AppColors.textMuted),
      _UploadState.ready => (Icons.check, 'Lista para enviar', AppColors.success),
      _UploadState.error => (
        Icons.refresh,
        'Se enviará al tocar "Enviar comprobante"',
        AppColors.textSecondary,
      ),
      _UploadState.idle => (null, '', AppColors.textMuted),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceSecondary,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: path == null ? AppColors.border : AppColors.accent,
              ),
            ),
            child: path == null
                ? Column(
                    children: [
                      const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Toca para adjuntar la captura del pago',
                        style: AppTextStyles.body(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          File(path!),
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${path!.split('/').last}\nToca para cambiarla',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (status.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              if (icon == null)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else
                Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(status, style: AppTextStyles.body(fontSize: 11.5, color: color)),
            ],
          ),
        ],
      ],
    );
  }
}
