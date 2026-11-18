#!/usr/bin/env python3
"""«Реальность» character sheets v2: 32×48 frames, high 3/4 angle, banded volume shading,
baked neon rim light (magenta left / cyan right), wet top sheen. Original procedural art.
Sheet: 4 cols × 5 rows (down, up, left, right, cast) -> 128×240."""
import numpy as np, os, math
from PIL import Image
OUT = os.path.join(os.path.dirname(__file__), '..', 'Sanya', 'Resources', 'Reality')
FW, FH = 32, 48
LX, LY = -0.55, -0.8           # key light from top-left (screen coords, y down)
L = math.hypot(LX, LY); LX /= L; LY /= L

def hexc(h): h = h.lstrip('#'); return np.array([int(h[i:i+2], 16) for i in (0, 2, 4)], np.float32)

class F:
    def __init__(s):
        s.rgb = np.zeros((FH, FW, 3), np.float32); s.a = np.zeros((FH, FW), np.float32)
        s.emit = np.zeros((FH, FW), bool)
    def put(s, x, y, col, emit=False):
        x, y = int(x), int(y)
        if 0 <= x < FW and 0 <= y < FH:
            s.rgb[y, x] = col; s.a[y, x] = 1; s.emit[y, x] = emit
    def ell(s, cx, cy, rx, ry, col, shade=True, bands=4, amb=0.62, k=0.55, emit=False):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                nx = (x + .5 - cx) / rx; ny = (y + .5 - cy) / ry
                r2 = nx * nx + ny * ny
                if r2 > 1: continue
                if shade:
                    nz = math.sqrt(max(0, 1 - r2))
                    lam = max(0, -(nx * LX + ny * LY) * 0.75 + nz * 0.55)
                    v = amb + k * lam
                    v = round(v * bands) / bands
                    s.put(x, y, np.clip(col * v, 0, 255), emit)
                else: s.put(x, y, col, emit)
    def cyl(s, x0, y0, w, h, col, bands=4, taper=None):
        """vertical cylinder-ish block: shading by horizontal position; taper(y)->half width."""
        cx = x0 + w / 2
        for y in range(int(y0), int(y0 + h)):
            hw = taper(y) if taper else w / 2
            for x in range(int(cx - hw), int(math.ceil(cx + hw))):
                nx = (x + .5 - cx) / max(hw, 0.5)
                if abs(nx) > 1.05: continue
                t = (y - y0) / max(h, 1)
                lam = max(0, -nx * LX * 0.9 + 0.45) - t * 0.12
                v = round((0.6 + 0.55 * lam) * bands) / bands
                s.put(x, y, np.clip(col * v, 0, 255))
    def line(s, x0, y0, x1, y1, col, emit=False):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for i in range(n + 1):
            t = i / max(n, 1); s.put(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t), col, emit)
    def finish(s, rim=True):
        a = s.a > 0; rgb = s.rgb.copy()
        P = np.pad(a, 1)
        left = ~P[1:-1, :-2] & a; right = ~P[1:-1, 2:] & a; top = ~P[:-2, 1:-1] & a
        mag = np.array([255, 60, 200], np.float32); cya = np.array([60, 230, 255], np.float32)
        if rim:
            m = left & ~s.emit; rgb[m] = rgb[m] * 0.45 + mag * 0.55
            m = right & ~s.emit; rgb[m] = rgb[m] * 0.45 + cya * 0.55
            m = top & ~s.emit & ~left & ~right; rgb[m] = np.clip(rgb[m] * 1.25 + 28, 0, 255)
        out = np.zeros((FH, FW, 4), np.uint8)
        out[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8); out[..., 3] = (a * 255).astype(np.uint8)
        # dark outline
        n = (P[:-2, 1:-1] | P[2:, 1:-1] | P[1:-1, :-2] | P[1:-1, 2:]) & ~a
        out[n] = (8, 6, 14, 255)
        return out

def draw(f, d, fr, p, cast=0):
    cx = 16
    bob = 1 if fr in (1, 3) else 0
    y0 = 2 + bob
    skin, hair, top, top2, pants, shoes, eye = (p[k] for k in ('skin', 'hair', 'top', 'top2', 'pants', 'shoes', 'eye'))
    coat = p.get('coat', 0)
    stride = {0: 0, 1: 2, 2: 0, 3: -2}[fr]
    # ---------- legs ----------
    leg_top = y0 + 33
    if d in (0, 1):
        for i, lx in enumerate((cx - 4.5, cx + 1.5)):
            off = stride if i == 0 else -stride
            ln = 10 + (off // 2 if d == 0 else -off // 2)
            f.cyl(lx, leg_top, 3.5, ln, pants)
            f.ell(lx + 1.7, leg_top + ln, 2.6, 1.6, shoes)
    else:
        fd = 1 if d == 3 else -1
        for i, sh in ((1, 0.7), (0, 1.0)):
            off = (stride if i == 0 else -stride) * fd
            f.cyl(cx - 2 + off, leg_top, 4, 10, pants * sh)
            f.ell(cx + off + fd * 1.2, leg_top + 10, 3, 1.5, shoes * sh)
    # ---------- torso / coat (seen from above: wide shoulders, tapering) ----------
    side = d in (2, 3)
    sh_w = 6.5 if side else 9.5
    def taper(y):
        t = (y - (y0 + 18)) / 18
        return sh_w - 1.6 * min(t, 0.6) + (1.6 * max(0, t - 0.6) * 2 if coat else 0)
    f.cyl(cx - sh_w, y0 + 18, sh_w * 2, 17 + coat, top, taper=taper)
    # shoulder caps (top surface catches the light)
    if not side:
        f.ell(cx - 6.5, y0 + 19.5, 4, 2.6, top * 1.08); f.ell(cx + 6.5, y0 + 19.5, 4, 2.6, top * 1.0)
    else:
        f.ell(cx, y0 + 19.5, 5.5, 2.6, top * 1.08)
    if d == 0:
        if p.get('trim') is not None:
            f.line(cx - 1, y0 + 21, cx - 1, y0 + 34 + coat, p['trim'], emit=True)
            f.line(cx - 6, y0 + 33 + coat, cx - 2, y0 + 33 + coat, p['trim'] * 0.8, emit=True)
        if p.get('collar') is not None:
            f.line(cx - 4, y0 + 18, cx - 1, y0 + 22, p['collar']); f.line(cx + 3, y0 + 18, cx, y0 + 22, p['collar'])
        if p.get('apron') is not None:
            f.cyl(cx - 5, y0 + 24, 10, 11, p['apron'])
            f.line(cx - 4, y0 + 24, cx + 4, y0 + 24, p['apron'] * 1.4)
        if p.get('belt') is not None: f.line(cx - 7, y0 + 29, cx + 7, y0 + 29, p['belt'])
    if d == 1 and p.get('trim') is not None:
        f.line(cx - 6, y0 + 33 + coat, cx + 6, y0 + 33 + coat, p['trim'] * 0.8, emit=True)
    # ---------- arms ----------
    sw = {0: 0, 1: 1.5, 2: 0, 3: -1.5}[fr]
    arm_r = p.get('cyberarm', top2)
    if cast:
        lift = 5 if cast == 1 else 8
        for sx, col in ((-1, top2), (1, arm_r)):
            ax = cx + sx * 9
            f.line(ax, y0 + 21, ax + sx * 1, y0 + 21 - lift, col); f.line(ax - sx, y0 + 21, ax, y0 + 21 - lift, col * 0.8)
            f.line(ax + sx, y0 + 21, ax + sx * 2, y0 + 21 - lift, col * 0.8)
            hx, hy = ax + sx * 1.5, y0 + 20 - lift
            f.ell(hx, hy, 1.8, 1.8, skin)
            mc = p.get('magic', hexc('c070ff'))
            f.put(hx, hy - 2, np.clip(mc * 1.3, 0, 255), emit=True); f.put(hx - sx, hy - 2, mc, emit=True)
    elif d in (0, 1):
        for sx, s_, col in ((-1, sw, top2), (1, -sw, arm_r)):
            ax = cx + sx * 9.6
            f.cyl(ax - 1.8, y0 + 20 + s_ * 0.5, 3.6, 12, col)
            hc = skin if (col is top2 or 'cyberarm' not in p) else hexc('8a909c')
            f.ell(ax, y0 + 33 + s_, 1.9, 1.7, hc)
            if col is arm_r and 'cyberarm' in p: f.put(ax, y0 + 26 + s_, hexc('ff8a3d'), emit=True)
    else:
        fd = 1 if d == 3 else -1
        ax = cx + sw * fd * 1.6
        f.cyl(ax - 1.8, y0 + 20, 3.6, 12, arm_r if fd < 0 else top2)
        f.ell(ax + sw * fd * 0.6, y0 + 33, 1.9, 1.7, skin)
    # neck
    if p.get('bandage') and d == 0: f.ell(cx, y0 + 17.5, 3.2, 1.6, hexc('e6e6ee'), bands=3)
    else: f.ell(cx, y0 + 17.5, 2.6, 1.5, skin * 0.75, shade=False)
    # ---------- head (high angle: crown dominant, face foreshortened) ----------
    hcx = cx + (1 if d == 3 else -1 if d == 2 else 0)
    if d != 1: f.ell(hcx, y0 + 12, 6.4, 5.6, skin)
    st = p['style']
    crown_cy = y0 + 8.5 if d != 1 else y0 + 10
    crown_ry = 6.6 if d != 1 else 8
    if st == 'hood':
        f.ell(hcx, crown_cy + 1, 8.6, crown_ry + 1.4, hair)
        if d == 0: f.ell(hcx, y0 + 13, 5.2, 4.2, skin * 0.55, shade=False); f.ell(hcx, y0 + 12.5, 4.6, 3.6, skin)
        elif d in (2, 3):
            fd = 1 if d == 3 else -1
            f.ell(hcx + fd * 3, y0 + 13, 3.6, 3.6, skin)
    else:
        f.ell(hcx, crown_cy, 7.4, crown_ry, hair)
        if st == 'spiky':
            for k in range(-3, 4):
                tx = hcx + k * 2.3; ty = crown_cy - crown_ry + (1 if k % 2 else -1)
                f.line(hcx + k * 1.6, crown_cy - 2, tx, ty - 1.5, hair * 1.15)
            if d == 0:
                for k in (-5, -2, 1, 4): f.line(hcx + k, y0 + 9, hcx + k + 0.5, y0 + 12, hair * 1.05)
        elif st == 'messy':
            if d == 0:
                for k in (-6, -3, 0, 3): f.line(hcx + k, y0 + 9, hcx + k + 1.5, y0 + 12.5, hair)
                f.line(hcx + 6, y0 + 8, hcx + 6.5, y0 + 13, hair)
            if p.get('streak') is not None:
                f.line(hcx + 2, crown_cy - crown_ry + 1, hcx + 3.5, crown_cy + 3, p['streak'], emit=True)
                f.line(hcx + 3, crown_cy - crown_ry + 1, hcx + 4.5, crown_cy + 3, p['streak'] * 0.75, emit=True)
        elif st == 'bun':
            f.ell(hcx, crown_cy - crown_ry + 1.5, 3.4, 2.8, hair * 1.05)
            f.line(hcx + 2, crown_cy - crown_ry - 1, hcx + 5, crown_cy - crown_ry - 3, hexc('9a6a40'))
            if d == 0: f.line(hcx - 6, y0 + 9, hcx - 6, y0 + 14, hair); f.line(hcx + 6, y0 + 9, hcx + 6, y0 + 14, hair)
        # parting highlight
        f.line(hcx - 3, crown_cy - crown_ry + 2, hcx - 1, crown_cy - crown_ry + 1.5, np.clip(hair * 1.6 + 30, 0, 255))
    # face details
    if d == 0:
        glow = p.get('eye_glow', False)
        for ex in (hcx - 3, hcx + 2):
            f.put(ex, y0 + 13, eye, emit=glow); f.put(ex + 1, y0 + 13, np.clip(eye * 1.5, 0, 255), emit=glow)
        if p.get('mask') is not None:
            for x in range(int(hcx - 4), int(hcx + 5)): f.put(x, y0 + 15, p['mask']); f.put(x, y0 + 16, p['mask'] * 0.8)
        else: f.put(hcx, y0 + 15.5, skin * 0.62)
        if p.get('plaster'): f.put(hcx + 3, y0 + 14.5, hexc('f0e0d0')); f.put(hcx + 4, y0 + 14.5, hexc('e0cdb8'))
        if p.get('pierce'): f.put(hcx - 0.5, y0 + 12, hexc('e8c060'), emit=True)
    elif d in (2, 3) and st != 'hood':
        fd = 1 if d == 3 else -1
        ex = hcx + fd * 3
        f.put(ex, y0 + 13, eye, emit=p.get('eye_glow', False))
        f.ell(hcx - fd * 2.5, y0 + 11, 4, 4.5, hair)
    elif d in (2, 3):
        fd = 1 if d == 3 else -1
        f.put(hcx + fd * 4, y0 + 13, eye)
    if p.get('earring') and d in (0, 2, 3):
        f.put(hcx + (6 if d != 2 else -6), y0 + 14, hexc('e8c060'), emit=True)
    if p.get('armband') and d in (0, 3): f.line(cx + 8.5, y0 + 26, cx + 10.5, y0 + 26, hexc('e6e6ee'))

def sheet(name, p):
    out = np.zeros((FH * 5, FW * 4, 4), np.uint8)
    for d in range(4):
        for fr in range(4):
            f = F(); draw(f, d, fr, p); out[d*FH:(d+1)*FH, fr*FW:(fr+1)*FW] = f.finish(rim=p.get('rim', True))
    for fr in range(4):
        f = F(); draw(f, 0, 0, p, cast=1 + (fr % 2)); out[4*FH:5*FH, fr*FW:(fr+1)*FW] = f.finish(rim=p.get('rim', True))
    Image.fromarray(out, 'RGBA').save(os.path.join(OUT, 'ch_' + name + '.png'))

S = hexc('e3bfa3'); PALE = hexc('f0dcd2'); TAN = hexc('b98a68')
sheet('vex', dict(skin=S, hair=hexc('1d1826'), style='messy', streak=hexc('b46cff'), top=hexc('22222e'), top2=hexc('2a2b38'),
                  trim=hexc('2ef2ff'), collar=hexc('3a3b4a'), pants=hexc('262836'), shoes=hexc('d6d9e2'), eye=hexc('2ef2ff'),
                  eye_glow=True, coat=3, magic=hexc('c070ff')))
sheet('alex', dict(skin=PALE, hair=hexc('cfd4de'), style='spiky', top=hexc('24232c'), top2=hexc('2e2d38'), pants=hexc('1c1c24'),
                   shoes=hexc('3a3a46'), eye=hexc('6fe6ff'), eye_glow=True, bandage=True, earring=True, pierce=True,
                   plaster=True, armband=True, coat=2, magic=hexc('9a7cff')))
sheet('lin', dict(skin=TAN, hair=hexc('b0b0ba'), style='bun', top=hexc('8a2a3a'), top2=hexc('8a2a3a'), apron=hexc('46285c'),
                  pants=hexc('2a2532'), shoes=hexc('16161c'), eye=hexc('2a1e18'), cyberarm=hexc('8a909c'), belt=hexc('2a1a20')))
for i, (coat, hood) in enumerate([(hexc('2a2e38'), hexc('20232c')), (hexc('34283a'), hexc('2a2030')), (hexc('243430'), hexc('1c2a26'))]):
    sheet(f'walker{i}', dict(skin=S if i != 1 else TAN, hair=hood, style='hood', top=coat, top2=coat * 0.85, pants=hexc('18181e'),
                             shoes=hexc('101014'), eye=hexc('7a7a90'), coat=4, mask=hexc('0e0e12') if i == 2 else None,
                             belt=hexc('121218') if i == 0 else None))

# ---------- umbrellas: canopy seen from a high angle, covers head + shoulders ----------
def umbrella(name, col, n_ribs=8):
    W, H = 48, 34
    cx, cy, rx, ry = 24, 16, 22.5, 15
    rgb = np.zeros((H, W, 3), np.float32); a = np.zeros((H, W), np.float32)
    for y in range(H):
        for x in range(W):
            nx = (x + .5 - cx) / rx; ny = (y + .5 - cy) / ry
            r = math.hypot(nx, ny)
            if r > 1: continue
            ang = math.atan2(ny, nx)
            seg = (ang / (2 * math.pi) * n_ribs) % 1
            # dome shading + panel scallop (each panel bulges)
            nz = math.sqrt(max(0, 1 - r * r))
            lam = max(0, -(nx * LX + ny * LY) * 0.7 + nz * 0.5)
            bulge = math.sin(seg * math.pi) * 0.12
            v = 0.55 + 0.6 * lam + bulge
            if abs(seg - 0) < 0.06 or abs(seg - 1) < 0.06: v *= 0.68   # ribs
            v = round(v * 5) / 5
            c = col * v
            if r > 0.9: c = c * 0.75 + np.array([150, 150, 170]) * 0.15      # wet edge
            rgb[y, x] = c; a[y, x] = 1
    # specular wet highlights (top-left)
    for y in range(H):
        for x in range(W):
            nx = (x + .5 - cx) / rx; ny = (y + .5 - cy) / ry
            d = math.hypot(nx + 0.38, ny + 0.42)
            if a[y, x] and d < 0.22: rgb[y, x] = np.clip(rgb[y, x] * 1.35 + 40, 0, 255)
    # tip + drip beads on rim
    rgb[cy, cx] = (210, 210, 220); rgb[cy - 1, cx] = (240, 240, 250)
    for k in range(n_ribs):
        ang = k / n_ribs * 2 * math.pi
        x = int(cx + math.cos(ang) * rx * 0.97); y = int(cy + math.sin(ang) * ry * 0.97)
        if 0 <= x < W and 0 <= y < H: rgb[y, x] = (200, 230, 255); a[y, x] = 1
    out = np.zeros((H, W, 4), np.uint8); out[..., :3] = np.clip(rgb, 0, 255); out[..., 3] = a * 255
    P = np.pad(a > 0, 1); n = (P[:-2, 1:-1] | P[2:, 1:-1] | P[1:-1, :-2] | P[1:-1, 2:]) & ~(a > 0)
    out[n] = (8, 6, 14, 220)
    Image.fromarray(out, 'RGBA').save(os.path.join(OUT, name + '.png'))
umbrella('umb_magenta', hexc('c0308f')); umbrella('umb_teal', hexc('22989e')); umbrella('umb_dark', hexc('343446'))
print('ok')
