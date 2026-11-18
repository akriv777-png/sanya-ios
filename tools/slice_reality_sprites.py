#!/usr/bin/env python3
"""Slice generated pixel-art sprite sheets (chroma green) into game sheets.
Game sheet: 4 cols × 5 rows of 48×72 (rows: down, up, left(mirrored right), right, cast)."""
import numpy as np, os, sys
from PIL import Image
from scipy import ndimage
ROOT = os.path.join(os.path.dirname(__file__), '..')
SRC = os.path.join(ROOT, 'design', 'reality', 'sprites')
OUT = os.path.join(ROOT, 'Sanya', 'Resources', 'Reality')
FW, FH, TARGET_H, BASE = 48, 72, 64, 70

def key(path):
    a = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    green = (g > 120) & (g > r * 1.35 + 20) & (g > b * 1.35 + 20)
    m = ~green
    m = ndimage.binary_opening(m, iterations=1)
    # despill
    mx = np.maximum(r, b)
    a[..., 1] = np.where(g > mx + 10, mx + 10, g)
    return a, m

def sprites(path, rows):
    a, m = key(path)
    lab, n = ndimage.label(ndimage.binary_dilation(m, iterations=6))
    objs = ndimage.find_objects(lab)
    boxes = []
    for i, sl in enumerate(objs):
        h = sl[0].stop - sl[0].start; w = sl[1].stop - sl[1].start
        if h < 60 or w < 25: continue
        boxes.append((sl[0].start, sl[0].stop, sl[1].start, sl[1].stop))
    # cluster into rows by vertical center
    boxes.sort(key=lambda b: (b[0] + b[1]) / 2)
    out_rows, cur = [], []
    for b in boxes:
        if cur and (b[0] + b[1]) / 2 - (cur[-1][0] + cur[-1][1]) / 2 > 80:
            out_rows.append(cur); cur = []
        cur.append(b)
    out_rows.append(cur)
    assert len(out_rows) == rows, (path, len(out_rows), [len(r) for r in out_rows])
    res = []
    for row in out_rows:
        row.sort(key=lambda b: b[2])
        assert len(row) == 4, (path, len(row))
        res.append([(a[y0:y1, x0:x1], m[y0:y1, x0:x1]) for y0, y1, x0, x1 in row])
    return res

def to_frame(rgb, mask, k, mirror=False):
    h, w = mask.shape
    rgba = np.dstack([rgb, mask * 255.0]).astype(np.uint8)
    im = Image.fromarray(rgba, 'RGBA')
    # premultiplied downscale to avoid green fringes
    pm = np.asarray(im).astype(np.float32); pm[..., :3] *= pm[..., 3:4] / 255
    nw, nh = max(1, round(w * k)), max(1, round(h * k))
    ch = [np.asarray(Image.fromarray(pm[..., i]).resize((nw, nh), Image.BOX)) for i in range(4)]
    al = ch[3]; col = np.stack(ch[:3], -1) / np.maximum(al[..., None] / 255, 1e-3)
    am = al > 110
    col = np.clip(col, 0, 255)
    fr = np.zeros((FH, FW, 4), np.uint8)
    # feet on baseline, centred horizontally on the mask centroid
    ys, xs = np.nonzero(am)
    if len(ys) == 0: return fr
    cxm = xs.mean(); bottom = ys.max()
    ox = int(round(FW / 2 - cxm)); oy = BASE - bottom
    for y, x in zip(ys, xs):
        X, Y = x + ox, y + oy
        if 0 <= X < FW and 0 <= Y < FH:
            fr[Y, X, :3] = col[y, x]; fr[Y, X, 3] = 255
    if mirror: fr = fr[:, ::-1].copy()
    return fr

def rim(fr, strength=0.38):
    a = fr[..., 3] > 0; P = np.pad(a, 1)
    left = ~P[1:-1, :-2] & a; right = ~P[1:-1, 2:] & a
    out = fr.astype(np.float32)
    mag = np.array([255, 70, 210]); cya = np.array([70, 230, 255])
    # one pixel in from the outline (sources already carry a dark outline)
    left2 = np.zeros_like(a); left2[:, 1:] = left[:, :-1]; left2 &= a & ~left
    right2 = np.zeros_like(a); right2[:, :-1] = right[:, 1:]; right2 &= a & ~right
    for m_, c in ((left2, mag), (right2, cya)):
        out[m_, :3] = out[m_, :3] * (1 - strength) + c * strength
    return np.clip(out, 0, 255).astype(np.uint8)

def build(name, walk, cast=None, recolor=None):
    rows = sprites(os.path.join(SRC, walk), 3)
    front_h = np.median([m.shape[0] for _, m in rows[0]])
    k = TARGET_H / front_h
    sheet = np.zeros((FH * 5, FW * 4, 4), np.uint8)
    order = [(0, False), (1, False), (2, True), (2, False)]   # down, up, left=mirror(right), right
    for r, (src_row, mir) in enumerate(order):
        for c, (rgb, m) in enumerate(rows[src_row]):
            fr = to_frame(recolor(rgb) if recolor else rgb, m, k, mir)
            sheet[r * FH:(r + 1) * FH, c * FW:(c + 1) * FW] = rim(fr)
    if cast:
        crow = sprites(os.path.join(SRC, cast), 1)[0]
        # cast sheet is drawn at a different zoom: normalise by the first (neutral) frame height
        kc = TARGET_H / crow[0][1].shape[0]
        for c, (rgb, m) in enumerate(crow):
            sheet[4 * FH:5 * FH, c * FW:(c + 1) * FW] = rim(to_frame(rgb, m, kc))
    else:
        sheet[4 * FH:5 * FH] = sheet[0:FH]
    Image.fromarray(sheet, 'RGBA').save(os.path.join(OUT, f'ch_{name}.png'))
    print(name, 'k=%.3f' % k)

def hue(rgb, swap):
    out = rgb.copy()
    if swap == 'teal':   # magenta/violet accents -> teal
        out = out[..., [2, 1, 0]] * np.array([0.8, 1.0, 1.0])
    elif swap == 'grey':
        g = out.mean(-1, keepdims=True); out = g + (out - g) * 0.35
        out = out * np.array([1.0, 0.95, 1.05])
    elif swap == 'warm':
        out = out * np.array([1.15, 0.95, 0.85])
    return np.clip(out, 0, 255)

build('vex', 'vex_walk_src.jpg', 'vex_cast_src.jpg')
build('alex', 'alex_walk_src.jpg')
build('lin', 'lin_walk_src.jpg')
build('walker0', 'walker_walk_src.jpg')
build('walker1', 'walker_walk_src.jpg', recolor=lambda c: hue(c, 'warm'))
build('walker2', 'walker_walk_src.jpg', recolor=lambda c: hue(c, 'grey'))
