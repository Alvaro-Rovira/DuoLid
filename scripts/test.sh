#!/bin/bash
# Ejecuta los tests del núcleo. Con solo las Command Line Tools hay que indicar dónde está
# Swift Testing y usar el sistema de compilación nativo (ver scripts/build-app.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

if swift test "$@" 2>/dev/null; then exit 0; fi

FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test --build-system native \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xlinker -F -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    "$@" 2> >(grep -v "has been deprecated" >&2)
