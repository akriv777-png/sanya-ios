"""Neon sign sprites for «Реальность» street, warped to the painted sign boards.
Output: Sanya/Resources/Reality/sign_*.png (2x scale, RGBA, additive-friendly) + printed centers."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np, os
OUT = os.path.join(os.path.dirname(__file__), '..', 'Sanya', 'Resources', 'Reality')
FONT = "/usr/share/fonts/truetype/sand-box/google/Russo One/RussoOne-Regular.ttf"
S = 2  # supersample vs scene px

def neon_text(text, h, color, track=0.12, tube=True):
    f = ImageFont.truetype(FONT, int(h * S))
    widths = [f.getbbox(c)[2] - f.getbbox(c)[0] for c in text]
    gap = int(h * S * track)
    W = sum(widths) + gap * (len(text) - 1) + int(h * S * 1.6)
    Hh = int(h * S * 2.2)
    m = Image.new('L', (W, Hh), 0); d = ImageDraw.Draw(m)
    x = int(h * S * 0.8)
    for c, w in zip(text, widths):
        bb = f.getbbox(c)
        if tube:
            d.text((x - bb[0], Hh // 2 - h * S // 2 - bb[1] + int(h*S*0.02)), c, font=f, fill=0, stroke_width=max(2, int(h*S*0.07)), stroke_fill=255)
        else:
            d.text((x - bb[0], Hh // 2 - h * S // 2 - bb[1]), c, font=f, fill=255)
        x += w + gap
    return compose(m, color)

def compose(mask, color):
    a = np.asarray(mask).astype(np.float32) / 255
    g1 = np.asarray(mask.filter(ImageFilter.GaussianBlur(3 * S))).astype(np.float32) / 255
    g2 = np.asarray(mask.filter(ImageFilter.GaussianBlur(9 * S))).astype(np.float32) / 255
    col = np.array(color, np.float32) / 255
    core = np.clip(a, 0, 1)[..., None]
    rgb = core * (col * 0.35 + 0.65) + (1 - core) * col[None, None, :] * 1.0
    alpha = np.clip(core[..., 0] + g1 * 1.6 + g2 * 0.9, 0, 1)
    rgb = np.clip(rgb, 0, 1)
    out = np.dstack([rgb, alpha])
    return Image.fromarray((out * 255).astype(np.uint8), 'RGBA')

def warp(img, quad):
    """Map img rect to parallelogram quad=(TL,TR,BL) in scene px; returns (img, center)."""
    (x0, y0), (x1, y1), (x2, y2) = [(px * S, py * S) for px, py in quad]
    ux, uy = x1 - x0, y1 - y0; vx, vy = x2 - x0, y2 - y0
    w, h = img.size
    xs = [x0, x1, x2, x1 + vx]; ys = [y0, y1, y2, y1 + vy]
    pad = 24 * S
    bx, by = min(xs) - pad, min(ys) - pad
    BW, BH = int(max(xs) - bx + pad), int(max(ys) - by + pad)
    # inverse affine: dest (X,Y) -> src (u*w, v*h)
    M = np.array([[ux / w, vx / h], [uy / w, vy / h]])
    Mi = np.linalg.inv(M)
    ox, oy = x0 - bx, y0 - by
    a, b = Mi[0]; c, d = Mi[1]
    coeffs = (a, b, -(a * ox + b * oy), c, d, -(c * ox + d * oy))
    out = img.transform((BW, BH), Image.AFFINE, coeffs, resample=Image.BICUBIC)
    cx = (bx + BW / 2) / S; cy = (by + BH / 2) / S
    return out, (cx, cy)

def fit(text_img, quad, inset=0.12):
    # shrink text into quad keeping aspect: build quad inset around center
    (x0, y0), (x1, y1), (x2, y2) = quad
    cx = (x1 + x2) / 2; cy = (y1 + y2) / 2
    ux, uy = x1 - x0, y1 - y0; vx, vy = x2 - x0, y2 - y0
    import math
    L = math.hypot(ux, uy); Hq = math.hypot(vx, vy)
    w, h = text_img.size
    k = min(L * (1 - inset) / w, Hq * (1 - inset) / h)
    su, sv = w * k / L, h * k / Hq
    nx0 = cx - ux * su / 2 - vx * sv / 2; ny0 = cy - uy * su / 2 - vy * sv / 2
    return warp(text_img, ((nx0, ny0), (nx0 + ux * su, ny0 + uy * su), (nx0 + vx * sv, ny0 + vy * sv)))

def save(name, res):
    img, c = res
    img.save(os.path.join(OUT, name + '.png'))
    print(f'{name}: center I({c[0]:.0f}, {c[1]:.0f}) size {img.size[0] / S:.0f}x{img.size[1] / S:.0f}')

MAG = (255, 70, 200); GRN = (60, 255, 120); RED = (255, 60, 90); CYA = (80, 230, 255)
# noodle board (magenta frame above awning): TL(156,242) TR(283,186) BL(160,305)
save('sign_lapsha', fit(neon_text('ЛАПША', 30, MAG), ((160, 246), (280, 192), (163, 300)), 0.06))
# bar board: TL(995,213) TR(1143,290) BL(993,268); eye in the middle -> text on left part
save('sign_bar', fit(neon_text('БАР', 30, GRN), ((997, 214), (1049, 241), (996, 270)), 0.0))
def blade(text, color, w, h):
    # vertical blade sign: dark plate, neon border, stacked letters
    f = ImageFont.truetype(FONT, int(h / len(text) * 0.78 * S))
    pad = 30 * S
    W, H = w * S + pad * 2, h * S + pad * 2
    m = Image.new('L', (W, H), 0); d = ImageDraw.Draw(m)
    d.rounded_rectangle((pad, pad, pad + w * S, pad + h * S), radius=3 * S, outline=255, width=max(2, S + 1))
    step = h * S / len(text)
    for i, c in enumerate(text):
        bb = f.getbbox(c)
        d.text((W / 2 - (bb[0] + bb[2]) / 2, pad + step * i + step / 2 - (bb[1] + bb[3]) / 2), c, font=f, fill=255)
    img = compose(m, color)
    plate = Image.new('RGBA', (W, H), (0, 0, 0, 0)); pd = ImageDraw.Draw(plate)
    pd.rounded_rectangle((pad, pad, pad + w * S, pad + h * S), radius=3 * S, fill=(8, 22, 14, 235))
    plate.alpha_composite(img)
    return plate
img = blade('ВЫСОТА', GRN, 24, 100)
img.save(os.path.join(OUT, 'sign_vysota.png')); print('sign_vysota: center I(1181, 338) (alpha plate)')
# corporate panel under hex logo (top center building)
save('sign_oracle', fit(neon_text('ОРАКУЛ', 20, RED, tube=False), ((398, 128), (468, 128), (398, 146)), 0.0))
