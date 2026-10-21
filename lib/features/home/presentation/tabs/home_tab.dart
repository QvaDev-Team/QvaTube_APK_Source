import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/app_logo.dart';
import '../widgets/content_placeholders.dart';

/// Pestaña de Inicio (spec §6.5).
///
/// La estructura y el diseño están listos; el contenido real depende de los
/// endpoints del catálogo, que aún no se han conectado.
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: const [
        _Hero(),
        SizedBox(height: 26),
        SectionTitle(title: 'Seguir donde quedaste'),
        _PosterRow(),
        SizedBox(height: 26),
        SectionTitle(title: 'Recomendaciones'),
        _PosterRow(),
        SizedBox(height: 26),
        _CommunityBanner(),
        SizedBox(height: 26),
        SectionTitle(title: 'Cómo funciona'),
        _HowItWorks(),
        SizedBox(height: 26),
        SectionTitle(title: 'Reseñas y estadísticas'),
        _StatsGrid(),
        SizedBox(height: 16),
        _ReviewForm(),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppLogo(height: 64),
        const SizedBox(height: 10),
        Text(
          'Streaming cubano — películas, series, novelas, anime, música y libros.',
          textAlign: TextAlign.center,
          style: AppTextStyles.display(
            fontSize: 17,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 20),
        const Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: 'Sugerir contenido',
                icon: Icons.auto_awesome,
                color: AppColors.accent,
                foreground: AppColors.accentInk,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                label: 'Súbelo tú mismo',
                icon: Icons.send,
                color: AppColors.telegram,
                foreground: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: 'Comunidad',
                icon: Icons.chat_bubble_outline,
                color: AppColors.whatsapp,
                foreground: Colors.white,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _ActionButton(
                label: 'Descargar APK',
                icon: Icons.download,
                color: AppColors.textPrimary,
                foreground: Colors.black,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.foreground,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadii.md),
        boxShadow: color == AppColors.accent ? AppColors.playGlow : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterRow extends StatelessWidget {
  const _PosterRow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 248,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 6,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return const PosterPlaceholder(width: 122);
        },
      ),
    );
  }
}

class _CommunityBanner extends StatelessWidget {
  const _CommunityBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: const Color(0x55FF3D1A)),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.18),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentSoft,
            ),
            child: const Icon(
              Icons.rocket_launch_outlined,
              color: AppColors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Instala la APK de QvaTube',
                  style: AppTextStyles.body(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'La versión Android más ligera para tu teléfono.',
                  style: AppTextStyles.body(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              'Descargar',
              style: AppTextStyles.body(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppColors.accentInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const List<String> _steps = [
    'Elige tu contenido',
    'Reproduce o descarga directo a tu móvil',
    'Ahorra megas',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < _steps.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: AppTextStyles.body(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accentInk,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _steps[index],
                    style: AppTextStyles.body(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid();

  static const List<({String label, String value})> _stats = [
    (label: 'Películas indexadas', value: '—'),
    (label: 'Series', value: '—'),
    (label: 'Música', value: '—'),
    (label: 'Usuarios activos', value: '—'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('4.9', style: Theme.of(context).textTheme.displayLarge),
                Row(
                  children: List.generate(
                    5,
                    (index) => const Icon(
                      Icons.star,
                      size: 14,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                'Reseñas de la comunidad — pendiente de conectar con el '
                'endpoint de reseñas.',
                style: AppTextStyles.body(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: [
            for (final stat in _stats)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      stat.value,
                      style: AppTextStyles.display(fontSize: 22),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stat.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ReviewForm extends StatelessWidget {
  const _ReviewForm();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Deja tu calificación',
            style: AppTextStyles.body(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(
              5,
              (index) => const Icon(
                Icons.star_border,
                size: 24,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const TextField(
            style: TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Escribe tu comentario...',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: null,
              child: Text('Enviar reseña'),
            ),
          ),
        ],
      ),
    );
  }
}
