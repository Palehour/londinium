import numpy as np, subprocess, sys, os
from multiprocessing import Pool
from scipy import ndimage as ndi
from PIL import Image, ImageFont, ImageDraw

W, H = 1920, 1080
FPS = 24
DUR = 10.0
NF = int(DUR * FPS)
OUT = os.path.dirname(os.path.abspath(__file__))

def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)
def ease(a, b, x):  # easeInOutSine
    t = np.clip((x - a) / (b - a), 0, 1)
    return 0.5 - 0.5 * np.cos(np.pi * t)

# ---------------- arc geometry (fit to the jpg, image coords -> frame) ----------------
S, Y0 = 1.2, 420.0
def map_xy(x, y): return 960 + (x - 512) * S, Y0 + (y - 460) * S
CX, CY = map_xy(512, 63.5)
R = 445.5 * S
TH = np.arcsin(280 / 445.5)          # half-angle to tips
WARC = 8.6 * S                        # centre thickness

# ROI for arc + glow
RX0, RX1, RY0, RY1 = 380, 1540, 180, 720
yy, xx = np.mgrid[RY0:RY1, RX0:RX1].astype(np.float32)
dx, dy = xx - CX, yy - CY
rr = np.sqrt(dx * dx + dy * dy)
sd = rr - R                                    # signed dist to centre line (+ = outside/below)
theta = np.arctan2(dx, dy)                     # 0 at bottom
U = np.abs(theta) / TH
wprof = WARC * np.clip(1 - U ** 2, 0, 1) ** 0.8
# crescent: offset the band slightly outward so lower edge is the "full" curve
arc_alpha = np.clip(wprof / 2 - np.abs(sd - 0.15 * wprof) + 0.5, 0, 1)
# subtle inner gradient: lower edge a touch brighter
arc_shade = 0.76 + 0.10 * np.clip((sd + wprof / 2) / (wprof + 1e-3), 0, 1)
d = np.abs(sd)
gtaper = np.clip(1 - U ** 2, 0, 1)
glow_n = np.exp(-(d / 5.0) ** 2)
glow_m = np.exp(-(d / 22.0) ** 2)
glow_w = np.exp(-(d / 80.0) ** 2) * np.exp(-((U - 0) / 1.1) ** 2)

# ---------------- fog noise textures ----------------
rng = np.random.default_rng(7)
TEX = []
for sig in (40, 20, 10, 5):
    n = ndi.gaussian_filter(rng.standard_normal((768, 768)).astype(np.float32), sig, mode='wrap')
    n = (n - n.mean()) / n.std()
    TEX.append(n)
WARP = ndi.gaussian_filter(rng.standard_normal((512, 512)).astype(np.float32), 30, mode='wrap')
WARP /= WARP.std()

FW, FH = 960, 540
fy, fx = np.mgrid[0:FH, 0:FW].astype(np.float32)
FX, FY = fx * 2 + 1, fy * 2 + 1      # in frame px

def fbm(t, stretch, speeds, amps, yoff=0.0):
    wv = ndi.map_coordinates(WARP, [(FY * 0.25 + 3 * t) % 512, (FX * 0.12 + 5 * t) % 512], order=1, mode='wrap')
    acc = np.zeros_like(FX)
    for i, (tex, sp, a) in enumerate(zip(TEX, speeds, amps)):
        sc = 0.5 * (1.0 + 0.6 * i)
        xs = (FX * sc / stretch + sp * t + 25 * wv) % 768
        ys = ((FY + yoff) * sc + 9 * wv + 3 * i * t) % 768
        acc += a * ndi.map_coordinates(tex, [ys, xs], order=1, mode='wrap')
    return acc

# fog band (matches the jpg fog: y~540-630 -> frame ~530-640)
BAND_CY = 548.0
by = np.where(FY < BAND_CY, np.exp(-((FY - BAND_CY) / 22) ** 2), np.exp(-((FY - BAND_CY) / 52) ** 2))
bx = np.exp(-((FX - 960) / 560) ** 4)
BAND = (by * bx).astype(np.float32)
HOT = (np.exp(-((FX - 960) / 260) ** 2) * np.exp(-((FY - (BAND_CY - 4)) / 26) ** 2)).astype(np.float32)
# ambient fog region: broad, heavier toward lower half
AMB = (np.exp(-((FY - 600) / 330) ** 2) * np.exp(-((FX - 960) / 1100) ** 2)).astype(np.float32)
# cold dawn light behind arc
yF, xF = np.mgrid[0:H, 0:W].astype(np.float32)
DAWN = np.exp(-((xF - 960) / 640) ** 2 - ((yF - 520) / 210) ** 2).astype(np.float32)

# ---------------- wordmark ----------------
FONT = '/usr/share/fonts/truetype/sand-box/google/Cormorant Garamond/CormorantGaramond-VariableFont_wght.ttf'
def make_wordmark():
    SS = 4
    size = int(sys.argv[2]) if len(sys.argv) > 2 else 58
    f = ImageFont.truetype(FONT, size * SS)
    f.set_variation_by_name(os.environ.get('WGHT', 'Light'))
    text = 'PALEHOUR'
    track = 0.62 * size * SS
    widths = [f.getbbox(c)[2] - f.getbbox(c)[0] for c in text]
    adv = [f.getlength(c) for c in text]
    total = sum(adv) + track * (len(text) - 1)
    pad = 40 * SS
    img = Image.new('L', (int(total + 2 * pad), int(size * SS * 2)), 0)
    dr = ImageDraw.Draw(img)
    x = pad
    for c, a in zip(text, adv):
        dr.text((x, size * SS * 0.3), c, font=f, fill=255)
        x += a + track
    img = img.resize((img.width // SS, img.height // SS), Image.LANCZOS)
    a = np.asarray(img).astype(np.float32) / 255
    ys, xs = np.nonzero(a > 0.02)
    # trim to ink bbox + margin
    m = 24
    a = a[max(ys.min() - m, 0):ys.max() + m, max(xs.min() - m, 0):xs.max() + m]
    return a
TEXT = make_wordmark()
TH_, TW_ = TEXT.shape
TEXT_CY = 742

def frame(i):
    t = i / FPS
    img = np.zeros((H, W), np.float32)
    # --- fog ---
    amb_k = 0.11 * ease(0.2, 1.8, t) * (1 - 0.45 * ease(4.0, 5.6, t))
    band_k = 0.36 * ease(1.2, 4.2, t) + 0.16 * ease(4.0, 5.6, t)
    hot_k = 0.14 * ease(3.0, 5.6, t)
    if amb_k > 0 or band_k > 0:
        n_amb = fbm(t, 2.2, (6.0, 9.0, 13.0, 18.0), (0.55, 0.3, 0.15, 0.08))
        fog_amb = AMB * np.clip(0.5 + 0.45 * n_amb, 0, None) ** 1.5
        n_band = fbm(t + 37.0, 4.5, (7.0, 11.0, 16.0, 22.0), (0.5, 0.35, 0.22, 0.12), yoff=200)
        dens = np.clip(0.50 + 0.50 * n_band, 0, None)
        dens = dens ** 1.6
        fog_band = BAND * dens
        fog = amb_k * fog_amb + band_k * fog_band + hot_k * HOT * (0.6 + 0.4 * dens)
        fog = ndi.zoom(fog, 2, order=3)[:H, :W]
        img += np.clip(fog, 0, None)
    # --- dawn ---
    img += 0.045 * ease(2.4, 5.2, t) * DAWN
    # --- arc ---
    p = ease(1.5, 3.7, t)
    if p > 0:
        ur = p * 1.04
        front = np.clip((ur - U) / 0.10, 0, 1)
        rev = np.clip((ur - U) / 0.03 + 0.5, 0, 1)
        wf = wprof * np.where(p < 1, front ** 0.6, 1.0)
        a_f = np.clip(wf / 2 - np.abs(sd - 0.15 * wf) + 0.5, 0, 1)
        sweep = np.exp(-((U - ur) / 0.07) ** 2) * (1 - sstep(3.5, 4.3, t))
        bloom = 0.9 + 0.5 * np.exp(-((t - 3.8) / 0.8) ** 2) + 0.15 * ease(4.0, 5.5, t)
        core = a_f * arc_shade * rev * (1 + 0.15 * sweep)
        cs = a_f * rev
        small = cs.reshape(cs.shape[0] // 2, 2, cs.shape[1] // 2, 2).mean(axis=(1, 3))
        g = (0.9 * ndi.gaussian_filter(small, 2.0) * 1.0 + 1.6 * ndi.gaussian_filter(small, 9.0) + 2.4 * ndi.gaussian_filter(small, 34.0))
        glow = ndi.zoom(g, 2, order=1) * 0.42 * bloom
        thf = min(ur, 1.0) * TH
        pts = 0
        for sgn in (-1, 1):
            px, py = CX + sgn * R * np.sin(thf), CY + R * np.cos(thf)
            pts = pts + np.exp(-((xx - px) ** 2 + (yy - py) ** 2) / (2 * 12.0 ** 2))
        pts = pts * (1 - sstep(3.4, 4.2, t))
        glow = glow + 0.20 * pts
        roi = img[RY0:RY1, RX0:RX1]
        lay = glow + core
        img[RY0:RY1, RX0:RX1] = 1 - (1 - roi) * (1 - np.clip(lay, 0, 1))   # screen
    # --- wordmark ---
    ta = ease(5.0, 6.9, t)
    if ta > 0:
        e = ease(5.0, 7.1, t)
        blur = 4.5 * (1 - e)
        off = 18 * (1 - e)
        tl = ndi.shift(TEXT, (off, 0), order=3, mode='constant')
        if blur > 0.05:
            tl = ndi.gaussian_filter(tl, blur)
        tl = np.clip(tl, 0, 1) * 0.80 * ta
        y0 = int(TEXT_CY - TH_ // 2); x0 = int(960 - TW_ // 2)
        reg = img[y0:y0 + TH_, x0:x0 + TW_]
        img[y0:y0 + TH_, x0:x0 + TW_] = 1 - (1 - reg) * (1 - tl)
    # --- global fade out ---
    img *= 1 - ease(8.2, 9.7, t)
    img = np.clip(img, 0, 1)
    # gamma-ish lift is already baked; add fine grain + TPDF dither at Y quantisation
    r = np.random.default_rng(1000 + i)
    grain = r.standard_normal((H, W)).astype(np.float32) * 0.0035 * (img > 0.003)
    v = np.clip(img + grain, 0, 1)
    tpdf = r.random((H, W), dtype=np.float32) - r.random((H, W), dtype=np.float32)
    Y = np.clip(np.round(16 + 219 * v + tpdf), 16, 235).astype(np.uint8)
    full = np.clip(np.round(255 * v + tpdf), 0, 255).astype(np.uint8)
    return i, Y, full

if __name__ == '__main__':
    mode = sys.argv[1] if len(sys.argv) > 1 else 'video'
    if mode == 'still':
        for tt in (1, 3, 5, 7, 8.2, 9):
            _, _, f = frame(int(tt * FPS))
            Image.fromarray(f).save(f'{OUT}/test_{tt}.png')
        sys.exit()
    ff = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'yuv420p', '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-',
                           '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-tune', 'grain', '-pix_fmt', 'yuv420p',
                           '-color_range', 'tv', '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709',
                           f'{OUT}/video_only.mp4'], stdin=subprocess.PIPE)
    uv = np.full((H // 2) * (W // 2) * 2, 128, np.uint8).tobytes()
    with Pool(8) as pool:
        for i, Y, full in pool.imap(frame, range(NF), chunksize=2):
            ff.stdin.write(Y.tobytes()); ff.stdin.write(uv)
            if i == int(8.0 * FPS):
                Image.fromarray(full).save(f'{OUT}/palehour-intro-final.png')
    ff.stdin.close(); ff.wait()
    print('done', ff.returncode)
