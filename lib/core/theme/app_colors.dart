import 'package:flutter/material.dart';

/// Tokens de color de QvaTube (ver doc/QVATUBE_FLUTTER_DESIGN_SPEC.md §2).
abstract final class AppColors {
  const AppColors._();

  // Fondos principales
  static const Color background = Color(0xFF0A0A0B);
  static const Color backgroundSecondary = Color(0xFF111113);
  static const Color surface = Color(0xFF151517);
  static const Color surfaceSecondary = Color(0xFF1C1C1F);

  // Bordes y separadores
  static const Color border = Color(0xFF242428);
  static const Color borderSoft = Color(0xFF1A1A1D);

  // Textos
  static const Color textPrimary = Color(0xFFF5F4F0);
  static const Color textSecondary = Color(0xFFA8A8AD);
  static const Color textMuted = Color(0xFF6B6B70);

  // Acento de marca
  static const Color accent = Color(0xFFFF3D1A);
  static const Color accentDim = Color(0xFFC92F12);
  static const Color accentInk = Color(0xFF1A0500);
  static const Color accentSoft = Color(0x24FF3D1A);

  // Semánticos
  static const Color danger = Color(0xFFFF5252);
  static const Color success = Color(0xFF3DDC84);
  static const Color favorite = Color(0xFFFF4D6D);
  static const Color telegram = Color(0xFF229ED9);
  static const Color whatsapp = Color(0xFF25D366);

  // Tarjetas de TV (logos oficiales sobre fondo blanco)
  static const Color tvCardBg = Color(0xFFFFFFFF);

  // Gradientes
  static const LinearGradient guestGradient = LinearGradient(
    colors: [Color(0xFFFF3D1A), Color(0xFFFF0844)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardHeaderGradient = LinearGradient(
    colors: [Color(0xFF1C1C1F), Color(0xFF151517)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient accentGradient = LinearGradient(
    colors: [accent, Color(0xFFFF0844)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Sombra/glow del botón de play.
  static const List<BoxShadow> playGlow = [
    BoxShadow(color: Color(0x59FF3D1A), blurRadius: 20, offset: Offset(0, 6)),
  ];

  /// Glow pulsante del botón invitado.
  static const List<BoxShadow> guestGlow = [
    BoxShadow(color: Color(0x73FF0844), blurRadius: 24, spreadRadius: 2),
  ];

  /// Backdrop de modales.
  static const Color modalBackdrop = Color(0xB3060504);
}

/// Temas del lector de libros (spec §2.5).
abstract final class ReaderThemes {
  const ReaderThemes._();

  static const Color darkBg = Color(0xFF121214);
  static const Color darkText = Color(0xFFE8E6E1);
  static const Color darkSurface = Color(0xFF1C1C1F);
  static const Color darkBorder = Color(0xFF2A2A2E);

  static const Color sepiaBg = Color(0xFFF2E8D5);
  static const Color sepiaText = Color(0xFF3A2F1F);
  static const Color sepiaSurface = Color(0xFFE8DBC0);
  static const Color sepiaBorder = Color(0xFFD8C8A5);

  static const Color lightBg = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF1A1A1A);
  static const Color lightSurface = Color(0xFFF2F2F3);
  static const Color lightBorder = Color(0xFFE2E2E4);
}

/// Radios de esquina (spec §4).
abstract final class AppRadii {
  const AppRadii._();

  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;
  static const double pill = 999;
}
