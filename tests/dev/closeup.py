# Dev helper: close-up renders of each aircraft's nose/cockpit glazing and first engine.
# Usage: python3 tests/dev/closeup.py PARTS_TXT OUTDIR  (after tests/dev/preview.sh)
import sys, importlib.util, os
import numpy as np
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("r", os.path.join(here, "render.py")); r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
parts = r.load(sys.argv[1]); out = sys.argv[2]
S = 1 / 0.28
for ac, ps in parts.items():
    def centre(names):
        pts = [p[2] for p in ps if p[1] in names]
        return np.mean(pts, axis=0) if pts else None
    span = max(abs(p[2][0]) for p in ps)
    nose = min(ps, key=lambda p: p[2][2])[2]
    tgt = nose + np.array([0, 0.6*S, 3*S])
    d = max(4, span / S * 0.25) * S
    r.render(ps, (tgt + np.array([d*0.9, d*0.45, -d*1.1]), tgt), f"{out}/{ac}_nose.png")
    eng = [p for p in ps if p[1] in ("FanHub",)]
    if eng:
        e = min(eng, key=lambda p: p[2][0])[2]
        de = max(2.5, span / S * 0.12) * S
        r.render(ps, (e + np.array([-de*0.8, de*0.25, -de*1.2]), e + np.array([0, 0, 1.5*S])), f"{out}/{ac}_engine.png")
        r.render(ps, (e + np.array([-de*1.4, -de*0.3, de*1.0]), e + np.array([0, 0, 1.0*S])), f"{out}/{ac}_engine_rear.png")
