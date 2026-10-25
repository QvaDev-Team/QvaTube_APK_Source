import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';

/// Fondo común de las pantallas de autenticación.
class AuthBackdrop extends StatelessWidget {
  const AuthBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.8),
                radius: 1.2,
                colors: [Color(0x33241A16), AppColors.background],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Banner de error / aviso dentro de las pantallas de autenticación.
class AuthNotice extends StatelessWidget {
  const AuthNotice({
    super.key,
    required this.message,
    this.isError = true,
    this.icon,
  });

  final String message;
  final bool isError;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppColors.danger : AppColors.accent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isError ? const Color(0x1AFF5252) : AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(
          color: isError ? const Color(0x55FF5252) : const Color(0x55FF3D1A),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            icon ?? (isError ? Icons.error_outline : Icons.info_outline),
            size: 16,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.body(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Encabezado reutilizable de las pantallas de autenticación.
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: AppTextStyles.body(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
