"""
Refine generated demon attack button icon:
- Clean background to true 32-bit alpha transparency
- Smooth anti-aliased circular mask with outer glow preservation
- Re-center exactly
- Scale to standard 512x512
- Output to Assets/UI/AttackButton.png
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from pathlib import Path

def process_icon():
    src_path = Path(r"C:\Users\herong\.gemini\antigravity\brain\076621a3-8734-407b-bbfb-6e284fc2586c\demon_attack_button_icon_1795054036070.jpg")
    dest_path = Path(r"c:\Users\herong\Desktop\work\DemonShop\Assets\UI\AttackButton.png")
    dest_path.parent.mkdir(parents=True, exist_ok=True)

    img = Image.open(src_path).convert("RGBA")
    w, h = img.size

    # Icon circle center and radius
    cx, cy = 511.5, 508.0
    radius = 398.0  # Outer boundary of the circular frame

    # Crop tightly around the circle with a tiny margin
    pad = 20
    box = (int(cx - radius - pad), int(cy - radius - pad), int(cx + radius + pad), int(cy + radius + pad))
    cropped = img.crop(box)
    cw, ch = cropped.size

    # New center inside cropped
    ncx = cw / 2.0
    ncy = ch / 2.0

    # Create high-res anti-aliased mask
    scale_factor = 4
    mask_w, mask_h = cw * scale_factor, ch * scale_factor
    mask = Image.new("L", (mask_w, mask_h), 0)
    draw = ImageDraw.Draw(mask)

    mcx = ncx * scale_factor
    mcy = ncy * scale_factor
    mradius = radius * scale_factor

    # Draw smooth circular gradient mask for border edge
    draw.ellipse((mcx - mradius, mcy - mradius, mcx + mradius, mcy + mradius), fill=255)

    # Slight blur for smooth sub-pixel anti-aliasing
    mask = mask.filter(ImageFilter.GaussianBlur(radius=scale_factor * 1.2))
    mask = mask.resize((cw, ch), Image.Resampling.LANCZOS)

    # Apply alpha mask
    cropped.putalpha(mask)

    # Now create target 512x512 image with 24px safe margin
    # Target icon diameter ~464px inside 512x512
    target_canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    target_diameter = 464
    resized_icon = cropped.resize((target_diameter, target_diameter), Image.Resampling.LANCZOS)

    # Paste centered
    offset = (512 - target_diameter) // 2
    target_canvas.paste(resized_icon, (offset, offset), resized_icon)

    # Save optimized PNG
    target_canvas.save(dest_path, format="PNG", optimize=True)
    print(f"Successfully processed and saved attack button to {dest_path}")
    print(f"Canvas size: {target_canvas.size}, Mode: {target_canvas.mode}")

if __name__ == "__main__":
    process_icon()
