#!/usr/bin/env python3
"""Generate DMG background image for Tokei installer."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math, os

W, H = 660, 400
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Elegant dark gradient background
for y in range(H):
    t = y / H
    r = int(28 + t * 6)
    g = int(28 + t * 5)
    b = int(35 + t * 8)
    draw.line([(0, y), (W, y)], fill=(r, g, b, 255))

# Subtle radial vignette (darker edges, lighter center)
vignette = Image.new("RGBA", (W, H), (0, 0, 0, 0))
vd = ImageDraw.Draw(vignette)
cx, cy = W // 2, H // 2 - 20
for r in range(max(W, H), 0, -1):
    t = r / max(W, H)
    alpha = int(t * t * 40)
    vd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(0, 0, 0, alpha))
img = Image.alpha_composite(img, vignette)

# ── Fonts ──
def get_font(size):
    for path in [
        "/System/Library/Fonts/STHeiti Medium.ttc",
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
        "/System/Library/Fonts/Supplemental/Songti.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
    ]:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                pass
    return ImageFont.load_default()

def get_mono(size):
    for path in [
        "/System/Library/Fonts/Menlo.ttc",
        "/System/Library/Fonts/Monaco.dfont",
        "/System/Library/Fonts/Supplemental/Courier New.ttf",
    ]:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                pass
    return ImageFont.load_default()

# ── Smooth curved arrow ──
arrow_y = 195
arrow_x1, arrow_x2 = 235, 425

# Soft glow under arrow
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
for offset in range(3):
    r = 20 - offset * 5
    a = 10 + offset * 8
    gd.line([(arrow_x1, arrow_y), (arrow_x2, arrow_y)],
            fill=(255, 160, 90, a), width=r)
glow = glow.filter(ImageFilter.GaussianBlur(15))
img = Image.alpha_composite(img, glow)

# Clean arrow shaft — solid gradient line
arrow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ad = ImageDraw.Draw(arrow)

# Draw smooth gradient arrow shaft
steps = 60
for i in range(steps):
    t = i / steps
    x = int(arrow_x1 + t * (arrow_x2 - arrow_x1 - 15))
    x_end = int(arrow_x1 + (i + 1) / steps * (arrow_x2 - arrow_x1 - 15))
    alpha = int(100 + t * 140)
    r = int(255 - t * 30)
    g = int(160 + t * 40)
    b = int(90 + t * 30)
    ad.line([(x, arrow_y), (x_end, arrow_y)], fill=(r, g, b, alpha), width=3)

# Arrow head — clean triangle
head_x = arrow_x2 - 5
ad.polygon([
    (head_x + 16, arrow_y),
    (head_x - 4, arrow_y - 12),
    (head_x - 4, arrow_y + 12),
], fill=(255, 180, 110, 230))

# Small highlight on arrowhead
ad.polygon([
    (head_x + 12, arrow_y - 1),
    (head_x, arrow_y - 7),
    (head_x, arrow_y - 1),
], fill=(255, 220, 180, 80))

img = Image.alpha_composite(img, arrow)
draw = ImageDraw.Draw(img)

# ── Text labels ──
title_font = get_font(13)
hint_font = get_font(11)
mono_font = get_mono(9)
small_font = get_font(10)

# "Drag to Applications" hint above arrow
txt = "拖入 Applications 安装"
bbox = draw.textbbox((0, 0), txt, font=title_font)
tw = bbox[2] - bbox[0]
draw.text(((W - tw) // 2, arrow_y - 35), txt,
          fill=(220, 220, 230, 180), font=title_font)

# Bottom xattr hint — two parts: Chinese label + mono command
label = "首次打开被拦截?  "
cmd = "sudo xattr -rd com.apple.quarantine /Applications/Tokei.app"
lbox = draw.textbbox((0, 0), label, font=hint_font)
cbox = draw.textbbox((0, 0), cmd, font=mono_font)
lw = lbox[2] - lbox[0]
cw = cbox[2] - cbox[0]
total_w = lw + cw
start_x = (W - total_w) // 2
draw.text((start_x, H - 35), label,
          fill=(140, 145, 165, 140), font=hint_font)
draw.text((start_x + lw, H - 34), cmd,
          fill=(120, 135, 160, 140), font=mono_font)

# Top brand tag
ver = "Tokei · AI Coding Usage Monitor"
bbox = draw.textbbox((0, 0), ver, font=small_font)
vw = bbox[2] - bbox[0]
draw.text(((W - vw) // 2, 12), ver,
          fill=(130, 130, 150, 100), font=small_font)

# Convert to RGB
out = Image.new("RGB", (W, H), (30, 30, 38))
out.paste(img, mask=img)
out.save(os.path.join(os.path.dirname(__file__), "dmg_background.png"), quality=95)
print("Generated dmg_background.png")
