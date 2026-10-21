import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Familias tipográficas de QvaTube (spec §3.1).
///
/// Las fuentes vienen empaquetadas en `assets/fonts` (Bebas Neue, Inter y
/// Roboto Mono). Cada familia declara además su fallback de sistema por si
/// la fuente no llegara a cargarse: `Arial Narrow` / `Roboto Condensed` para
/// display, `Roboto` / sistema para body y `monospace` para mono.
abstract final class AppFonts {
  const AppFonts._();

  static const String display = 'Bebas Neue';
  static const String displayFallback = 'Arial Narrow';
  static const String body = 'Inter';
  static const String bodyFallback = 'Roboto';
  static const String mono = 'Roboto Mono';
  static const String monoFallback = 'monospace';
  static const String reading = 'Georgia';

  static const List<String> displayFallbacks = [
    'Arial Narrow',
    'Roboto Condensed',
    'sans-serif-condensed',
  ];

  static const List<String> bodyFallbacks = [
    'Roboto',
    'Segoe UI',
    'sans-serif',
  ];

  static const List<String> monoFallbacks = [
    'SF Mono',
    'Menlo',
    'Consolas',
    'monospace',
  ];
}

/// Estilos de texto listos para usar (spec §3.2).
abstract final class AppTextStyles {
  const AppTextStyles._();

  static TextStyle display({
    double fontSize = 26,
    Color color = AppColors.textPrimary,
    FontWeight fontWeight = FontWeight.w400,
    double letterSpacing = 0.3,
    double height = 1.05,
  }) {
    return TextStyle(
      fontFamily: AppFonts.display,
      fontFamilyFallback: AppFonts.displayFallbacks,
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle body({
    double fontSize = 14,
    Color color = AppColors.textPrimary,
    FontWeight fontWeight = FontWeight.w400,
    double height = 1.5,
    double letterSpacing = 0,
  }) {
    return TextStyle(
      fontFamily: AppFonts.body,
      fontFamilyFallback: AppFonts.bodyFallbacks,
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle mono({
    double fontSize = 12,
    Color color = AppColors.textPrimary,
    FontWeight fontWeight = FontWeight.w500,
    double letterSpacing = 0,
  }) {
    return TextStyle(
      fontFamily: AppFonts.mono,
      fontFamilyFallback: AppFonts.monoFallbacks,
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle reading({
    double fontSize = 16,
    Color color = ReaderThemes.darkText,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    return TextStyle(
      fontFamily: AppFonts.reading,
      fontFamilyFallback: const ['Times New Roman', 'serif'],
      fontSize: fontSize,
      color: color,
      fontWeight: fontWeight,
      height: 1.7,
    );
  }
}
