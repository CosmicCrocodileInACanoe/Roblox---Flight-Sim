#!/bin/sh
# Dev helper: render each aircraft from its cockpit camera (interior shown, nose shell hidden).
set -e
cd "$(dirname "$0")/../.."
OUT=${1:-/tmp/aircraft-preview}
mkdir -p "$OUT" tests/generated
{ printf 'return [=====['; cat src/server/AircraftBuilder.luau; printf ']=====]\n'; } > tests/generated/AircraftBuilder_src.luau
luau tests/dev/dump_cockpit.luau > "$OUT/cockpit_parts.txt"
python3 - "$OUT" <<'PY'
import sys, importlib.util
spec = importlib.util.spec_from_file_location("r", "tests/dev/render.py"); r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
out = sys.argv[1]
parts = r.load(f"{out}/cockpit_parts.txt")
eyes = {"kestrel72": (-0.45, 0.55, -10.4), "meridian200": (-0.55, 0.85, -15.3), "atlas400": (-0.6, 4.05, -31.4), "celestia800": (-0.6, 1.0, -32.6)}
S = 1 / 0.28
for ac, ps in parts.items():
    e = [v * S for v in eyes[ac]]
    r.render_cockpit(ps, e, f"{out}/{ac}_cockpit.png")
    r.render_cockpit(ps, e, f"{out}/{ac}_cockpit_left.png", look=(-1, -0.15, -0.3))
PY
