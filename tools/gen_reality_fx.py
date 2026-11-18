#!/usr/bin/env python3
"""Original procedural sprites & FX textures for «Реальность». No third-party assets."""
import numpy as np, random, os, math
from PIL import Image, ImageFilter
OUT = os.path.join(os.path.dirname(__file__), '..', 'Sanya', 'Resources', 'Reality')

def hexc(h, a=255):
    h = h.lstrip('#'); return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)
def shade(c, f): return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (c[3],)

class C:
    def __init__(s, w, h): s.w, s.h = w, h; s.a = np.zeros((h, w, 4), np.uint8)
    def px(s, x, y, c):
        if 0 <= x < s.w and 0 <= y < s.h and c is not None: s.a[y, x] = c
    def rect(s, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w): s.px(xx, yy, c)
    def ell(s, cx, cy, rx, ry, c):
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
                if ((x + .5 - cx) / rx) ** 2 + ((y + .5 - cy) / ry) ** 2 <= 1: s.px(x, y, c)
    def outline(s, col=(6, 6, 12, 255)):
        m = s.a[..., 3] > 0; p = np.pad(m, 1)
        n = p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
        s.a[n & ~m] = col
    def img(s): return Image.fromarray(s.a, 'RGBA')
    def save(s, n): s.img().save(os.path.join(OUT, n + '.png'))

FW, FH = 24, 36

def draw(c, d, f, p, cast=0):
    """3/4 high-angle chibi-ish figure. d: 0 down 1 up 2 left 3 right."""
    skin, hair, top, top2, pants, shoes, eye = p['skin'], p['hair'], p['top'], p['top2'], p['pants'], p['shoes'], p['eye']
    bob = 1 if f in (1, 3) else 0
    y0 = 3 + bob
    # legs
    step = {0: (0, 0), 1: (-2, 2), 2: (0, 0), 3: (2, -2)}[f]
    if d in (0, 1):
        for i, lx in enumerate((8, 13)):
            ln = 8 + (step[i] // 2 if d == 0 else -step[i] // 2)
            c.rect(lx, y0 + 23, 3, ln, pants); c.rect(lx + 2, y0 + 23, 1, ln, shade(pants, 0.7))
            c.rect(lx, y0 + 23 + ln - 1, 3, 2, shoes)
    else:
        fd = 1 if d == 3 else -1
        for i, (lx, sh) in enumerate(((10, 1.0), (12, 0.75))):
            off = step[i] * fd
            c.rect(lx + off, y0 + 23, 3, 8, shade(pants, sh)); c.rect(lx + off + (1 if fd > 0 else -1), y0 + 30, 3, 2, shade(shoes, sh))
    # torso / coat
    coat = p.get('coat', 0)
    c.rect(6, y0 + 13, 12, 11 + coat, top)
    c.rect(6, y0 + 13, 12, 1, shade(top, 1.35)); c.rect(6, y0 + 14, 1, 9 + coat, shade(top, 1.15)); c.rect(17, y0 + 14, 1, 10 + coat, shade(top, 0.65))
    if d == 0:
        if p.get('trim'): c.rect(11, y0 + 14, 1, 9 + coat, p['trim']); c.rect(12, y0 + 14, 1, 9 + coat, shade(p['trim'], 0.6))
        if p.get('apron'): c.rect(8, y0 + 16, 8, 8, p['apron']); c.rect(8, y0 + 16, 8, 1, shade(p['apron'], 1.3))
        if p.get('tie'): c.rect(11, y0 + 14, 2, 6, p['tie'])
        if p.get('bandage'): c.rect(9, y0 + 12, 6, 2, hexc('e8e8ee'))
    # arms
    sw = {0: 0, 1: 1, 2: 0, 3: -1}[f]
    arm_l = p.get('cyberarm', top2)
    if cast:
        lift = 6 if cast == 1 else 8
        c.rect(3, y0 + 14 - lift, 3, 9, top2); c.rect(18, y0 + 14 - lift, 3, 9, arm_l)
        c.rect(3, y0 + 13 - lift, 3, 2, skin); c.rect(18, y0 + 13 - lift, 3, 2, skin)
    elif d in (0, 1):
        c.rect(3, y0 + 14 + sw, 3, 9, top2); c.rect(18, y0 + 14 - sw, 3, 9, arm_l)
        c.rect(3, y0 + 23 + sw, 3, 2, skin); c.rect(18, y0 + 23 - sw, 3, 2, skin if 'cyberarm' not in p else hexc('ff8a3d'))
    else:
        fd = 1 if d == 3 else -1
        c.rect(11 + sw * fd * 2, y0 + 14, 3, 9, arm_l if fd < 0 else top2); c.rect(11 + sw * fd * 2, y0 + 23, 3, 2, skin)
    # head
    c.rect(7, y0 + 1, 10, 11, skin); c.rect(16, y0 + 2, 1, 9, shade(skin, 0.78)); c.rect(7, y0 + 10, 10, 2, shade(skin, 0.85))
    st = p['style']
    def hair_top():
        c.rect(6, y0 - 1, 12, 5, hair); c.rect(7, y0 - 2, 10, 1, hair); c.rect(7, y0 - 1, 9, 1, shade(hair, 1.35))
    if d == 1:
        hair_top(); c.rect(6, y0 + 3, 12, 8, hair); c.rect(7, y0 + 4, 3, 5, shade(hair, 1.15))
        if st == 'hood': c.rect(5, y0 - 2, 14, 14, hair)
        if st == 'bun': c.rect(9, y0 - 5, 6, 4, hair)
    else:
        hair_top()
        if st == 'spiky':
            for x in (6, 8, 10, 12, 14, 16): c.px(x, y0 - 3 - (x // 2) % 2, hair); c.px(x, y0 - 2, hair)
            c.rect(6, y0 + 4, 2, 3, hair); c.rect(16, y0 + 4, 2, 2, hair); c.rect(9, y0 + 4, 3, 1, hair)
        elif st == 'messy':
            c.rect(6, y0 + 4, 3, 4, hair); c.rect(15, y0 + 4, 3, 3, hair); c.rect(9, y0 + 4, 5, 2, hair); c.px(5, y0 + 1, hair); c.px(18, y0, hair)
            if p.get('streak'): c.rect(13, y0 - 1, 2, 6, p['streak'])
        elif st == 'bun':
            c.rect(9, y0 - 5, 6, 4, hair); c.rect(6, y0 + 4, 1, 4, hair); c.rect(17, y0 + 4, 1, 4, hair)
            c.px(15, y0 - 6, hexc('8a5a3a')); c.px(16, y0 - 7, hexc('8a5a3a'))
        elif st == 'hood':
            c.rect(5, y0 - 2, 14, 6, hair); c.rect(5, y0 + 4, 2, 9, hair); c.rect(17, y0 + 4, 2, 9, hair)
            c.rect(7, y0 + 3, 10, 2, shade(hair, 0.6))
        if d == 0:
            for ex in (9, 13):
                c.rect(ex, y0 + 6, 2, 2, eye); c.px(ex, y0 + 6, shade(eye, 1.7))
            if p.get('mask'): c.rect(8, y0 + 8, 8, 3, p['mask'])
            else: c.rect(11, y0 + 9, 2, 1, shade(skin, 0.65))
            if p.get('pierce'): c.px(12, y0 + 5, hexc('d4a64a'))
        else:
            fd = 1 if d == 3 else -1
            ex = 13 if fd > 0 else 9
            c.rect(ex, y0 + 6, 2, 2, eye); c.px(ex, y0 + 6, shade(eye, 1.7))
            back = 6 if fd > 0 else 14
            c.rect(back, y0 + 3, 4, 6, hair)
        if p.get('earring') and d != 1: c.px(16 if d != 2 else 7, y0 + 7, hexc('d4a64a'))

def sheet(name, p):
    out = C(FW * 4, FH * 5)
    for d in range(4):
        for f in range(4):
            s = C(FW, FH); draw(s, d, f, p); s.outline(); out.a[d * FH:(d + 1) * FH, f * FW:(f + 1) * FW] = s.a
    for f in range(4):
        s = C(FW, FH); draw(s, 0, 0, p, cast=1 + (f % 2)); s.outline(); out.a[4 * FH:5 * FH, f * FW:(f + 1) * FW] = s.a
    out.save('ch_' + name)

S = hexc('e3bfa3'); PALE = hexc('eedad0'); TAN = hexc('b98a68')
# superseded by gen_reality_chars.py: sheet('vex', dict(skin=S, hair=hexc('16131c'), style='messy', streak=hexc('b06bff'), top=hexc('17171f'), top2=hexc('1f2029'), trim=hexc('2ef2ff'), pants=hexc('22242e'), shoes=hexc('cfd2dc'), eye=hexc('2ef2ff'), coat=2))
# superseded by gen_reality_chars.py: sheet('alex', dict(skin=PALE, hair=hexc('c4c9d4'), style='spiky', top=hexc('1c1b22'), top2=hexc('26252e'), pants=hexc('16161c'), shoes=hexc('34343e'), eye=hexc('6fe6ff'), bandage=True, earring=True, pierce=True, coat=4))
# superseded by gen_reality_chars.py: sheet('lin', dict(skin=TAN, hair=hexc('a4a4ae'), style='bun', top=hexc('7a2433'), top2=hexc('7a2433'), apron=hexc('3d2350'), pants=hexc('24202c'), shoes=hexc('121218'), eye=hexc('2a1e18'), cyberarm=hexc('7d8494')))
# superseded by gen_reality_chars.py: for i, (coat, hood) in enumerate([(hexc('22262e'), hexc('1a1c22')), (hexc('2a1f2e'), hexc('201822')), (hexc('1e2a28'), hexc('18201e'))]):
# superseded by gen_reality_chars.py:     sheet(f'walker{i}', dict(skin=S if i != 1 else TAN, hair=hood, style='hood', top=coat, top2=shade(coat, 0.85), pants=hexc('15151a'), shoes=hexc('0e0e12'), eye=hexc('6a6a80'), coat=4, mask=hexc('0c0c10') if i == 2 else None))

def umbrella(name, col):
    c = C(34, 20)
    c.ell(17, 9, 16, 8.5, shade(col, 0.55))
    c.ell(17, 8, 15, 7, col)
    for k in range(-3, 4):
        x = 17 + k * 4
        for y in range(2, 16): 
            if ((x - 17) / 15) ** 2 + ((y - 8) / 7) ** 2 <= 1 and y % 1 == 0: c.px(x, y, shade(col, 0.7))
    c.ell(13, 5, 5, 2.5, shade(col, 1.45))
    for x in range(1, 34, 2):
        y = int(9 + 8.5 * math.sqrt(max(0, 1 - ((x - 17) / 16) ** 2)))
        if 0 <= y < 20: c.px(x, y, shade(col, 1.8))
    c.rect(16, 0, 2, 2, hexc('c8c8d0'))
    c.outline((6, 6, 12, 200)); c.save(name)
# superseded by gen_reality_chars.py: umbrella('umb_magenta', hexc('b02a82')); umbrella('umb_teal', hexc('1f8a8f')); umbrella('umb_dark', hexc('2a2a38'))

# drone: 2 frames
out = C(56 * 2, 30)
for f in range(2):
    s = C(56, 30)
    s.rect(18, 10, 20, 10, hexc('2c3040')); s.rect(19, 11, 18, 7, hexc('3e4458')); s.rect(19, 11, 18, 1, hexc('6a7290'))
    s.rect(24, 18, 8, 4, hexc('1c1f2a')); s.rect(26, 19, 4, 3, hexc('ff2a3a')); s.px(27, 19, hexc('ffd0d0'))
    for (ax, ay) in ((10, 8), (46, 8), (8, 20), (48, 20)):
        s.rect(min(ax, 28), ay + 2, abs(28 - ax), 2, hexc('2a2e3a'))
        s.ell(ax, ay + 2, 7 if f == 0 else 5, 2, (150, 160, 180, 150)); s.rect(ax - 1, ay + 1, 3, 3, hexc('4a5064'))
        s.px(ax, ay + 4, hexc('ff3a3a') if (ax + f) % 2 else hexc('2ef2ff'))
    s.rect(21, 13, 3, 2, hexc('ff3a3a'))
    s.outline(); out.a[:, f * 56:(f + 1) * 56] = s.a
Image.fromarray(out.a, 'RGBA').save(os.path.join(OUT, 'ch_drone.png'))

def radial(name, size, power=2.2, ring=None):
    c = C(size, size)
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - size / 2 + .5, y - size / 2 + .5) / (size / 2)
            if ring:
                a = max(0, 1 - abs(d - ring[0]) / ring[1]) ** 2
            else:
                a = max(0, 1 - d) ** power
            if a > 0: c.px(x, y, (255, 255, 255, int(255 * min(1, a))))
    c.save(name)
radial('g_soft', 128, 2.2); radial('g_core', 64, 4.0); radial('fx_ring', 256, ring=(0.86, 0.12)); radial('fx_spark', 8, 1.5)
# ember (diamond), rain, splash
c = C(7, 7)
for y in range(7):
    for x in range(7):
        d = abs(x - 3) + abs(y - 3)
        if d <= 3: c.px(x, y, (255, 255, 255, int(255 * (1 - d / 4))))
c.save('fx_ember')
c = C(2, 16)
for y in range(16): c.px(0, y, (220, 230, 255, int(14 + y * 11))); c.px(1, y, (220, 230, 255, int(y * 6)))
c.save('fx_rain')
c = C(10, 5)
for (x, y) in [(0, 4), (1, 3), (2, 2), (3, 1), (4, 1), (5, 1), (6, 1), (7, 2), (8, 3), (9, 4)]: c.px(x, y, (230, 240, 255, 230))
c.save('fx_splash')
# smoke puff
rng = np.random.default_rng(3)
n = rng.random((64, 64)); im = Image.fromarray((n * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4))
nn = np.asarray(im).astype(float) / 255
yy, xx = np.mgrid[0:64, 0:64]; d = np.hypot(xx - 31.5, yy - 31.5) / 32
a = np.clip(np.clip(1 - d, 0, 1) ** 1.6 * (0.5 + nn), 0, 1)
arr = np.zeros((64, 64, 4), np.uint8); arr[..., :3] = 255; arr[..., 3] = (a * 255).astype(np.uint8)
Image.fromarray(arr, 'RGBA').save(os.path.join(OUT, 'fx_smoke.png'))
# light cone (apex at top)
c = C(128, 256)
for y in range(256):
    w = 6 + y * 0.42
    for x in range(128):
        dx = abs(x - 63.5) / w
        if dx < 1:
            a = (1 - dx ** 2) * (0.25 + 0.75 * (y / 255)) * (1 - (y / 256) ** 6)
            c.px(x, y, (255, 255, 255, int(200 * a)))
c.save('fx_cone')
# vignette
s = 256; c = C(s, s)
for y in range(s):
    for x in range(s):
        d = math.hypot((x - s / 2 + .5) / (s / 2), (y - s / 2 + .5) / (s / 2))
        a = min(1, max(0, (d - 0.55) / 0.75)) ** 1.6
        c.px(x, y, (0, 0, 0, int(255 * a)))
c.save('fx_vignette')
c = C(28, 10); c.ell(14, 5, 13, 4.5, (0, 0, 0, 120)); c.ell(14, 5, 9, 3, (0, 0, 0, 160)); c.save('fx_shadow')
# floating rune glyphs (original invented shapes)
glyphs = [["0010100", "0011100", "0001000", "0101010", "0011100", "0001000", "0010100"],
          ["0001000", "0011100", "0101010", "1001001", "0001000", "0010100", "0100010"],
          ["0110110", "0001000", "0001000", "0111110", "0001000", "0010100", "0100010"],
          ["1000001", "0100010", "0011100", "0001000", "0011100", "0100010", "1000001"],
          ["0001000", "0010100", "0100010", "0011100", "0001000", "0001000", "0011100"]]
out = C(16 * len(glyphs), 16)
for i, g in enumerate(glyphs):
    for y, row in enumerate(g):
        for x, v in enumerate(row):
            if v == '1': out.rect(i * 16 + 1 + x * 2, 1 + y * 2, 2, 2, (255, 255, 255, 255))
im = out.img(); glow = im.filter(ImageFilter.GaussianBlur(1.2))
base = Image.alpha_composite(glow, im); base.save(os.path.join(OUT, 'fx_glyphs.png'))
print('fx ok')
