import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text.dart';
import 'badge_count.dart';
import 'qvatube_bottom_nav.dart';

/// Menú lateral de QvaTube para escritorio y pantallas anchas: las mismas
/// secciones que [QvaBottomNav], en vertical, con icono y nombre.
///
/// Con poco ancho ([compact]) muestra solo los iconos.
class QvaSideNav extends StatelessWidget {
  const QvaSideNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.compact = false,
  });

  final List<QvaBottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 76 : 216,
      decoration: const BoxDecoration(
        color: Color(0xF20A0A0B),
        border: Border(right: BorderSide(color: AppColors.borderSoft)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _SideNavButton(
                item: items[i],
                selected: i == currentIndex,
                compact: compact,
                onTap: () => onTap(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _SideNavButton extends StatefulWidget {
  const _SideNavButton({
    required this.item,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final QvaBottomNavItem item;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_SideNavButton> createState() => _SideNavButtonState();
}

class _SideNavButtonState extends State<_SideNavButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final selected = widget.selected;
    final color = selected ? AppColors.accent : AppColors.textSecondary;
    final icon = Icon(
      selected ? (item.activeIcon ?? item.icon) : item.icon,
      size: 22,
      color: selected || _hover ? color : AppColors.textSecondary,
    );
    // Badge de estrenos en la esquina superior derecha del icono.
    final iconWithBadge = item.badgeCount > 0
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              icon,
              Positioned(
                right: -10,
                top: -7,
                child: AppBadge(count: item.badgeCount),
              ),
            ],
          )
        : icon;

    // InkWell: ratón (cursor de mano y hover) y teclado (Tab + Intro).
    final button = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (value) => setState(() => _hover = value),
        onFocusChange: (value) => setState(() => _hover = value),
        borderRadius: BorderRadius.circular(AppRadii.md),
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        splashColor: AppColors.accent.withValues(alpha: 0.12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 46,
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 0 : 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accentSoft
                : _hover
                ? AppColors.surfaceSecondary
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.7)
                  : Colors.transparent,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.25),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          child: widget.compact
              ? Center(child: iconWithBadge)
              : Row(
                  children: [
                    iconWithBadge,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: selected || _hover
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );

    return widget.compact
        ? Tooltip(message: item.label, child: button)
        : button;
  }
}
