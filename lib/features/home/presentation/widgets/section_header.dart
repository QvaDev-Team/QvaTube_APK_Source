import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Encabezado de sección con línea divisoria (spec §3.2).
///
/// `accent` pinta la línea divisoria con el color del género.
/// `highlight` añade un sufijo resaltado (por ejemplo, "Especial Halloween").
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.accent,
    this.highlight,
    this.highlightColor = AppColors.accent,
    this.action,
    this.icon,
  });

  final String title;
  final String? accent;
  final String? highlight;
  final Color highlightColor;
  final Widget? action;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final accentColor = _parseColor(accent);
    final style = Theme.of(context).textTheme.displaySmall;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          final maxTitleWidth = (constraints.maxWidth - gap).clamp(
            0.0,
            double.infinity,
          );

          return Row(
            children: [
              // 1. Icono en cuadradito (si existe)
              if (icon != null) ...[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: (accentColor ?? AppColors.border).withValues(
                      alpha: 0.14,
                    ),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: (accentColor ?? AppColors.border).withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),
                  child: IconTheme(
                    data: IconThemeData(
                      color: accentColor ?? AppColors.border,
                      size: 18,
                    ),
                    child: icon!,
                  ),
                ),
                const SizedBox(width: 10), // Espacio entre icono y texto
              ],

              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxTitleWidth),
                child: Text.rich(
                  TextSpan(
                    text: title,
                    children: [
                      if (highlight != null)
                        TextSpan(
                          text: highlight,
                          style: TextStyle(color: highlightColor),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              const SizedBox(width: gap),
              Expanded(
                child: Container(
                  height: 1,
                  color: accentColor ?? AppColors.border,
                ),
              ),
              if (action != null) ...[const SizedBox(width: gap), action!],
            ],
          );
        },
      ),
    );
  }

  static Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final value = hex.replaceFirst('#', '');
    if (value.length != 6) return null;
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return null;
    return Color(0xFF000000 | parsed);
  }
}
