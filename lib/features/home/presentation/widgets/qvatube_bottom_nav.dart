import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import '../../../../core/widgets/focus_ring.dart';

const double _navBarHeight = 66;
const double _navLabelGap = 4;
const double _navLabelHeight = 13;

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
/// - Píldora deslizante de 50x34px con fondo `accentSoft` y borde accent.
/// - Glow respiratorio detrás de la pestaña activa.
/// - La etiqueta de la pestaña activa se muestra debajo del icono.
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
  // Tamaño máximo de la píldora activa. El tamaño real se calcula en el
  // layout: nunca puede pasar del ancho de la casilla, así el óvalo no se
  // sale ni se pisa con los vecinos (ni en el primer ni en el último icono).
  static const double _maxPillWidth = 50;
  static const double _maxPillHeight = 34;
  static const double _pillWidthFactor = 0.78;
  static const double _pillHeightFactor = 0.72;

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
          height: _navBarHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final slot = constraints.maxWidth / count;
                final pillWidth = math.min(
                  _maxPillWidth,
                  slot * _pillWidthFactor,
                );
                final pillHeight = math.min(
                  _maxPillHeight,
                  slot * _pillHeightFactor,
                );
                final pillRadius = pillHeight / 2;
                final pillTop =
                    (_navBarHeight -
                        (pillHeight + _navLabelGap + _navLabelHeight)) /
                    2;
                return Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    // Píldora deslizante con glow respiratorio.
                    AnimatedBuilder(
                      animation: _glowController,
                      builder: (context, child) {
                        final opacity = 0.22 + (_glowController.value * 0.20);
                        return Positioned(
                          left: slot * _pillCenter + (slot - pillWidth) / 2,
                          top: pillTop,
                          child: Container(
                            width: pillWidth,
                            height: pillHeight,
                            decoration: BoxDecoration(
                              color: AppColors.accentSoft,
                              // Radio = alto/2 → óvalo perfecto.
                              borderRadius: BorderRadius.circular(pillRadius),
                              border: Border.all(
                                color: AppColors.accent.withValues(alpha: 0.6),
                              ),
                              boxShadow: [
                                // Halo interior suave (no se corta en los
                                // extremos de la barra).
                                BoxShadow(
                                  color: AppColors.accent.withValues(
                                    alpha: opacity,
                                  ),
                                  blurRadius: 8,
                                  spreadRadius: 0,
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
                              pillWidth: pillWidth,
                              pillHeight: pillHeight,
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
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.isActive,
    required this.onTap,
    required this.pillWidth,
    required this.pillHeight,
  });

  final QvaBottomNavItem item;
  final bool isActive;
  final VoidCallback onTap;
  final double pillWidth;
  final double pillHeight;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.accent : AppColors.textMuted;

    return FocusRing(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: SizedBox(
          height: _navBarHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: pillWidth,
                height: pillHeight,
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
                        right: 0,
                        top: 0,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 13),
                          height: 13,
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            // Borde del color de fondo para despegarlo del icono.
                            border: Border.all(
                              color: AppColors.background,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                            style: AppTextStyles.mono(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accentInk,
                            ).copyWith(height: 1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: _navLabelGap),
              SizedBox(
                height: _navLabelHeight,
                child: AnimatedOpacity(
                  opacity: isActive ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      style: AppTextStyles.body(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
