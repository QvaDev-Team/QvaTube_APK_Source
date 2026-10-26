import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_text.dart';
import '../../../catalog/application/catalog_providers.dart';

/// Barra o cápsula horizontal de estadísticas en tiempo real (spec de la imagen):
/// 🔴 {N} conectados   ▶ {N}/{Total} viendo   ✨ {N} nuevo hoy   📥 {N} hoy
class LiveStatsBar extends ConsumerWidget {
  const LiveStatsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(siteStatsProvider);

    return statsAsync.when(
      loading: () => _buildContent(
        online: null,
        watchingNow: null,
        watchingCap: null,
        newToday: null,
        downloadsToday: null,
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (stats) => _buildContent(
        online: stats.onlineNow ?? 0,
        watchingNow: stats.watchingNow ?? 0,
        watchingCap: stats.watchingCapacity ?? 20,
        newToday: stats.newToday ?? 0,
        downloadsToday: stats.activityToday ?? stats.totalDownloads ?? 0,
      ),
    );
  }

  Widget _buildContent({
    required int? online,
    required int? watchingNow,
    required int? watchingCap,
    required int? newToday,
    required int? downloadsToday,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🔴 {N} conectados
          _StatPill(
            icon: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFFF3D1A),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x99FF3D1A),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            value: online != null ? '$online' : '-',
            label: 'conectados',
          ),
          const SizedBox(width: 10),

          // ▶ {N}/{Cap} viendo
          _StatPill(
            icon: const Icon(
              Icons.play_arrow,
              size: 11,
              color: Color(0xFFFF3D1A),
            ),
            value: watchingNow != null
                ? '$watchingNow/${watchingCap ?? 20}'
                : '-/-',
            label: 'viendo',
          ),
          const SizedBox(width: 10),

          // ✨ {N} nuevo hoy
          _StatPill(
            icon: const Icon(
              Icons.auto_awesome,
              size: 10,
              color: Color(0xFFFF3D1A),
            ),
            value: newToday != null ? '$newToday' : '-',
            label: 'nuevo hoy',
          ),
          const SizedBox(width: 10),

          // 📥 {N} hoy
          _StatPill(
            icon: const Icon(
              Icons.arrow_downward,
              size: 10,
              color: Color(0xFFFF3D1A),
            ),
            value: downloadsToday != null ? '$downloadsToday' : '-',
            label: 'hoy',
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.icon,
    required this.value,
    required this.label,
  });

  final Widget icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        icon,
        const SizedBox(width: 4),
        Text(
          value,
          style: AppTextStyles.mono(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFE5E7EB),
          ),
        ),
        const SizedBox(width: 3.5),
        Text(
          label,
          style: AppTextStyles.body(
            fontSize: 10.5,
            color: const Color(0xFF9CA3AF),
          ),
        ),
      ],
    );
  }
}
