#!/usr/bin/env python3
"""Erzeugt alle Audiodateien des Spiels synthetisch (keine Fremdaufnahmen, keine Lizenzen nötig).
Aufruf: python3 tools/gen_audio.py   ->  assets/audio/*.wav (16 bit, mono, 22,05 kHz)"""
import numpy as np, wave, os
SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(112)

def t(sec): return np.arange(int(SR * sec)) / SR
def env(n, a=0.005, r=0.02):
    e = np.ones(n); na = max(1, int(SR * a)); nr = max(1, int(SR * r))
    e[:na] = np.linspace(0, 1, na); e[-nr:] = np.linspace(1, 0, nr); return e
def tone(f, sec, vol=0.5, a=0.005, r=0.02):
    x = np.sin(2 * np.pi * f * t(sec)); return x * env(len(x), a, r) * vol
def silence(sec): return np.zeros(int(SR * sec))
def lowpass(x, k):
    y = np.empty_like(x); acc = 0.0
    for i, v in enumerate(x):
        acc += (v - acc) * k; y[i] = acc
    return y
def save(name, x):
    x = np.clip(x, -1, 1)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32000).astype("<i2").tobytes())
    print(name, round(len(x) / SR, 2), "s")

# Telefon: zweistimmiger Triller, Ruf – Pause (Schleife 3 s)
def trill(sec):
    tt = t(sec); mod = (np.sin(2 * np.pi * 22 * tt) > 0)
    x = np.where(mod, np.sin(2 * np.pi * 1320 * tt), np.sin(2 * np.pi * 1050 * tt))
    x += 0.3 * np.sin(2 * np.pi * 2640 * tt)
    return x * env(len(x), 0.01, 0.05) * 0.35
# einmaliges, kurzes Klingeln bei neuem Notruf (kein Dauerklingeln)
def ring(sec):
    x = trill(sec) / 0.35 * 0.62
    return x
save("phone", np.concatenate([ring(0.45), silence(0.12), ring(0.45)]))

# Alarmierung: eigener Dreiklang-Gong + kurze Tonfolge
def gong(f, sec, vol):
    tt = t(sec); x = np.sin(2 * np.pi * f * tt) + 0.5 * np.sin(2 * np.pi * f * 2.01 * tt) + 0.25 * np.sin(2 * np.pi * f * 3.02 * tt)
    return x * np.exp(-tt * 3.2) * vol * env(len(x), 0.003, 0.05)
alarm = np.concatenate([gong(659.3, 0.55, 0.33), gong(523.3, 0.55, 0.33), gong(392.0, 1.1, 0.36)])
save("alarm", alarm)

# Funk: Rauschsperre (kurzes Rauschen + Klick)
n = rng.standard_normal(int(SR * 0.28))
sq = lowpass(n, 0.55) - lowpass(n, 0.08)
sq *= env(len(sq), 0.002, 0.08) * 0.28
click = tone(1800, 0.018, 0.25, 0.001, 0.01)
save("radio", np.concatenate([click, sq, silence(0.02), tone(1200, 0.05, 0.12)]))

# Sprechwunsch: zwei kurze Töne
save("talk", np.concatenate([tone(988, 0.11, 0.3), silence(0.06), tone(988, 0.11, 0.3), silence(0.06), tone(1319, 0.18, 0.3)]))

# Systemsignal
save("system", np.concatenate([tone(880, 0.08, 0.25), silence(0.03), tone(1175, 0.14, 0.25)]))
# Fehler-/Hinweiston
save("error", np.concatenate([tone(330, 0.12, 0.3), silence(0.04), tone(262, 0.2, 0.3)]))

# Tastatur: drei Varianten
for i in range(3):
    n = rng.standard_normal(int(SR * 0.045))
    k = (lowpass(n, 0.6) - lowpass(n, 0.15)) * np.exp(-np.arange(len(n)) / (SR * 0.008)) * 0.5
    k[: int(SR * 0.002)] += 0.25
    save("key%d" % (i + 1), np.concatenate([k, silence(0.02)]))

# Anruferstimme (abstraktes, gedämpftes Sprachsignal über Telefon – kein Text)
tt = t(0.5)
f0 = 150 + 30 * np.sin(2 * np.pi * 3.1 * tt) + 20 * np.sin(2 * np.pi * 7.3 * tt)
ph = 2 * np.pi * np.cumsum(f0) / SR
v = np.sign(np.sin(ph)) * 0.5 + np.sin(ph * 2) * 0.3
v = lowpass(v, 0.25) - lowpass(v, 0.03)
sy = (np.sin(2 * np.pi * 4.5 * tt) > -0.2) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * tt))
save("voice", v * sy * env(len(v), 0.02, 0.08) * 0.35)

# Hintergrund Leitstelle: leises Raumrauschen, Lüftung, vereinzelte entfernte Tastenanschläge (Schleife 12 s)
L = 12.0
n = rng.standard_normal(int(SR * L))
room = lowpass(n, 0.02) * 0.9 + (lowpass(n, 0.2) - lowpass(n, 0.1)) * 0.08
tt = t(L)
hum = 0.012 * np.sin(2 * np.pi * 100 * tt) + 0.006 * np.sin(2 * np.pi * 200 * tt)
amb = room * 0.22 + hum
for _ in range(26):
    p = int(rng.uniform(0.3, L - 0.3) * SR)
    k = rng.standard_normal(int(SR * 0.03)); k = (lowpass(k, 0.5) - lowpass(k, 0.2)) * np.exp(-np.arange(len(k)) / (SR * 0.006))
    amb[p:p + len(k)] += k * rng.uniform(0.02, 0.05)
fade = int(SR * 0.5)
amb[:fade] = amb[:fade] * np.linspace(0, 1, fade) + amb[-fade:] * np.linspace(1, 0, fade)
save("ambient", amb[:-fade])
