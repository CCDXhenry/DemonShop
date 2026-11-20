"""从 AI 生成的符文原图提取抗锯齿透明 PNG 并生成 64×64 透明度 Luau 模块与辨识度预览图。"""
from __future__ import annotations

import argparse
import base64
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT_DIR = ROOT / "Assets" / "UI" / "Runes"
DEFAULT_LUAU_OUT = ROOT / "Scripts" / "ReplicatedStorage" / "Scripts" / "Shared" / "RuneGlyphData.luau"
DEFAULT_PREVIEW_OUT = ROOT / ".cache" / "runes" / "preview.png"

EXPORT_SIZE = 256
GLYPH_SIZE = 64
CONTENT_FRACTION = 0.78  # 居中视觉尺寸占比，四周保留约 11% 透明边距
INK_RGB = (106, 27, 154)  # 导出透明 PNG 统一暗紫主色（运行时按 GameConfig.RuneBaseColor 着色）
RUNTIME_RGB = (176, 63, 255)


def extract_alpha(img: Image.Image) -> Image.Image:
    """将白底或已有 Alpha 的符文原图转为抗锯齿单通道 L 遮罩。"""
    rgba = img.convert("RGBA")
    width, height = rgba.size
    pixels = rgba.load()
    # 检查是否存在真实透明背景
    alpha_band = rgba.getchannel("A")
    a_min, _ = alpha_band.getextrema()
    if a_min < 250:
        # 已有透明通道，直接保留抗锯齿 Alpha
        return alpha_band

    # 纯白底原图：根据像素到纯白 (255, 255, 255) 的亮度/色差连续提取抗锯齿覆盖度
    mask = Image.new("L", (width, height), 0)
    mask_px = mask.load()
    # 统计最深墨水像素的亮度作为 100% 不透明基准
    darkest = 255.0
    for y in range(height):
        for x in range(width):
            r, g, b, _ = pixels[x, y]
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            if lum < darkest:
                darkest = lum
    white_cut = 246.0  # 过滤 JPEG 压缩产生的极微弱白底噪点
    ink_level = min(darkest + 25.0, 200.0)
    denom = max(white_cut - ink_level, 1.0)
    for y in range(height):
        for x in range(width):
            r, g, b, _ = pixels[x, y]
            lum = 0.299 * r + 0.587 * g + 0.114 * b
            if lum >= white_cut:
                mask_px[x, y] = 0
            elif lum <= ink_level:
                mask_px[x, y] = 255
            else:
                t = (white_cut - lum) / denom
                mask_px[x, y] = int(round(max(0.0, min(1.0, t)) * 255.0))
    return mask


def normalize_glyph(mask: Image.Image, target_size: int) -> Image.Image:
    """按非透明包围盒统一裁切并居中缩放到统一视觉尺寸，四周留透明边距。"""
    bbox = mask.point(lambda v: 255 if v >= 16 else 0).getbbox()
    if not bbox:
        raise ValueError("符文原图未检测到有效前景笔画")
    cropped = mask.crop(bbox)
    cw, ch = cropped.size
    max_dim = int(round(target_size * CONTENT_FRACTION))
    scale = min(max_dim / cw, max_dim / ch)
    nw = max(1, int(round(cw * scale)))
    nh = max(1, int(round(ch * scale)))
    resized = cropped.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("L", (target_size, target_size), 0)
    ox = (target_size - nw) // 2
    oy = (target_size - nh) // 2
    canvas.paste(resized, (ox, oy))
    return canvas


def mask_to_rgba(mask: Image.Image, rgb: tuple[int, int, int]) -> Image.Image:
    rgba = Image.new("RGBA", mask.size, (rgb[0], rgb[1], rgb[2], 0))
    rgba.putalpha(mask)
    return rgba


def build_preview(glyph_masks_64: list[Image.Image], preview_path: Path) -> None:
    """生成白膜底色（纯白）上的多尺度与旋转辨识度自检图。"""
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    sizes = [64, 36, 24, 18, 14]
    width = 640
    height = 360
    sheet = Image.new("RGBA", (width, height), (245, 245, 245, 255))
    draw = ImageDraw.Draw(sheet)
    # 白色白膜背景区
    draw.rectangle([16, 16, width - 16, height - 16], fill=(255, 255, 255, 255), outline=(210, 210, 210, 255))

    y = 32
    for idx, mask64 in enumerate(glyph_masks_64):
        x = 36
        rgba = mask_to_rgba(mask64, RUNTIME_RGB)
        for sz in sizes:
            sample = rgba.resize((sz, sz), Image.Resampling.BILINEAR)
            sheet.alpha_composite(sample, (x, y + (64 - sz) // 2))
            x += sz + 26
        # 额外展示旋转 35° 与边缘 0.5 缩放（18px）
        rotated = rgba.resize((36, 36), Image.Resampling.BILINEAR).rotate(-35, resample=Image.Resampling.BICUBIC, expand=True)
        sheet.alpha_composite(rotated, (x, y + (64 - rotated.height) // 2))
        x += rotated.width + 24
        half_scale = rgba.resize((18, 18), Image.Resampling.BILINEAR)
        sheet.alpha_composite(half_scale, (x, y + (64 - 18) // 2))
        y += 96

    sheet.convert("RGB").save(preview_path)


def emit_luau(glyph_masks_64: list[Image.Image], out_path: Path) -> None:
    encoded_list: list[str] = []
    for mask in glyph_masks_64:
        raw = mask.tobytes()
        assert len(raw) == GLYPH_SIZE * GLYPH_SIZE
        encoded_list.append(base64.b64encode(raw).decode("ascii"))

    lines = [
        "-- 符文字形 64×64 透明度数据：由 AI 生成的透明 PNG 离线导出，供曲面图集与平面 EditableImage 共用",
        "--!strict",
        "local RuneGlyphData = {}",
        f"RuneGlyphData.Size = {GLYPH_SIZE}",
        f"RuneGlyphData.Count = {len(encoded_list)}",
        "",
        "local ENCODED: { string } = {",
    ]
    for b64 in encoded_list:
        lines.append(f'\t"{b64}",')
    lines.extend([
        "}",
        "",
        "local ALPHABET = \"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/\"",
        "local DECODE_MAP: { [number]: number } = {}",
        "for i = 1, #ALPHABET do",
        "\tDECODE_MAP[string.byte(ALPHABET, i)] = i - 1",
        "end",
        "",
        "local function DecodeBase64(text: string, expectedBytes: number): buffer",
        "\tlocal out = buffer.create(expectedBytes)",
        "\tlocal write = 0",
        "\tlocal length = #text",
        "\tlocal i = 1",
        "\twhile i <= length and write < expectedBytes do",
        "\t\tlocal c1 = DECODE_MAP[string.byte(text, i)] or 0",
        "\t\tlocal c2 = DECODE_MAP[string.byte(text, i + 1)] or 0",
        "\t\tlocal b3 = string.byte(text, i + 2)",
        "\t\tlocal b4 = string.byte(text, i + 3)",
        "\t\tlocal c3 = if b3 then DECODE_MAP[b3] else nil",
        "\t\tlocal c4 = if b4 then DECODE_MAP[b4] else nil",
        "\t\tlocal n = bit32.bor(bit32.lshift(c1, 18), bit32.lshift(c2, 12), bit32.lshift(c3 or 0, 6), c4 or 0)",
        "\t\tbuffer.writeu8(out, write, bit32.band(bit32.rshift(n, 16), 255))",
        "\t\twrite += 1",
        "\t\tif c3 ~= nil and write < expectedBytes then",
        "\t\t\tbuffer.writeu8(out, write, bit32.band(bit32.rshift(n, 8), 255))",
        "\t\t\twrite += 1",
        "\t\tend",
        "\t\tif c4 ~= nil and write < expectedBytes then",
        "\t\t\tbuffer.writeu8(out, write, bit32.band(n, 255))",
        "\t\t\twrite += 1",
        "\t\tend",
        "\t\ti += 4",
        "\tend",
        "\treturn out",
        "end",
        "",
        "local GLYPHS: { buffer } = {}",
        "local PIXEL_COUNT = RuneGlyphData.Size * RuneGlyphData.Size",
        "for index, text in ipairs(ENCODED) do",
        "\tGLYPHS[index] = DecodeBase64(text, PIXEL_COUNT)",
        "end",
        "",
        "function RuneGlyphData.Alpha(glyph: number): buffer",
        "\treturn GLYPHS[glyph] or GLYPHS[1]",
        "end",
        "",
        "function RuneGlyphData.Sample(glyph: number, u: number, v: number): number",
        "\tif u <= 0 or u >= 1 or v <= 0 or v >= 1 then",
        "\t\treturn 0",
        "\tend",
        "\tlocal alpha = GLYPHS[glyph] or GLYPHS[1]",
        "\tlocal size = RuneGlyphData.Size",
        "\tlocal fx = u * size - 0.5",
        "\tlocal fy = v * size - 0.5",
        "\tlocal x0 = math.floor(fx)",
        "\tlocal y0 = math.floor(fy)",
        "\tlocal tx = fx - x0",
        "\tlocal ty = fy - y0",
        "\tlocal x1 = x0 + 1",
        "\tlocal y1 = y0 + 1",
        "\tlocal a00 = if x0 >= 0 and x0 < size and y0 >= 0 and y0 < size then buffer.readu8(alpha, y0 * size + x0) else 0",
        "\tlocal a10 = if x1 >= 0 and x1 < size and y0 >= 0 and y0 < size then buffer.readu8(alpha, y0 * size + x1) else 0",
        "\tlocal a01 = if x0 >= 0 and x0 < size and y1 >= 0 and y1 < size then buffer.readu8(alpha, y1 * size + x0) else 0",
        "\tlocal a11 = if x1 >= 0 and x1 < size and y1 >= 0 and y1 < size then buffer.readu8(alpha, y1 * size + x1) else 0",
        "\tlocal top = a00 + (a10 - a00) * tx",
        "\tlocal bottom = a01 + (a11 - a01) * tx",
        "\treturn top + (bottom - top) * ty",
        "end",
        "",
        "function RuneGlyphData.CreateRgbaBuffer(glyph: number): buffer",
        "\tlocal alpha = GLYPHS[glyph] or GLYPHS[1]",
        "\tlocal pixels = buffer.create(PIXEL_COUNT * 4)",
        "\tbuffer.fill(pixels, 0, 255)",
        "\tfor index = 0, PIXEL_COUNT - 1 do",
        "\t\tbuffer.writeu8(pixels, index * 4 + 3, buffer.readu8(alpha, index))",
        "\tend",
        "\treturn pixels",
        "end",
        "",
        "return RuneGlyphData",
        "",
    ])
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("inputs", nargs=3, help="三张 AI 符文原图路径（Rune1, Rune2, Rune3）")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--luau-out", type=Path, default=DEFAULT_LUAU_OUT)
    parser.add_argument("--preview-out", type=Path, default=DEFAULT_PREVIEW_OUT)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    masks_64: list[Image.Image] = []
    for index, raw_path in enumerate(args.inputs, start=1):
        img = Image.open(raw_path)
        raw_mask = extract_alpha(img)
        norm_256 = normalize_glyph(raw_mask, EXPORT_SIZE)
        rgba_256 = mask_to_rgba(norm_256, INK_RGB)
        png_path = args.out_dir / f"Rune{index}.png"
        rgba_256.save(png_path, format="PNG")
        mask_64 = normalize_glyph(raw_mask, GLYPH_SIZE)
        masks_64.append(mask_64)
        print(f"Exported {png_path} ({EXPORT_SIZE}x{EXPORT_SIZE}) + 64x64 alpha")

    emit_luau(masks_64, args.luau_out)
    print(f"Generated {args.luau_out}")
    build_preview(masks_64, args.preview_out)
    print(f"Generated preview {args.preview_out}")


if __name__ == "__main__":
    main()
