#!/bin/bash
# Resources/AppIcon.icns dosyasını yeniden üretir (yalnızca simge tasarımı değişince gerekir).
set -euo pipefail
cd "$(dirname "$0")/.."
T="$(mktemp -d)"
swift scripts/make-icon.swift "$T/icon.png"
S="$T/AppIcon.iconset"
mkdir -p "$S" Resources
for sz in 16 32 128 256 512; do
  sips -z $sz $sz "$T/icon.png" --out "$S/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) "$T/icon.png" --out "$S/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$S" -o Resources/AppIcon.icns
sips -z 256 256 "$T/icon.png" --out docs/icon.png >/dev/null
rm -rf "$T"
echo Resources/AppIcon.icns
