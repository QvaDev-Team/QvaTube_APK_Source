import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qvatube_apk/features/auth/presentation/providers/auth_controller.dart';
import 'package:qvatube_apk/features/home/presentation/widgets/info_row.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../catalog/application/catalog_providers.dart';

/// Plan y suscripción.
///
/// - `GET /api/plans/me`: consumo actual del plan.
/// - `GET /api/plans`: catálogo de planes con límites y precios.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(planUsageProvider);
    final plans = ref.watch(plansProvider);
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;

    return Scaffold(
      backgroundColor: AppColors.background,
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
          ref.invalidate(planUsageProvider);
          ref.invalidate(plansProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            usage.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (error, stack) => const Text('No se pudo cargar tu plan.'),
              data: (data) {
                final plan = data.usage;
                if (plan == null) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: AppColors.accent),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.planName ?? (plan.plan ?? 'Plan').toUpperCase(),
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 14),
                      _UsageBar(
                        label: 'Descargas',
                        used: plan.downloadsUsed ?? 0,
                        limit: plan.downloadLimit ?? 0,
                      ),
                      _UsageBar(
                        label: 'Streams de video',
                        used: plan.streamsUsed ?? 0,
                        limit: plan.streamLimit ?? 0,
                      ),
                      _UsageBar(
                        label: 'Descargas comprimidas',
                        used: plan.compressedUsed ?? 0,
                        limit: plan.compressedLimit ?? 0,
                      ),
                      _UsageBar(
                        label: 'Descargas de música',
                        used: plan.musicDownloadsUsed ?? 0,
                        limit: plan.musicDownloadLimit ?? 0,
                      ),
                      _UsageBar(
                        label: 'Streams de música',
                        used: plan.musicStreamsUsed ?? 0,
                        limit: plan.musicStreamLimit ?? 0,
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            InfoRow(
              icon: Icons.confirmation_number_outlined,
              label: 'Código de referido',
              value: user?.referralCode ?? '—',
              mono: true,
            ),
            const SizedBox(height: 20),

            Text(
              'Planes disponibles',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 12),
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
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadii.md),
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
                                  style: AppTextStyles.body(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                plan.priceCup != null && plan.priceCup! > 0
                                    ? '${plan.priceCup!.toStringAsFixed(0)} CUP'
                                    : 'Gratis',
                                style: AppTextStyles.mono(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.accent,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _Chip(
                                label: '${plan.downloadLimit ?? 0} descargas',
                              ),
                              _Chip(label: '${plan.streamLimit ?? 0} streams'),
                              _Chip(
                                label:
                                    '${plan.musicDownloadLimit ?? 0} de música',
                              ),
                              if ((plan.priceUsd ?? 0) > 0)
                                _Chip(label: '\$${plan.priceUsd} USD'),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.label,
    required this.used,
    required this.limit,
  });

  final String label;
  final int used;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final ratio = limit <= 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.body(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                '$used / ${limit > 0 ? limit : '∞'}',
                style: AppTextStyles.mono(fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: AppColors.surfaceSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: AppTextStyles.body(
          fontSize: 11,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
