#!/bin/bash
# Compila DuoLid y lo empaqueta como build/DuoLid.app (firmado ad hoc).
#
#   scripts/build-app.sh            → build/DuoLid.app
#   scripts/build-app.sh --install  → además lo copia a /Applications y lo abre
set -euo pipefail
cd "$(dirname "$0")/.."

FLAGS=(-c release)
# SwiftPM 6.4 con solo las Command Line Tools (sin Xcode) falla con
# "Unknown error parsing property list"; en ese caso se usa el sistema de compilación nativo.
if ! swift build "${FLAGS[@]}" >/dev/null 2>&1; then
    FLAGS+=(--build-system native)
    swift build "${FLAGS[@]}" 2> >(grep -v "has been deprecated" >&2)
fi
BIN_DIR=$(swift build "${FLAGS[@]}" --show-bin-path 2>/dev/null)
APP=build/DuoLid.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DuoLid" "$APP/Contents/MacOS/DuoLid"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$APP"
echo "✓ $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x DuoLid 2>/dev/null || true
    rm -rf /Applications/DuoLid.app
    cp -R "$APP" /Applications/
    open /Applications/DuoLid.app
    echo "✓ Instalado en /Applications/DuoLid.app"
fi
