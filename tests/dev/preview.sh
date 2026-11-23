#!/bin/sh
# Dev helper: dump every aircraft's parts through the Roblox mock and render PNG previews.
# Usage: sh tests/dev/preview.sh OUTDIR   (needs python3 with numpy + pillow)
set -e
cd "$(dirname "$0")/../.."
OUT=${1:-/tmp/aircraft-preview}
mkdir -p "$OUT" tests/generated
{ printf 'return [=====['; cat src/server/AircraftBuilder.luau; printf ']=====]\n'; } > tests/generated/AircraftBuilder_src.luau
# optional: PREVIEW_IDS="id1 id2" renders only those aircraft
rm -f tests/generated/only_preview.luau
if [ -n "$PREVIEW_IDS" ]; then
	{ printf 'return {'; for id in $PREVIEW_IDS; do printf '"%s",' "$id"; done; printf '}\n'; } > tests/generated/only_preview.luau
fi
luau tests/dev/dump.luau > "$OUT/parts.txt"
python3 tests/dev/render.py "$OUT/parts.txt" "$OUT"
