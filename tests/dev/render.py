# Tiny z-buffer renderer for part dumps (class, CFrame, Size) -> PNG previews.
import sys, math, numpy as np
from PIL import Image

def load(path):
    parts = {}
    for line in open(path):
        f = line.split()
        if len(f) < 21: continue
        ac, shape, name = f[0], f[1], f[2]
        v = list(map(float, f[3:]))
        p = np.array(v[0:3]); r = np.array(v[3:6]); u = np.array(v[6:9]); b = np.array(v[9:12])
        s = np.array(v[12:15]); col = np.array(v[15:18])
        parts.setdefault(ac, []).append((shape, name, p, r, u, b, s, col))
    return parts

def box_tris(s):
    x, y, z = s / 2
    V = np.array([[sx*x, sy*y, sz*z] for sx in (-1,1) for sy in (-1,1) for sz in (-1,1)])
    F = [(0,1,3),(0,3,2),(4,6,7),(4,7,5),(0,4,5),(0,5,1),(2,3,7),(2,7,6),(0,2,6),(0,6,4),(1,5,7),(1,7,3)]
    return V, F

def wedge_tris(s):
    x, y, z = s / 2
    # full bottom (y=-) and back (z=+) faces; slope from top-back to bottom-front
    V = np.array([[-x,-y,-z],[x,-y,-z],[-x,-y,z],[x,-y,z],[-x,y,z],[x,y,z]])
    F = [(0,2,3),(0,3,1),(2,4,5),(2,5,3),(0,1,5),(0,5,4),(0,4,2),(1,3,5)]
    return V, F

def cyl_tris(s, n=18):
    L, r = s[0] / 2, min(s[1], s[2]) / 2
    V = [[-L,0,0],[L,0,0]]
    for i in range(n):
        a = 2*math.pi*i/n
        V.append([-L, r*math.cos(a), r*math.sin(a)]); V.append([L, r*math.cos(a), r*math.sin(a)])
    F = []
    for i in range(n):
        j = (i+1) % n
        a0, a1, b0, b1 = 2+2*i, 3+2*i, 2+2*j, 3+2*j
        F += [(a0,b0,b1),(a0,b1,a1),(0,b0,a0),(1,a1,b1)]
    return np.array(V), F

def ball_tris(s, n=10):
    r = min(s) / 2
    V, F = [], []
    for i in range(n+1):
        t = math.pi * i / n
        for j in range(2*n):
            p = 2*math.pi*j/(2*n)
            V.append([r*math.sin(t)*math.cos(p), r*math.cos(t), r*math.sin(t)*math.sin(p)])
    for i in range(n):
        for j in range(2*n):
            a = i*2*n + j; b = i*2*n + (j+1) % (2*n); c = a + 2*n; d = b + 2*n
            F += [(a,c,d),(a,d,b)]
    return np.array(V), F

def mesh(part):
    shape, name, p, r, u, b, s, col = part
    if shape == "wedge": V, F = wedge_tris(s)
    elif shape == "Cylinder": V, F = cyl_tris(s)
    elif shape == "Ball": V, F = ball_tris(s)
    elif shape == "ecyl":
        V, F = cyl_tris(np.array([2.0, 2.0, 2.0]), 28)
        V = V * (s / 2)
    elif shape == "ellipsoid":
        V, F = ball_tris(np.array([2.0, 2.0, 2.0]), 20)
        V = V * (s / 2)
    else: V, F = box_tris(s)
    R = np.stack([r, u, b], axis=1)
    W = V @ R.T + p
    return W, F, col

def render(parts, view, out, W=1100, H=700, title=None):
    eye, target = np.array(view[0], float), np.array(view[1], float)
    fwd = target - eye; fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, [0,1,0]); right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    light = np.array([0.4, 0.8, 0.45]); light /= np.linalg.norm(light)
    tris, cols = [], []
    for part in parts:
        Wv, F, col = mesh(part)
        for f in F:
            tris.append(Wv[list(f)]); cols.append(col)
    tris = np.array(tris); cols = np.array(cols)
    rel = tris - eye
    cx = rel @ right; cy = rel @ up; cz = rel @ fwd
    ortho = view[2] if len(view) > 2 else None
    if ortho:
        sx = cx / ortho * (W/2) + W/2; sy = -cy / ortho * (W/2) + H/2
    else:
        f = (W/2) / math.tan(math.radians(25))
        cz = np.maximum(cz, 0.1)
        sx = cx / cz * f + W/2; sy = -cy / cz * f + H/2
    n = np.cross(tris[:,1]-tris[:,0], tris[:,2]-tris[:,0])
    nl = np.linalg.norm(n, axis=1, keepdims=True); nl[nl == 0] = 1; n /= nl
    shade = 0.35 + 0.65*np.abs(n @ light)
    img = np.ones((H, W, 3)) * np.array([0.82, 0.88, 0.95])
    zb = np.full((H, W), np.inf)
    for i in range(len(tris)):
        xs, ys, zs = sx[i], sy[i], cz[i]
        x0, x1 = int(max(0, math.floor(xs.min()))), int(min(W-1, math.ceil(xs.max())))
        y0, y1 = int(max(0, math.floor(ys.min()))), int(min(H-1, math.ceil(ys.max())))
        if x1 < x0 or y1 < y0: continue
        X, Y = np.meshgrid(np.arange(x0, x1+1)+0.5, np.arange(y0, y1+1)+0.5)
        d = (ys[1]-ys[2])*(xs[0]-xs[2]) + (xs[2]-xs[1])*(ys[0]-ys[2])
        if abs(d) < 1e-9: continue
        l0 = ((ys[1]-ys[2])*(X-xs[2]) + (xs[2]-xs[1])*(Y-ys[2])) / d
        l1 = ((ys[2]-ys[0])*(X-xs[2]) + (xs[0]-xs[2])*(Y-ys[2])) / d
        l2 = 1 - l0 - l1
        m = (l0 >= 0) & (l1 >= 0) & (l2 >= 0)
        if not m.any(): continue
        z = l0*zs[0] + l1*zs[1] + l2*zs[2]
        sub = zb[y0:y1+1, x0:x1+1]
        m &= z < sub
        sub[m] = z[m]
        img[y0:y1+1, x0:x1+1][m] = cols[i] * shade[i]
    Image.fromarray((np.clip(img,0,1)*255).astype(np.uint8)).save(out)

if __name__ == "__main__":
    parts = load(sys.argv[1]); outdir = sys.argv[2]
    S = 1/0.28
    for ac, ps in parts.items():
        # scale views by aircraft size
        ext = max(np.abs(np.array([p[2] for p in ps])).max(axis=0))
        d = ext * 2.3
        render(ps, ([d*0.85, d*0.35, -d*0.75], [0, 0, ext*0.05]), f"{outdir}/{ac}_three_quarter.png")
        render(ps, ([-d*0.8, d*0.2, d*0.9], [0, 0, 0]), f"{outdir}/{ac}_rear.png")
        render(ps, ([0, d*3, 0.001], [0, 0, 0], ext*1.1), f"{outdir}/{ac}_top.png")
        render(ps, ([d*3, 0, 0], [0, 0, 0], ext*1.1), f"{outdir}/{ac}_side.png")
