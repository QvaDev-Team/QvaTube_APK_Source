import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../catalog/application/catalog_providers.dart';
import '../../../catalog/domain/catalog_models.dart';

/// Diálogo "Reportar contenido" (`GET /api/report-reasons` + `POST /api/report`).
///
/// Igual que la web: se elige un motivo, el detalle es obligatorio solo para
/// "Otro", y al enviar se muestra la confirmación y se cierra solo.
Future<void> showReportContentDialog(BuildContext context, CatalogItem item) {
  return showDialog<void>(
    context: context,
    barrierColor: AppColors.modalBackdrop,
    builder: (context) => _ReportContentDialog(item: item),
  );
}

class _ReportContentDialog extends ConsumerStatefulWidget {
  const _ReportContentDialog({required this.item});

  final CatalogItem item;

  @override
  ConsumerState<_ReportContentDialog> createState() =>
      _ReportContentDialogState();
}

class _ReportContentDialogState extends ConsumerState<_ReportContentDialog> {
  final _detailController = TextEditingController();
  List<({String key, String label})>? _reasons;
  String? _loadError;
  String? _selected;
  bool _sending = false;
  String? _status;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _loadReasons();
  }

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _loadReasons() async {
    try {
      final reasons = await ref.read(catalogApiProvider).reportReasons();
      if (!mounted) return;
      setState(() => _reasons = reasons);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _loadError =
            'No se pudieron cargar los motivos. Intenta de nuevo más tarde.',
      );
    }
  }

  Future<void> _submit() async {
    final reason = _selected;
    if (reason == null || _sending) return;
    final detail = _detailController.text.trim();
    if (reason == 'otro' && detail.isEmpty) {
      setState(() {
        _status = 'Describe el problema antes de enviar.';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _sending = true;
      _status = null;
    });
    try {
      await ref
          .read(catalogApiProvider)
          .submitReport(item: widget.item, reasonKey: reason, detail: detail);
      if (!mounted) return;
      setState(() {
        _status = '¡Gracias! Revisaremos tu reporte pronto.';
        _statusIsError = false;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _status = error.statusCode == 401
            ? 'Inicia sesión para reportar contenido.'
            : error.message;
        _statusIsError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _status = 'No se pudo enviar el reporte.';
        _statusIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reasons = _reasons;

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'REPORTAR CONTENIDO',
                textAlign: TextAlign.center,
                style: AppTextStyles.display(fontSize: 20, letterSpacing: 0.5),
              ),
              const SizedBox(height: 6),
              Text(
                widget.item.title ?? '',
                textAlign: TextAlign.center,
                style: AppTextStyles.body(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              if (_loadError != null)
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body(
                    fontSize: 12.5,
                    color: AppColors.danger,
                  ),
                )
              else if (reasons == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                for (final reason in reasons)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ReasonButton(
                      label: reason.label,
                      selected: _selected == reason.key,
                      onTap: _sending
                          ? null
                          : () => setState(() {
                              _selected = reason.key;
                              _status = null;
                            }),
                    ),
                  ),
                if (_selected != null) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _detailController,
                    maxLength: 500,
                    minLines: 3,
                    maxLines: 5,
                    enabled: !_sending,
                    style: AppTextStyles.body(fontSize: 13),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: _selected == 'otro'
                          ? 'Describe el problema (obligatorio)...'
                          : 'Detalles adicionales (opcional)...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _sending ? null : _submit,
                      child: Text(_sending ? 'Enviando...' : 'Enviar reporte'),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 8),
              SizedBox(
                height: 46,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              if (_status != null) ...[
                const SizedBox(height: 12),
                Text(
                  _status!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body(
                    fontSize: 12.5,
                    color: _statusIsError ? AppColors.danger : AppColors.success,
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

class _ReasonButton extends StatelessWidget {
  const _ReasonButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentSoft : AppColors.surfaceSecondary,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.body(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
