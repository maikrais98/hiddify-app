"""Bake the popup artwork from Aurora's glow and stars (requires Pillow)."""

import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

assets = Path(__file__).resolve().parents[1] / "assets" / "images"
glow = Image.open(assets / "luma_aurora_glow.png").convert("RGBA")
stars = ET.parse(assets / "luma_aurora_stars.svg").getroot()
_, _, width, height = map(int, stars.attrib["viewBox"].split())
scale_x = glow.width / width
scale_y = glow.height / height

group = stars[0]
star_layer = Image.new("RGBA", glow.size)
draw = ImageDraw.Draw(star_layer)
rgb = bytes.fromhex(group.attrib["fill"].removeprefix("#"))
fill = (*rgb, round(float(group.attrib["opacity"]) * 255))
for circle in group:
    x, y, radius = (float(circle.attrib[key]) for key in ("cx", "cy", "r"))
    draw.ellipse(
        ((x - radius) * scale_x, (y - radius) * scale_y, (x + radius) * scale_x, (y + radius) * scale_y),
        fill=fill,
    )

artwork = Image.alpha_composite(glow, star_layer).convert("RGB")
artwork = artwork.resize((width, height), Image.Resampling.LANCZOS)
# TonniTools' 14px strength plus 2px extra blur and 120% reflection saturation.
blurred = artwork.filter(ImageFilter.GaussianBlur(16))
ImageEnhance.Color(blurred).enhance(1.2).save(assets / "luma_aurora_popup.png", optimize=True)
