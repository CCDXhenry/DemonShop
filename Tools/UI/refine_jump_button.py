"""
Refine generated demon jump button icon:
- Clean background to true 32-bit alpha transparency
- Smooth anti-aliased circular mask
- Re-center exactly
- Scale to standard 512x512 with 24px safe margin (diameter 464px)
- Output to Assets/UI/JumpButton.png
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter


def process_icon() -> None:
    src_path = Path(r"C:\Users\herong\.gemini\antigravity\brain\7370dd91-e9a8-42e2-9214-44eeaff83c15\jump_button_raw_1795577037753.jpg")
    dest_path = Path(r"c:\Users\herong\Desktop\work\DemonShop\Assets\UI\JumpButton.png")
    dest_path.parent.mkdir(parents=True, exist_ok=True)

    img = Image.open(src_path).convert("RGBA")

    cx, cy = 511.5, 512.5
    radius = 445.0

    pad = 20
    box = (int(cx - radius - pad), int(cy - radius - pad), int(cx + radius + pad), int(cy + radius + pad))
    cropped = img.crop(box)
    cw, ch = cropped.size

    ncx = cw / 2.0
    ncy = ch / 2.0

    scale_factor = 4
    mask_w, mask_h = cw * scale_factor, ch * scale_factor
    mask = Image.new("L", (mask_w, mask_h), 0)
    draw = ImageDraw.Draw(mask)

    mcx = ncx * scale_factor
    mcy = ncy * scale_factor
    mradius = radius * scale_factor

    draw.ellipse((mcx - mradius, mcy - mradius, mcx + mradius, mcy + mradius), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(radius=scale_factor * 1.2))
    mask = mask.resize((cw, ch), Image.Resampling.LANCZOS)

    cropped.putalpha(mask)

    target_canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    target_diameter = 464
    resized_icon = cropped.resize((target_diameter, target_diameter), Image.Resampling.LANCZOS)

    offset = (512 - target_diameter) // 2
    target_canvas.paste(resized_icon, (offset, offset), resized_icon)

    target_canvas.save(dest_path, format="PNG", optimize=True)
    print(f"Successfully processed and saved jump button to {dest_path}")
    print(f"Canvas size: {target_canvas.size}, Mode: {target_canvas.mode}")


if __name__ == "__main__":
    process_icon()
