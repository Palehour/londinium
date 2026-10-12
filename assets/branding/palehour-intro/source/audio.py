import numpy as np, wave
from scipy import signal
SR, DUR = 48000, 10.0
n = int(SR * DUR); t = np.arange(n) / SR
rng = np.random.default_rng(3)
def env(a, b, x):
    u = np.clip((x - a) / (b - a), 0, 1); return 0.5 - 0.5 * np.cos(np.pi * u)
fade = 1 - env(8.0, 9.8, t)
# drone: low A + fifth + octave, slow beating, per channel detune
def drone(det):
    s = np.zeros(n)
    for f, a in ((55.0, 1.0), (82.41, 0.45), (110.0, 0.35), (164.8, 0.12)):
        ff = f * (1 + det) + 0.15 * np.sin(2 * np.pi * 0.07 * t)
        ph = 2 * np.pi * np.cumsum(ff) / SR
        s += a * np.sin(ph)
    return s
swell = env(0.0, 4.5, t) * (0.75 + 0.25 * env(4.5, 6.0, t))
dL, dR = drone(-0.0015), drone(0.0015)
# wind: pink-ish noise through slowly sweeping bandpass
def wind(seed):
    r = np.random.default_rng(seed); w = r.standard_normal(n)
    b, a = signal.butter(2, [250 / (SR / 2), 1400 / (SR / 2)], 'band'); w = signal.lfilter(b, a, w)
    b2, a2 = signal.butter(1, 4000 / (SR / 2)); w = signal.lfilter(b2, a2, w)
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * 0.13 * t + seed) * np.sin(2 * np.pi * 0.051 * t + 1.3 * seed)
    return w / np.std(w) * gust
wL, wR = wind(1), wind(2)
wenv = env(0.0, 2.0, t)
# chime at 5.1 s: low resonant bell, inharmonic partials
t0 = 5.1; tc = np.clip(t - t0, 0, None); on = (t >= t0)
chime = np.zeros(n)
for ratio, a, dec in ((1.0, 1.0, 2.6), (2.0, 0.35, 1.8), (2.76, 0.25, 1.3), (5.40, 0.08, 0.7)):
    chime += a * np.sin(2 * np.pi * 146.83 * ratio * tc) * np.exp(-tc / dec)
chime *= on * (1 - np.exp(-tc / 0.012))
# reverb: exponential noise IR
L = int(SR * 3.0); ti = np.arange(L) / SR
def ir(seed):
    r = np.random.default_rng(seed).standard_normal(L) * np.exp(-ti / 0.9)
    b, a = signal.butter(2, 3000 / (SR / 2)); return signal.lfilter(b, a, r)
cL = chime + 0.5 * signal.fftconvolve(chime, ir(5))[:n] / 30
cR = chime + 0.5 * signal.fftconvolve(chime, ir(6))[:n] / 30
L_ = 0.30 * dL * swell + 0.10 * wL * wenv + 0.32 * cL
R_ = 0.30 * dR * swell + 0.10 * wR * wenv + 0.32 * cR
st = np.stack([L_, R_], 1) * fade[:, None]
st *= env(0, 0.05, t)[:, None]
pk = np.abs(st).max(); st = st / pk * 10 ** (-6 / 20)   # peak -6 dBFS
print('peak dBFS -6, rms dBFS', 20 * np.log10(np.sqrt((st ** 2).mean())))
pcm = (st * 32767).astype('<i2')
with wave.open('audio.wav', 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
