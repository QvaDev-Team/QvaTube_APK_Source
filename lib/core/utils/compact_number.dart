/// Formatea contadores grandes en forma corta: `950`, `1.9K`, `2K`, `15K`,
/// `1M`, `2.4M`, `1B`.
///
/// Se usa en los contadores que van encima de las carátulas (popularidad),
/// donde un número largo como `1234567` se sale de la tarjeta.
String formatCompactNumber(num value) {
  final n = value.round();
  if (n < 0) return '-${formatCompactNumber(-n)}';
  if (n < 1000) return '$n';

  const units = <(int, String)>[
    (1000000000, 'B'),
    (1000000, 'M'),
    (1000, 'K'),
  ];
  for (var i = 0; i < units.length; i++) {
    final (size, suffix) = units[i];
    if (n < size) continue;
    // Un decimal hasta 100 (1.9K, 25.4K) y ninguno a partir de ahí (150K).
    final scaled = n / size;
    final decimals = scaled < 100 ? 1 : 0;
    // Se trunca (no se redondea) para no anunciar más de lo que hay:
    // 1999 → 1.9K, nunca 2.0K.
    final factor = decimals == 1 ? 10 : 1;
    final truncated = (scaled * factor).floor() / factor;
    // 999 999 → "999.9K" no cabe bien; si ya llega a 1000 de la unidad, se
    // pasa a la siguiente (1M).
    if (truncated >= 1000 && i > 0) {
      final (bigSize, bigSuffix) = units[i - 1];
      return '${_trim((n / bigSize * 10).floor() / 10)}$bigSuffix';
    }
    return '${_trim(truncated)}$suffix';
  }
  return '$n';
}

/// `2.0` → `2`, `1.9` → `1.9`.
String _trim(num value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}
