import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

IconData getIconFromName(String? iconName) {
  switch (iconName?.toLowerCase()) {
    case 'star':
      return LucideIcons.star;
    case 'spark':
      return LucideIcons.sparkles;
    case 'bolt':
      return LucideIcons.zap;
    case 'mask':
      return LucideIcons.venetianMask;
    case 'smile':
      return LucideIcons.smile;
    case 'atom':
      return LucideIcons.atom;
    case 'heart':
      return LucideIcons.heart;
    case 'ghost':
      return LucideIcons.ghost;
    default:
      return LucideIcons.circlePlay;
  }
}
