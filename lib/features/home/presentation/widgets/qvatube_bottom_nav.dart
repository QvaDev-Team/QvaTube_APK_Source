import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';

/// Ítem de la barra de navegación inferior.
class QvaBottomNavItem {
  const QvaBottomNavItem({
    required this.label,
    required this.icon,
    this.activeIcon,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final IconData? activeIcon;
  final int badgeCount;
}

/// Barra de navegación inferior de QvaTube (spec §6.2).
///
/// - Píldora deslizante de 50x38px con fondo `accentSoft` y borde accent.
/// - Glow respiratorio detrás de la pestaña activa.
/// - Iconos centrados verticalmente dentro de la píldora activa (sin
///   etiquetas de texto debajo).
class QvaBottomNav extends StatefulWidget {
  const QvaBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<QvaBottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  State<QvaBottomNav> createState() => _QvaBottomNavState();
}

class _QvaBottomNavState extends State<QvaBottomNav>
    with TickerProviderStateMixin {
  static const double _pillWidth = 50;
  static const double _pillHeight = 38;

  late final AnimationController _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  late final AnimationController _slideController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  late double _pillCenter;

  @override
  void initState() {
    super.initState();
    _pillCenter = widget.currentIndex.toDouble();
    _slideController.addListener(() {
      final begin = _pillCenter;
      final end = widget.currentIndex.toDouble();
      setState(() {
        _pillCenter = begin + (end - begin) * _slideController.value;
      });
    });
  }

  @override
  void didUpdateWidget(covariant QvaBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex) {
      _slideController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.items.length;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF20A0A0B),
        border: Border(top: BorderSide(color: AppColors.borderSoft)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / count;
              return Stack(
                alignment: Alignment.topCenter,
                children: [
                  // Píldora deslizante con glow respiratorio.
                  AnimatedBuilder(
                    animation: _glowController,
                    builder: (context, child) {
                      final opacity = 0.35 + (_glowController.value * 0.35);
                      return Positioned(
                        left: slot * _pillCenter + (slot - _pillWidth) / 2,
                        top: (58 - _pillHeight) / 2,
                        child: Container(
                          width: _pillWidth,
                          height: _pillHeight,
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.accent.withValues(alpha: 0.55),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent.withValues(alpha: opacity),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  Row(
                    children: [
                      for (var index = 0; index < count; index++)
                        Expanded(
                          child: _NavButton(
                            item: widget.items[index],
                            isActive: index == widget.currentIndex,
                            onTap: () => widget.onTap(index),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  final QvaBottomNavItem item;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.accent : AppColors.textMuted;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: SizedBox(
        height: 58,
        child: Center(
          child: SizedBox(
            width: 50,
            height: 38,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedScale(
                  scale: isActive ? 1.12 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isActive ? (item.activeIcon ?? item.icon) : item.icon,
                    size: 22,
                    color: color,
                  ),
                ),
                if (item.badgeCount > 0)
                  Positioned(
                    right: 6,
                    top: 4,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 15),
                      height: 15,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                        style: AppTextStyles.mono(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentInk,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
