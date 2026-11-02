#!/usr/bin/env bash
# Genera los parches diferenciales (BSDIFF40) de las últimas versiones
# publicadas hacia el APK nuevo. Lo usa .github/workflows/android.yml y
# también se puede ejecutar en local (ver doc/ACTUALIZACIONES_DIFERENCIALES.md).
#
# Variables de entorno:
#   NEW_APK        APK recién compilado (por defecto dist/qvatube.apk)
#   NEW_CODE       versionCode del APK nuevo (obligatorio)
#   OUT_DIR        dónde dejar los parches y patches.json (por defecto dist/patches)
#   MAX_SOURCES    cuántas versiones anteriores se parchean (por defecto 3)
#   MAX_RATIO      descarta parches que pesen más que este % del APK (por defecto 80)
#   SOURCES_DIR    carpeta con APKs viejos `qvatube-<code>.apk`. Si no se da,
#                  se descargan de GitHub (necesita DIST_REPO y GH_TOKEN).
#   DIST_REPO      repo público de distribución (ej. QvaDev-Team/QvaTube_APK)
#   ARCHIVE_TAG    release donde se archivan los APKs viejos (por defecto apk-archive)
#   BSDIFF         comando bsdiff (por defecto `bsdiff`; uso: bsdiff old new patch)
#
# Salida: $OUT_DIR/qvatube-<from>-to-<to>.bsdiff y $OUT_DIR/patches.json con
#   [{from_version_code, from_sha256, file, size_bytes, sha256}, ...]
set -euo pipefail

NEW_APK="${NEW_APK:-dist/qvatube.apk}"
NEW_CODE="${NEW_CODE:?Falta NEW_CODE}"
OUT_DIR="${OUT_DIR:-dist/patches}"
MAX_SOURCES="${MAX_SOURCES:-3}"
MAX_RATIO="${MAX_RATIO:-80}"
ARCHIVE_TAG="${ARCHIVE_TAG:-apk-archive}"
BSDIFF="${BSDIFF:-bsdiff}"

mkdir -p "$OUT_DIR"
echo '[]' > "$OUT_DIR/patches.json"

sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---------------------------------------------------------------------------
# 1) Reunir los APKs de origen (versiones anteriores ya publicadas).
# ---------------------------------------------------------------------------
if [ -z "${SOURCES_DIR:-}" ]; then
  : "${DIST_REPO:?Falta DIST_REPO}"
  SOURCES_DIR="$(mktemp -d)"

  # APKs archivados en la release $ARCHIVE_TAG (qvatube-<code>.apk).
  # Si el archivo no existe o no se puede leer, se sigue sin él (con
  # pipefail, un grep sin resultados abortaría todo el script).
  archived="$(gh release view "$ARCHIVE_TAG" --repo "$DIST_REPO" --json assets \
      --jq '.assets[].name' 2>/dev/null || true)"
  printf '%s\n' "$archived" \
    | { grep -E '^qvatube-[0-9]+\.apk$' || true; } \
    | sed -E 's/^qvatube-([0-9]+)\.apk$/\1/' \
    | awk -v new="$NEW_CODE" '$1 < new' \
    | sort -rn | head -n "$MAX_SOURCES" \
    | while read -r code; do
        echo ">> Descargando versión archivada $code"
        gh release download "$ARCHIVE_TAG" --repo "$DIST_REPO" \
          --pattern "qvatube-$code.apk" --dir "$SOURCES_DIR" --clobber
      done

  # Arranque: la versión publicada ahora mismo en "latest" (todavía no está
  # en el archivo la primera vez que corre este script).
  tmp_latest="$(mktemp -d)"
  if gh release download latest --repo "$DIST_REPO" \
       --pattern latest.json --pattern qvatube.apk --dir "$tmp_latest" 2>/dev/null; then
    prev_code="$(jq -r '.version_code // 0' "$tmp_latest/latest.json" 2>/dev/null || echo 0)"
    if [ "$prev_code" -gt 0 ] && [ "$prev_code" -lt "$NEW_CODE" ] \
       && [ ! -f "$SOURCES_DIR/qvatube-$prev_code.apk" ]; then
      echo ">> Usando la release latest actual (versión $prev_code) como origen"
      mv "$tmp_latest/qvatube.apk" "$SOURCES_DIR/qvatube-$prev_code.apk"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 2) Un parche por origen; se descartan los que no ahorran lo suficiente.
# ---------------------------------------------------------------------------
new_size="$(stat -c%s "$NEW_APK")"
new_sha="$(sha "$NEW_APK")"

shopt -s nullglob
sources=("$SOURCES_DIR"/qvatube-*.apk)
if [ ${#sources[@]} -eq 0 ]; then
  echo ">> No hay versiones anteriores: no se generan parches"
  exit 0
fi

for old in $(printf '%s\n' "${sources[@]}" | sort -t- -k2 -rn | head -n "$MAX_SOURCES"); do
  code="$(basename "$old" .apk | sed -E 's/^qvatube-//')"
  [ "$code" -lt "$NEW_CODE" ] || continue
  old_sha="$(sha "$old")"
  if [ "$old_sha" = "$new_sha" ]; then
    echo ">> $code es idéntico al APK nuevo: se omite"
    continue
  fi

  file="qvatube-$code-to-$NEW_CODE.bsdiff"
  echo ">> bsdiff $code -> $NEW_CODE"
  $BSDIFF "$old" "$NEW_APK" "$OUT_DIR/$file"

  size="$(stat -c%s "$OUT_DIR/$file")"
  ratio=$(( size * 100 / new_size ))
  if [ "$ratio" -ge "$MAX_RATIO" ]; then
    echo "   descartado: pesa el ${ratio}% del APK completo"
    rm -f "$OUT_DIR/$file"
    continue
  fi
  echo "   $(awk "BEGIN {printf \"%.1f\", $size/1048576}") MB (${ratio}% del APK)"

  jq --argjson from "$code" --arg from_sha "$old_sha" --arg file "$file" \
     --argjson size "$size" --arg sha "$(sha "$OUT_DIR/$file")" \
     '. + [{from_version_code: $from, from_sha256: $from_sha, file: $file,
            size_bytes: $size, sha256: $sha}]' \
     "$OUT_DIR/patches.json" > "$OUT_DIR/patches.json.tmp"
  mv "$OUT_DIR/patches.json.tmp" "$OUT_DIR/patches.json"
done

cat "$OUT_DIR/patches.json"
