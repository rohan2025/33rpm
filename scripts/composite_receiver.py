#!/usr/bin/env python3
"""Places the vintage receiver (Assets/receiver_patch.png, generated with FLUX.1 Kontext for this room)
into the open cubby of each scene's original room photo, graded to that room's light.

    python3 scripts/composite_receiver.py

Reads Scenes/<Scene>/_sources/background_source.png, writes Scenes/<Scene>/background.png.
The receiver's display window and knobs line up with the `receiver` block in each scene.json.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
PATCH = Image.open(ROOT / "Assets/receiver_patch.png").convert("RGB")
# x, bottom y, width in the 1536x1024 room photos (cubby floor, right of the records).
X, BOTTOM, WIDTH = 743, 711, 190
GRADES = {  # brightness, (r, g, b) multipliers
    "Evening": (0.72, (1.0, 1.0, 1.0)),
    "RainyWindow": (0.58, (0.92, 0.97, 1.08)),
    "Minimal": (0.80, (1.0, 0.98, 0.95)),
}

for scene, (bright, tint) in GRADES.items():
    src = ROOT / f"Scenes/{scene}/_sources/background_source.png"
    bg = Image.open(src).convert("RGB")
    h = round(PATCH.height * WIDTH / PATCH.width)
    rx = PATCH.resize((WIDTH, h), Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
    rx = ImageEnhance.Brightness(rx).enhance(bright)
    r, g, b = rx.split()
    rx = Image.merge("RGB", [ch.point(lambda v, m=m: min(255, int(v * m))) for ch, m in zip((r, g, b), tint)])
    # The console top shades the receiver's upper part.
    shade = Image.new("L", (WIDTH, h), 0)
    sd = ImageDraw.Draw(shade)
    for yy in range(h):
        sd.line([(0, yy), (WIDTH, yy)], fill=max(0, int(110 * (1 - yy / (h * 0.45)))))
    rx = Image.composite(Image.new("RGB", (WIDTH, h), (0, 0, 0)), rx, shade)
    oy = BOTTOM - h
    out = bg.copy()
    out.paste(rx, (X, oy), Image.new("L", (WIDTH, h), 255).filter(ImageFilter.GaussianBlur(0.8)))
    contact = Image.new("RGBA", out.size, (0, 0, 0, 0))
    ImageDraw.Draw(contact).ellipse([X + 4, oy + h - 4, X + WIDTH - 4, oy + h + 8], fill=(0, 0, 0, 120))
    out = Image.alpha_composite(out.convert("RGBA"), contact.filter(ImageFilter.GaussianBlur(4))).convert("RGB")
    out.save(ROOT / f"Scenes/{scene}/background.png")
    print(f"{scene}: receiver at x={X} y={oy} {WIDTH}x{h}")
