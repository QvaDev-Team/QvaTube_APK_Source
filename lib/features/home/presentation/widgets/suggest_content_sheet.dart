import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../catalog/application/catalog_providers.dart';

/// Hoja para sugerir contenido (`POST /api/suggest-content`).
///
/// Body: `{ category_key, title, note, search_query }`.
Future<void> showSuggestContentSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    barrierColor: AppColors.modalBackdrop,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
    ),
    builder: (context) => const _SuggestContentSheet(),
  );
}

class _SuggestContentSheet extends ConsumerStatefulWidget {
  const _SuggestContentSheet();

  @override
  ConsumerState<_SuggestContentSheet> createState() =>
      _SuggestContentSheetState();
}

class _SuggestContentSheetState extends ConsumerState<_SuggestContentSheet> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  String _categoryKey = 'movie';
  bool _working = false;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Escribe el título que quieres sugerir.');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });

    try {
      await ref.read(catalogApiProvider).suggestContent(
            categoryKey: _categoryKey,
            title: title,
            note: _noteController.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _working = false;
        _done = true;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = 'No se pudo enviar la sugerencia.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Sugerir contenido',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 4),
              Text(
                '¿Falta algo en QvaTube? Cuéntanoslo y lo revisamos.',
                style: AppTextStyles.body(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              if (_done)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: AppColors.success,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '¡Gracias! La revisamos pronto.',
                          style: AppTextStyles.body(
                            fontSize: 13,
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      _error!,
                      style: AppTextStyles.body(
                        fontSize: 12.5,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                categories.when(
                  loading: () => const SizedBox.shrink(),
                  error: (error, stack) => const SizedBox.shrink(),
                  data: (items) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final category in items)
                        ChoiceChip(
                          label: Text(category['name']?.toString() ?? ''),
                          selected: category['key']?.toString() == _categoryKey,
                          onSelected: (_) => setState(
                            () => _categoryKey =
                                category['key']?.toString() ?? 'movie',
                          ),
                          selectedColor: AppColors.accentSoft,
                          backgroundColor: AppColors.surfaceSecondary,
                          labelStyle: AppTextStyles.body(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: category['key']?.toString() == _categoryKey
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                          side: BorderSide(
                            color:
                                category['key']?.toString() == _categoryKey
                                    ? AppColors.accent
                                    : AppColors.border,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _titleController,
                  style: AppTextStyles.body(fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Título',
                    prefixIcon: Icon(Icons.movie_filter_outlined, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  maxLines: 3,
                  style: AppTextStyles.body(fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                    prefixIcon: Icon(Icons.notes, size: 18),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _working ? null : _send,
                    child: _working
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accentInk,
                            ),
                          )
                        : const Text('Enviar sugerencia'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
