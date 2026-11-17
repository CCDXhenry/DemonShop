"""Exercise production hint rules, translation binding and delayed translator refresh with Lune."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / ".cache" / "processing-texts"
OUT.mkdir(parents=True, exist_ok=True)
SHARED = ROOT / "Scripts/ReplicatedStorage/Scripts/Shared"
CLIENT = ROOT / "Scripts/ReplicatedStorage/Scripts/Client"

for name in ("Hints", "GameTexts"):
    source = (SHARED / f"{name}.luau").read_text(encoding="utf-8")
    source = re.sub(r"require\(script.Parent.(\w+)\)", r"require('./\1')", source)
    (OUT / f"{name}.luau").write_text(source, encoding="utf-8")
(OUT / "GameTypes.luau").write_text("return {}", encoding="utf-8")
(OUT / "GameConfig.luau").write_text(
    "return {PotionReward=237,StunHits=5,PoolCapacity=11,ShelfCapacity=13}", encoding="utf-8"
)
source = (CLIENT / "ProcessingTextTool.luau").read_text(encoding="utf-8")
start, end = source.index("local ReplicatedStorage"), source.index("local Tool =")
source = source[:start] + """local GameTexts = require('./GameTexts')
local TranslationTool = require('./TranslationTool')
local TextFitting = require('./Boundary').TextFitting
""" + source[end:]
(OUT / "ProcessingTextTool.luau").write_text(source, encoding="utf-8")
source = (ROOT / "Scripts/ReplicatedStorage/Core/Scripts/Client/TranslationTool.luau").read_text(encoding="utf-8")
start, end = source.index("local replicatedStorage:"), source.index("local AttemptLimit:")
source = source[:start] + """local B = require('./Boundary')
local players, localizationService = B.players, B.localizationService
local function RetryAsync(callback) return true, callback() end
""" + source[end:]
(OUT / "TranslationTool.luau").write_text(source, encoding="utf-8")
source = (CLIENT / "UIManager/TextFitting.luau").read_text(encoding="utf-8").replace(
    'local TextService = game:GetService("TextService")',
    """local R = require('@lune/roblox')
local Vector2, Enum = R.Vector2, R.Enum
local TextService = {GetTextSize = function(_, text, size) return Vector2.new(#text * size / 2, size) end}
""",
)
(OUT / "TextFitting.luau").write_text(source, encoding="utf-8")
for name in ("ProcessingTextBoundary", "test_processing_texts"):
    destination = "Boundary" if name == "ProcessingTextBoundary" else name
    (OUT / f"{destination}.luau").write_text(
        (ROOT / f"Tools/Gameplay/{name}.luau").read_text(encoding="utf-8"), encoding="utf-8"
    )

# All emitted notification identifiers must exist; recovery commands embed the exact Edit migration.
catalog = (SHARED / "GameTexts.luau").read_text(encoding="utf-8")
manager = (ROOT / "Scripts/ServerStorage/Scripts/ProcessingManager.luau").read_text(encoding="utf-8")
for identifier in re.findall(r'self:Tell\(player, "([^"]+)"', manager):
    assert f"\t{identifier} = {{ source" in catalog, identifier
migration = (ROOT / "Tools/Gameplay/update-processing-localization.luau").read_text(encoding="utf-8").replace(
    'return "Updated processing localization templates"', ""
)
for name in ("build-game-assets.luau", "build-quality-samples.luau"):
    assert migration in (ROOT / f"Tools/Gameplay/{name}").read_text(encoding="utf-8")
subprocess.run(["lune", "run", str(OUT / "test_processing_texts.luau")], cwd=ROOT, check=True)
