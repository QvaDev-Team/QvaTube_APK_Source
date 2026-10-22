import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Encabezado de sección con línea divisoria (spec §3.2).
///
/// `accent` pinta la línea divisoria con el color del género.
class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.accent, this.action});

  final String title;
  final String? accent;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final accentColor = _parseColor(accent);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.displaySmall,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: accentColor ?? AppColors.border,
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 12),
            action!,
          ],
        ],
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
