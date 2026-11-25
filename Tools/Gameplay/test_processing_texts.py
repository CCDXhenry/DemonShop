"""Exercise production hint rules, translation binding and delayed translator refresh with Lune."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / ".cache" / "processing-texts"
OUT.mkdir(parents=True, exist_ok=True)
SHARED = ROOT / "Scripts/ReplicatedStorage/Scripts/Shared"
CLIENT = ROOT / "Scripts/ReplicatedStorage/Scripts/Client"

(OUT / "GameConfig").mkdir(parents=True, exist_ok=True)
for data_name in ("WeaponData", "CarryToolData", "PersonalAbilityData", "AutomationFacilityData"):
    (OUT / "GameConfig" / f"{data_name}.luau").write_text(
        (SHARED / "GameConfig" / f"{data_name}.luau").read_text(encoding="utf-8"), encoding="utf-8"
    )
for name in ("Hints", "GameTexts", "GameData"):
    source = (SHARED / f"{name}.luau").read_text(encoding="utf-8")
    source = re.sub(r"require\(script.Parent.(\w+)\)", r"require('./\1')", source)
    if name == "GameData":
        for data_name in ("WeaponData", "CarryToolData", "PersonalAbilityData", "AutomationFacilityData"):
            source = source.replace(f"require(script.Parent.GameConfig.{data_name})", f"require('./GameConfig/{data_name}')")
    (OUT / f"{name}.luau").write_text(source, encoding="utf-8")
(OUT / "GameTypes.luau").write_text("return {}", encoding="utf-8")
(OUT / "GameConfig.luau").write_text(
    'return {PotionReward=237,StunHits=5,PoolCapacity=11,ShelfCapacity=13,AttackCooldown=0.6,WeaponSlashAnimation="",WeaponSlashSound=""}',
    encoding="utf-8",
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

# Verify sync-localization-table covers every GameTexts entry, JsonData *_t field, and static touch label with all 18 locales.
import json
EXPECTED_LANGS = {
    "ar", "de", "es", "fr", "id", "it", "ja", "ko",
    "pl", "pt", "ru", "th", "tr", "vi", "zh-cn", "zh-hans", "zh-hant", "zh-tw",
}
sync_source = (ROOT / "Tools/Gameplay/sync-localization-table.luau").read_text(encoding="utf-8")
sync_entries = {}
for m in re.finditer(
    r'Key\s*=\s*"([^"]*)",\s*Source\s*=\s*"([^"]+)",\s*Context\s*=\s*"[^"]*",\s*Example\s*=\s*"[^"]*",\s*Values\s*=\s*\{([^\n]+)\}',
    sync_source,
):
    langs = set(re.findall(r'\["([^"]+)"\]\s*=', m.group(3)))
    assert langs == EXPECTED_LANGS, f"Incomplete locales for {(m.group(1), m.group(2))}: missing {EXPECTED_LANGS - langs}"
    sync_entries[(m.group(1), m.group(2))] = langs

for _, src, key in re.findall(r'(\w+)\s*=\s*\{\s*source\s*=\s*"([^"]+)",\s*key\s*=\s*"([^"]*)"\s*\}', catalog):
    assert (key, src) in sync_entries, f"Missing GameTexts entry in sync-localization-table.luau: {(key, src)}"

for json_path in sorted((ROOT / "JsonData").glob("*.json")):
    rows = json.loads(json_path.read_text(encoding="utf-8"))
    if isinstance(rows, list):
        for row in rows:
            for field, value in row.items():
                if field.endswith("_t") and isinstance(value, str) and value:
                    assert ("", value) in sync_entries, f"Missing {json_path.name}.{field} in sync-localization-table.luau: {value!r}"

for static_label in ("ATTACK", "JUMP", "SPRINT", "RESET VIEW", "EXIT", "DRAW THE RUNE", "SOUL WORKSHOP"):
    assert ("", static_label) in sync_entries, f"Missing static UI text in sync-localization-table.luau: {static_label!r}"

subprocess.run(["lune", "run", str(OUT / "test_processing_texts.luau")], cwd=ROOT, check=True)
