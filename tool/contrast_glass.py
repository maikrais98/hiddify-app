"""Contrast of text on the variant B (Flutter glass) popups, worst case.

Run: python3 -I tool/contrast_glass.py <repo>

Measure the baked popup artwork with the glass tint and the brightest inner
highlight. The route barrier sits under the opaque material and has no effect
on the result. macOS sips converts the texture to a 24-bit BMP.
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

with tempfile.TemporaryDirectory() as directory:
    bmp = os.path.join(directory, "glow.bmp")
    subprocess.run(["sips", "-s", "format", "bmp", os.path.join(repo, "assets/images/luma_aurora_popup.png"), "--out", bmp],
                   check=True, stdout=subprocess.DEVNULL)
    with open(bmp, "rb") as image:
        raw = image.read()
off = struct.unpack("<I", raw[10:14])[0]
w, h = struct.unpack("<ii", raw[18:26])
h = abs(h)
stride = (w * 3 + 3) // 4 * 4
bg = color("background")[0]
best_lum, best_px, chan = -1, None, [0, 0, 0]
for y in range(h):
    row = raw[off + y * stride: off + y * stride + w * 3]
    for x in range(w):
        b_, g_, r_ = row[x * 3], row[x * 3 + 1], row[x * 3 + 2]
        px = (r_, g_, b_)
        scene = tuple(max(p, q) for p, q in zip(px, bg))
        chan = [max(c, s) for c, s in zip(chan, scene)]
        if lum(scene) > best_lum:
            best_lum, best_px = lum(scene), scene
primary, secondary = color("primary")[0], color("secondary")[0]
highlight, ha = color("highlight")
rows = []
for role in ("sheetTint", "menuTint", "dialogTint"):
    t, a = color(role)
    for label, scene in (("brightest pixel", best_px), ("per-channel max", tuple(chan))):
        glass = mix(highlight, ha, mix(t, a, scene))
        rows.append((role, label, round(a, 2), ratio(primary, glass), ratio(secondary, glass)))
plate, pa = color("plateTint")
sheet, sa = color("sheetTint")
worst_glass = mix(highlight, ha, mix(sheet, sa, best_px))
plate_surface = mix(plate, pa, worst_glass)
rows.append(("plate on sheet", "brightest pixel", round(pa, 2), ratio(primary, plate_surface), ratio(secondary, plate_surface)))
ok = True
for r in rows:
    flag = "ok" if r[3] >= 4.5 and r[4] >= 3 else "FAIL"
    ok &= flag == "ok"
    print("%-15s %-16s alpha %.2f  primary %5.2f  secondary %5.2f  %s" % (*r, flag))
print("brightest scene pixel", best_px, "per-channel max", tuple(chan))
sys.exit(0 if ok else 1)
