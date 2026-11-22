"""Contrast of text on the variant B (Flutter glass) popups, worst case.

Run: python3 -I tool/contrast_glass.py <repo>

The glass is the tint (BlizzardPopupGlass) over a blurred scene. Blur never exceeds the
brightest pixel, so the brightest scene pixel (per channel and by luminance) of
assets/images/luma_aurora_glow.png over #07121F, with no dimming at all, is an upper bound of
what can sit behind the glass. Also reported: inside a dialog, whose route dims the scene by
the 54% black barrier. Pillow is not needed: macOS sips converts the PNG to a 24-bit BMP.
"""

import os
import re
import struct
import subprocess
import sys
import tempfile

repo = sys.argv[1]
tokens = open(os.path.join(repo, "lib/core/theme/blizzard_tokens.dart")).read()


def color(name):
    m = re.search(r"static const %s = Color\(0x([0-9A-Fa-f]{8})\)" % name, tokens)
    v = int(m.group(1), 16)
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255), (v >> 24) / 255


lin = [(c / 255 / 12.92) if c / 255 <= 0.04045 else ((c / 255 + 0.055) / 1.055) ** 2.4 for c in range(256)]
lum = lambda c: 0.2126 * lin[round(c[0])] + 0.7152 * lin[round(c[1])] + 0.0722 * lin[round(c[2])]


def ratio(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


mix = lambda top, a, below: tuple(t * a + b * (1 - a) for t, b in zip(top, below))

bmp = os.path.join(tempfile.mkdtemp(), "glow.bmp")
subprocess.run(["sips", "-s", "format", "bmp", os.path.join(repo, "assets/images/luma_aurora_glow.png"), "--out", bmp],
               check=True, stdout=subprocess.DEVNULL)
raw = open(bmp, "rb").read()
off = struct.unpack("<I", raw[10:14])[0]
w, h = struct.unpack("<ii", raw[18:26])
h = abs(h)
stride = (w * 3 + 3) // 4 * 4
bg = color("background")[0]
best_lum, best_px, chan = -1, None, [0, 0, 0]
for y in range(h):
    row = raw[off + y * stride: off + y * stride + w * 3]
    for x in range(0, w, 2):
        b_, g_, r_ = row[x * 3], row[x * 3 + 1], row[x * 3 + 2]
        px = (r_, g_, b_)
        # the png may carry alpha; sips flattens it to black, so treat it as the scene colour
        scene = tuple(max(p, q) for p, q in zip(px, bg))
        chan = [max(c, s) for c, s in zip(chan, scene)]
        if lum(scene) > best_lum:
            best_lum, best_px = lum(scene), scene
primary, secondary = color("primary")[0], color("secondary")[0]
rows = []
for role in ("sheetTint", "menuTint", "dialogTint"):
    t, a = color(role)
    for label, scene in (("brightest pixel", best_px), ("per-channel max", tuple(chan))):
        for scrim in ((0, "no scrim"), (0.54, "under 54% barrier")) if role == "dialogTint" else ((0, "no scrim"),):
            under = mix((0, 0, 0), scrim[0], scene)
            glass = mix(t, a, under)
            rows.append((role, label, scrim[1], round(a, 2), ratio(primary, glass), ratio(secondary, glass)))
plate, pa = color("plateTint")
worst_glass = mix(color("sheetTint")[0], color("sheetTint")[1], best_px)
rows.append(("plate on sheet", "brightest pixel", "no scrim", round(pa, 2),
             ratio(primary, mix(plate, pa, worst_glass)), ratio(secondary, mix(plate, pa, worst_glass))))
ok = True
for r in rows:
    flag = "ok" if r[4] >= 4.5 and r[5] >= 3 else "FAIL"
    ok &= flag == "ok"
    print("%-15s %-16s %-18s alpha %.2f  primary %5.2f  secondary %5.2f  %s" % (r[0], r[1], r[2], r[3], r[4], r[5], flag))
print("brightest scene pixel", best_px, "per-channel max", tuple(chan))
sys.exit(0 if ok else 1)
