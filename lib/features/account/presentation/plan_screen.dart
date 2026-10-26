import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qvatube_apk/features/catalog/domain/catalog_models.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../catalog/application/catalog_providers.dart';

/// Plan y suscripción.
///
/// - `GET /api/plans`: catálogo de planes con límites y precios.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Plan y suscripción'),
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        onRefresh: () async {
          ref.invalidate(plansProvider);
          await ref.read(plansProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(
              'Elige tu plan',
              style: AppTextStyles.display(fontSize: 22, letterSpacing: 0.5),
            ),
            const SizedBox(height: 16),
            plans.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (error, stack) =>
                  const Text('No se pudo cargar el catálogo de planes.'),
              data: (items) => Column(
                children: [for (final plan in items) _PlanCard(plan: plan)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});

  final PlanInfo plan;

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
        border: Border.all(color: AppColors.border),
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
                      onPressed: () =>
                          _showPaymentPending(context, plan, 'CUP'),
                      child: const Text('Pagar en CUP'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 43,
                    child: OutlinedButton(
                      onPressed: () =>
                          _showPaymentPending(context, plan, 'QvaPay'),
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
                  onPressed: () =>
                      _showPaymentPending(context, plan, 'Saldo Móvil'),
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

  void _showPaymentPending(BuildContext context, PlanInfo plan, String method) {
    final planName = plan.name ?? plan.key ?? '';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'El pago de $planName con $method estará disponible próximamente.',
          ),
        ),
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
