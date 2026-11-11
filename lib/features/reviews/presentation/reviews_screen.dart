import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/router/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../auth/presentation/providers/auth_controller.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../catalog/domain/catalog_models.dart';
import 'rating_widgets.dart';

/// Valorar QvaTube: formulario de valoración (`POST /api/reviews`) y
/// comentarios de los usuarios (`GET /api/reviews`).
class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(reviewsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Valorar QvaTube'),
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        onRefresh: () => ref.refresh(reviewsProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            const RatingSummary(starSize: 110),
            const SizedBox(height: 22),
            const _ReviewForm(),
            const SizedBox(height: 28),
            Text(
              'LO QUE DICEN LOS USUARIOS',
              style: AppTextStyles.display(fontSize: 20, letterSpacing: 0.5),
            ),
            const SizedBox(height: 12),
            reviews.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (error, stack) => _Note(
                'No se pudieron cargar los comentarios. Desliza hacia abajo '
                'para reintentar.',
              ),
              data: (data) => data.reviews.isEmpty
                  ? const _Note('Todavía no hay comentarios. ¡Sé el primero!')
                  : Column(
                      children: [
                        for (final review in data.reviews)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ReviewCard(review: review),
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

class _ReviewForm extends ConsumerStatefulWidget {
  const _ReviewForm();

  @override
  ConsumerState<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends ConsumerState<_ReviewForm> {
  static const _labels = ['Malo', 'Regular', 'Bueno', 'Muy bueno', 'Excelente'];

  final _comment = TextEditingController();
  int _rating = 0;
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _sending) return;
    FocusScope.of(context).unfocus();
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(catalogApiProvider)
          .submitReview(rating: _rating, comment: _comment.text);
      if (!mounted) return;
      setState(() {
        _rating = 0;
        _comment.clear();
      });
      ref.invalidate(reviewsProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('¡Gracias por tu valoración!')),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo enviar. Intenta de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _goToLogin() async {
    // Igual que "Cerrar sesión": el invitado sale de ese modo para poder
    // abrir el login (el router devuelve a Inicio a quien ya puede navegar).
    await ref.read(authControllerProvider.notifier).logout();
    if (mounted) context.go(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = ref.watch(authControllerProvider).isAuthenticated;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: ratingGold.withValues(alpha: 0.45)),
      ),
      child: isLoggedIn ? _form() : _loginPrompt(),
    );
  }

  Widget _loginPrompt() {
    return Column(
      children: [
        const Icon(Icons.person_outline, color: ratingGold, size: 30),
        const SizedBox(height: 10),
        Text(
          'Inicia sesión para valorar QvaTube.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _goToLogin,
            child: const Text('Iniciar sesión'),
          ),
        ),
      ],
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'TU VALORACIÓN',
          textAlign: TextAlign.center,
          style: AppTextStyles.display(fontSize: 18, letterSpacing: 0.5),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= 5; i++)
              GestureDetector(
                onTap: _sending ? null : () => setState(() => _rating = i),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: AnimatedScale(
                    scale: i == _rating ? 1.18 : 1,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    child: Icon(
                      Icons.star_rounded,
                      size: 44,
                      color: i <= _rating ? ratingGold : AppColors.border,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _rating == 0 ? 'Toca una estrella' : _labels[_rating - 1],
          textAlign: TextAlign.center,
          style: AppTextStyles.body(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _rating == 0 ? AppColors.textMuted : ratingGold,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _comment,
          enabled: !_sending,
          maxLength: 500,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Cuéntanos qué te parece QvaTube (opcional)',
          ),
        ),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: _rating == 0 || _sending ? null : _submit,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded, size: 18),
          label: Text(_sending ? 'Enviando…' : 'Enviar valoración'),
        ),
        const SizedBox(height: 8),
        Text(
          'Si ya valoraste antes, tu valoración anterior se reemplaza.',
          textAlign: TextAlign.center,
          style: AppTextStyles.body(fontSize: 11.5, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final ReviewItem review;

  @override
  Widget build(BuildContext context) {
    final name = (review.displayName?.trim().isNotEmpty ?? false)
        ? review.displayName!.trim()
        : 'Usuario';
    final avatar = absoluteMediaUrl(review.avatarUrl);
    final date = _relativeDate(review.createdAt);

    return Container(
      padding: const EdgeInsets.all(14),
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
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.accentSoft,
                foregroundImage: avatar.isEmpty ? null : NetworkImage(avatar),
                child: Text(
                  name.characters.first.toUpperCase(),
                  style: AppTextStyles.body(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    RatingStars(
                      value: (review.rating ?? 0).toDouble(),
                      size: 14,
                    ),
                  ],
                ),
              ),
              if (date != null)
                Text(
                  date,
                  style: AppTextStyles.body(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
          if (review.comment?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Text(
              review.comment!.trim(),
              style: AppTextStyles.body(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `2026-11-10 14:22:01` (UTC de SQLite) → "hace 3 h", "hace 2 días" o fecha.
String? _relativeDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  var iso = raw.trim().replaceFirst(' ', 'T');
  final hasZone =
      iso.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(iso);
  if (!hasZone) iso = '${iso}Z';
  final date = DateTime.tryParse(iso)?.toLocal();
  if (date == null) return null;
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'ahora';
  if (diff.inHours < 1) return 'hace ${diff.inMinutes} min';
  if (diff.inDays < 1) return 'hace ${diff.inHours} h';
  if (diff.inDays < 30) {
    return 'hace ${diff.inDays} ${diff.inDays == 1 ? 'día' : 'días'}';
  }
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year}';
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTextStyles.body(fontSize: 13, color: AppColors.textSecondary),
      ),
    );
  }
}
