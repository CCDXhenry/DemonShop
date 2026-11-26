"""Emit a DemonShop Studio Edit command using the checked-in image manifest."""

import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "Assets/UI/evil_shop_assets.json"
HIT_MASKS = ROOT / "Assets/UI/evil_shop_hit_masks.json"
BUILDERS = {
    "coins": ("build-game-assets.luau", "true"),
    "game": ("build-game-assets.luau", "nil"),
    "shop": ("build-personal-shop-assets.luau", "nil"),
    "localization": ("update-processing-localization.luau", ""),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=BUILDERS, help="Use game only for a full asset bootstrap")
    args = parser.parse_args()
    filename, extra_args = BUILDERS[args.target]
    source = (ROOT / "Tools/Gameplay" / filename).read_text(encoding="utf-8")
    command = (
        'assert(game.PlaceId == 110812537538556 and not game:GetService("RunService"):IsRunning(), '
        '"DemonShop Edit required")\n'
        "local function build(...)\n"
        f"{source.rstrip()}\nend\n"
    )
    if args.target == "localization":
        localization = (ROOT / "Tools/Gameplay/sync-localization-table.luau").read_text(encoding="utf-8")
        static_sources = {"SHOP", "ABILITY UPGRADES", "TOOL EVOLUTION", "MOVE SPEED",
                          "RUNE BATCH", "SALE BONUS", "RUSTY PAN", "EQUIPPED", "MAX"}
        entries = re.findall(r'\t\{\n\t\tKey = "([^"]*)",\n\t\tSource = "([^"]*)",\n([^\n]+\n[^\n]+\n[^\n]+\n\t\},)', localization)
        shop_rows = [
            f'\t{{\n\t\tKey = "{key}",\n\t\tSource = "{text}",\n{fields}'
            for key, text, fields in entries
            if key == "Processing.Coins" or key.startswith("Processing.Shop") or (not key and text in static_sources)
        ]
        command += "return build({\n" + "\n".join(shop_rows) + "\n})\n"
    else:
        assets = json.loads(MANIFEST.read_text(encoding="utf-8"))
        if len(assets) != 36 or any(
            not re.fullmatch(r"rbxassetid://[1-9][0-9]*", uri) for uri in assets.values()
        ):
            parser.error("The manifest must contain 36 uploaded image URIs")
        manifest = json.dumps(assets, separators=(",", ":"))
        mask_json = HIT_MASKS.read_text(encoding="utf-8").strip()
        command += f"return build([=[{manifest}]=], {extra_args}, [=[{mask_json}]=])\n"
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stdout.write(command)


if __name__ == "__main__":
    main()
