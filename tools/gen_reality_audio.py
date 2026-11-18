#!/usr/bin/env python3
"""Procedurally synthesised ambience & SFX for «Реальность» (original, no samples)."""
import numpy as np, wave, os
SR = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'Sanya', 'Resources', 'Reality')
rng = np.random.default_rng(11)
def save(name, x, peak=0.8):
    x = np.asarray(x, float); m = np.max(np.abs(x)) or 1; x = x / m * peak
    with wave.open(os.path.join(OUT, name + '.wav'), 'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype('<i2').tobytes())
def t(d): return np.arange(int(SR * d)) / SR
def lp(x, a):  # one-pole lowpass, a in (0,1)
    y = np.zeros_like(x); acc = 0.0
    for i, v in enumerate(x): acc += a * (v - acc); y[i] = acc
    return y
def env(n, a, r):
    e = np.ones(n); ai = int(SR * a); ri = int(SR * r)
    if ai: e[:ai] = np.linspace(0, 1, ai)
    if ri: e[-ri:] *= np.linspace(1, 0, ri) ** 2
    return e
def loopify(x, fade=0.6):
    f = int(SR * fade); y = x[f:].copy(); y[-f:] = y[-f:] * np.linspace(1, 0, f) + x[:f] * np.linspace(0, 1, f); return y
# rain
n = rng.standard_normal(SR * 11)
rain = lp(n, 0.35) * 0.7 + lp(n, 0.08) * 0.8
for _ in range(260):
    p = rng.integers(0, len(rain) - 400); L = rng.integers(60, 300)
    rain[p:p + L] += rng.standard_normal(L) * np.exp(-np.arange(L) / (L / 4)) * rng.uniform(0.3, 1.0)
save('amb_rain', loopify(rain), 0.6)
# city drone
T = t(11)
city = 0.5 * np.sin(2 * np.pi * 55 * T) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.11 * T)) + 0.3 * np.sin(2 * np.pi * 82.4 * T + np.sin(2 * np.pi * 0.3 * T))
city += 0.12 * np.sin(2 * np.pi * 220 * T) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.07 * T)) + 0.08 * np.sin(2 * np.pi * 329.6 * T) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.05 * T + 1))
traffic = lp(rng.standard_normal(len(T)), 0.03) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.09 * T) ** 2) * 3
save('amb_city', loopify(city + traffic), 0.5)
room = lp(rng.standard_normal(SR * 9), 0.04) * 2 + 0.25 * np.sin(2 * np.pi * 60 * t(9)) + 0.1 * np.sin(2 * np.pi * 120 * t(9))
save('amb_room', loopify(room), 0.4)
# sfx
def blip(): T = t(0.09); return np.sin(2 * np.pi * (900 + 600 * T / 0.09) * T) * env(len(T), 0.003, 0.06)
save('sfx_blip', blip(), 0.5)
def coin(): T = t(0.35); return (np.sin(2 * np.pi * 1318 * T) * (T < 0.08) + np.sin(2 * np.pi * 1975 * T) * (T >= 0.08)) * np.exp(-T * 9)
save('sfx_coin', coin(), 0.5)
T = t(0.25); save('sfx_error', np.sign(np.sin(2 * np.pi * 120 * T)) * env(len(T), 0.005, 0.1) * 0.6, 0.4)
T = t(0.4); save('sfx_eat', lp(rng.standard_normal(len(T)), 0.2) * (np.sin(2 * np.pi * 9 * T) > 0) * env(len(T), 0.01, 0.15), 0.4)
T = t(0.7); save('sfx_door', lp(rng.standard_normal(len(T)), 0.05) * env(len(T), 0.1, 0.4) + 0.3 * np.sin(2 * np.pi * 70 * T) * env(len(T), 0.02, 0.5), 0.6)
T = t(0.9); save('sfx_scan', np.sin(2 * np.pi * (600 + 900 * np.abs(np.sin(2 * np.pi * 1.6 * T))) * T) * env(len(T), 0.02, 0.3), 0.4)
T = t(1.6); save('sfx_sleep', sum(np.sin(2 * np.pi * f * T) * np.exp(-T * 2.2) for f in (523, 659, 784)), 0.4)
# magic: charge (rising whine + crackle)
T = t(0.65)
f = 120 + 900 * (T / 0.65) ** 2
ch = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.6 + np.sin(2 * np.pi * np.cumsum(f * 1.5) / SR) * 0.3
crack = rng.standard_normal(len(T)) * (rng.random(len(T)) > 0.985) * 1.2
save('sfx_charge', (ch + crack) * env(len(T), 0.2, 0.05), 0.6)
# blast: sub sweep + noise + crackle tail
T = t(1.4)
sweep = np.sin(2 * np.pi * np.cumsum(140 * np.exp(-T * 3) + 38) / SR) * np.exp(-T * 2.6)
noise = lp(rng.standard_normal(len(T)), 0.5) * np.exp(-T * 7) * 0.9
cr = rng.standard_normal(len(T)) * (rng.random(len(T)) > 0.97) * np.exp(-T * 2.5) * 0.8
save('sfx_blast', sweep * 1.2 + noise + cr, 0.95)
# whoosh
T = t(0.5); nn = rng.standard_normal(len(T)); a = 0.02 + 0.5 * np.sin(np.pi * T / 0.5) ** 2
y = np.zeros_like(nn); acc = 0
for i, v in enumerate(nn): acc += a[i] * (v - acc); y[i] = acc
save('sfx_whoosh', y * np.sin(np.pi * T / 0.5) ** 1.5 + 0.3 * np.sin(2 * np.pi * 60 * T) * np.exp(-T * 6), 0.8)
# hex: dissonant screech + growl
T = t(1.0)
hx = np.sin(2 * np.pi * 466 * T + 3 * np.sin(2 * np.pi * 7 * T)) * 0.4 + np.sin(2 * np.pi * 494 * T) * 0.4 + np.sign(np.sin(2 * np.pi * 58 * T)) * 0.25 * np.exp(-T * 2)
save('sfx_hex', hx * env(len(T), 0.15, 0.5), 0.6)
# sigil: shimmering bell chord
T = t(2.4)
sg = sum(np.sin(2 * np.pi * f * T + 0.4 * np.sin(2 * np.pi * 5 * T)) * np.exp(-T * k) for f, k in ((392, 1.2), (587, 1.4), (784, 1.6), (1175, 2.2), (1568, 2.8)))
sg *= env(len(T), 0.5, 0.8)
save('sfx_sigil', sg, 0.6)
print('audio ok')
