#!/usr/bin/env bash
# Empaqueta el build de Linux de Flutter como AppImage (incluye libmpv y sus
# dependencias, así funciona sin instalar nada) y como .tar.gz.
#
# Uso: tool/escritorio/empaquetar_linux.sh <versión> [carpeta de salida]
# Requiere haber ejecutado `flutter build linux --release` y tener
# linuxdeploy en $LINUXDEPLOY (por defecto ./linuxdeploy-x86_64.AppImage).
set -euo pipefail

VERSION="${1:?Falta la versión}"
OUT="${2:-dist}"
BUNDLE="build/linux/x64/release/bundle"
LINUXDEPLOY="${LINUXDEPLOY:-./linuxdeploy-x86_64.AppImage}"
APPDIR="$(mktemp -d)/AppDir"

[ -x "$BUNDLE/qvatube" ] || { echo "No existe $BUNDLE/qvatube" >&2; exit 1; }
mkdir -p "$OUT"

# 1) .tar.gz: el bundle tal cual (necesita libmpv instalado en el sistema).
tar -C "$(dirname "$BUNDLE")" -czf "$OUT/QvaTube-$VERSION-linux-x64.tar.gz" \
  --transform "s,^bundle,QvaTube-$VERSION," bundle

# 2) AppImage: el bundle va entero en usr/bin (el ejecutable busca lib/ y
#    data/ junto a él) y linuxdeploy copia en usr/lib las dependencias de las
#    librerías de los plugins (libmpv y las suyas).
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/icons/hicolor/512x512/apps"
cp -a "$BUNDLE/." "$APPDIR/usr/bin/"
cp linux/packaging/qvatube.desktop "$APPDIR/usr/share/applications/"
cp linux/packaging/qvatube.png \
  "$APPDIR/usr/share/icons/hicolor/512x512/apps/qvatube.png"

libs=()
for so in "$APPDIR"/usr/bin/lib/*.so; do libs+=(--library "$so"); done

export APPIMAGE_EXTRACT_AND_RUN=1 NO_STRIP=1 VERSION
export LDAI_OUTPUT="$OUT/QvaTube-$VERSION-linux-x86_64.AppImage"
"$LINUXDEPLOY" --appdir "$APPDIR" \
  --executable "$APPDIR/usr/bin/qvatube" \
  --desktop-file "$APPDIR/usr/share/applications/qvatube.desktop" \
  --icon-file "$APPDIR/usr/share/icons/hicolor/512x512/apps/qvatube.png" \
  "${libs[@]}" \
  --output appimage

ls -la "$OUT"
