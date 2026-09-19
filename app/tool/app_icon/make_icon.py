import json, sys
import numpy as np
from PIL import Image, ImageFilter

S = 1024
OUT_DIR = sys.argv[1]
import os
MASK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "walk_mask.png")

rng = np.random.default_rng(7)

def blur(arr, r):
    im = Image.fromarray(np.clip(arr * 255, 0, 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r)), dtype=np.float32) / 255.0

def dilate(arr, r):
    im = Image.fromarray((arr > 0.5).astype(np.uint8) * 255)
    return np.asarray(im.filter(ImageFilter.MaxFilter(2 * r + 1)), dtype=np.float32) / 255.0

def erode(arr, r):
    im = Image.fromarray((arr > 0.5).astype(np.uint8) * 255)
    return np.asarray(im.filter(ImageFilter.MinFilter(2 * r + 1)), dtype=np.float32) / 255.0

# ---------------------------------------------------------------- figure mask
m = Image.open(MASK).split()[3]
bbox = m.getbbox()
m = m.crop(bbox)
target_h = int(S * 0.62)
scale = target_h / m.height
m = m.resize((int(m.width * scale), target_h), Image.LANCZOS)
fig = np.zeros((S, S), np.float32)
ox = (S - m.width) // 2 + 6
oy = (S - m.height) // 2 - 4
fig[oy:oy + m.height, ox:ox + m.width] = np.asarray(m, np.float32) / 255.0
fig_bin = (fig > 0.5).astype(np.float32)

STROKE = 11                # half-width of the raised bead
outer = dilate(fig_bin, STROKE)
inner = erode(fig_bin, STROKE)
bead = np.clip(outer - inner, 0, 1)
bead_soft = blur(bead, 1.2)
inner_soft = blur(inner, 1.0)

# ---------------------------------------------------------------- metal plate
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
cx, cy = S / 2, S / 2
dx, dy = xx - cx, yy - cy
r = np.sqrt(dx * dx + dy * dy)
theta = np.arctan2(dy, dx)

# spun (circular) brushing: noise as a function of radius, several frequencies
def ring_noise(n, smooth):
    v = rng.standard_normal(n).astype(np.float32)
    if smooth > 0:
        k = np.ones(smooth) / smooth
        v = np.convolve(v, k, mode="same")
    return v / (np.abs(v).max() + 1e-6)

maxr = int(np.ceil(r.max())) + 2
ri = np.clip(r, 0, maxr - 1)
i0 = ri.astype(int)
frac = ri - i0
n_fine = ring_noise(maxr, 0)
n_mid = ring_noise(maxr, 4)
n_coarse = ring_noise(maxr, 18)
def sample(n):
    return n[i0] * (1 - frac) + n[np.minimum(i0 + 1, maxr - 1)] * frac
brush = 0.028 * sample(n_fine) + 0.022 * sample(n_mid) + 0.02 * sample(n_coarse)
brush *= np.clip(r / 40.0, 0, 1)        # fade the pole artefact at the centre
# break perfect rings slightly with angular grain
brush *= 0.75 + 0.25 * np.cos(theta * 3 + sample(n_coarse) * 4)

# anisotropic sheen typical of spun metal (light from top-left)
sheen = 0.10 * np.cos(2 * (theta + 0.9)) + 0.06 * np.cos(theta + 0.8)
# radial falloff + diagonal lighting
radial = -0.16 * (r / (S * 0.72)) ** 2
diag = -0.16 * ((dx + dy) / (S * 1.4))
base = 0.71 + brush + sheen + radial + diag

# soft rim / bevel near the plate edges (light top-left, dark bottom-right)
edge = np.minimum(np.minimum(xx, S - 1 - xx), np.minimum(yy, S - 1 - yy))
rim = np.clip(1 - edge / 40.0, 0, 1) ** 2.2
rim_dir = (-(dx + dy) / S) * 2          # +1 top-left, -1 bottom-right
base += rim * (0.04 + 0.12 * rim_dir)
base -= np.clip(1 - edge / 3.0, 0, 1) * 0.06

lum = base.copy()

# ---------------------------------------------------------------- recessed interior
# interior sits a touch lower: slightly darker, with an inner shadow along the top-left
inner_shadow = np.clip(np.roll(np.roll(blur(outer, 6), 7, axis=0), 7, axis=1) - inner, 0, 1) * inner_soft
lum = lum - 0.09 * inner_soft - 0.20 * inner_shadow
# bright counter-edge at bottom-right of the recess
inner_light = np.clip(np.roll(np.roll(blur(outer, 4), -5, axis=0), -5, axis=1) - inner, 0, 1) * inner_soft
lum = lum + 0.05 * inner_light

# ---------------------------------------------------------------- bead shadow on plate
shadow = blur(np.roll(np.roll(bead, 10, axis=0), 8, axis=1), 9)
shadow = np.clip(shadow - bead_soft, 0, 1)
lum = lum - 0.28 * shadow
contact = blur(outer, 3)
lum = lum - 0.10 * np.clip(contact - outer, 0, 1)

rgb = np.stack([lum * 1.0, lum * 1.0, lum * 1.005], axis=-1)   # near-neutral steel

# ---------------------------------------------------------------- raised bead
# rounded cross-section: height field = blurred bead, lit from top-left
height = blur(bead, 3.5) * bead_soft
gy, gx = np.gradient(height)
nx, ny = -gx, -gy
light = np.clip(0.55 + 3.6 * (nx * -0.7 + ny * -0.7), 0.0, 1.35)
spec = np.clip(1.0 - 25 * (gx * gx + gy * gy), 0, 1) * bead      # flat crest = brightest
bead_col = np.array([0.945, 0.935, 0.915], np.float32)          # warm off-white enamel
bead_rgb = bead_col[None, None, :] * (0.74 + 0.26 * light)[..., None] + 0.08 * spec[..., None]
# tiny dark seam where bead meets plate
seam = np.clip(blur(bead, 1.5) - bead_soft, 0, 1)
rgb = rgb - 0.08 * seam[..., None]

a = bead_soft[..., None]
rgb = rgb * (1 - a) + bead_rgb * a

img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB")
img.save(f"{OUT_DIR}/Icon-App-1024x1024@1x.png", optimize=True)

# ---------------------------------------------------------------- all sizes
with open(f"{OUT_DIR}/Contents.json") as f:
    contents = json.load(f)
for entry in contents["images"]:
    pt = float(entry["size"].split("x")[0])
    sc = int(entry["scale"].rstrip("x"))
    px = int(round(pt * sc))
    if px == S:
        continue
    img.resize((px, px), Image.LANCZOS).save(f"{OUT_DIR}/{entry['filename']}", optimize=True)
    print("wrote", entry["filename"], px)
print("done")
