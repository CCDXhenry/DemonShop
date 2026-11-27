"""Run production coverage/save/lease rules with Lune; only service boundaries are mocked."""
from pathlib import Path
import json
import re
import subprocess
import sys
import openpyxl
ROOT=Path(__file__).resolve().parents[2]

def verify_data_tables_primary_key():
    excel_files = sorted(path for path in (ROOT / "ExcelData").glob("*.xlsx") if not path.name.startswith("~$"))
    assert excel_files, "ExcelData/*.xlsx must not be empty"
    for xlsx_path in excel_files:
        wb = openpyxl.load_workbook(xlsx_path, data_only=True)
        ws = wb.active
        assert ws.cell(1, 1).value == "id", f"{xlsx_path.name}: first column name must be 'id', got {ws.cell(1, 1).value!r}"
        assert ws.cell(2, 1).value == "int", f"{xlsx_path.name}: first column type must be 'int', got {ws.cell(2, 1).value!r}"
        seen = set()
        row_count = 0
        for r in range(4, ws.max_row + 1):
            row_vals = [ws.cell(r, c).value for c in range(1, ws.max_column + 1)]
            if not any(v is not None for v in row_vals):
                continue
            val = row_vals[0]
            assert isinstance(val, int) and not isinstance(val, bool) and val >= 1, (
                f"{xlsx_path.name} row {r}: id must be positive int, got {val!r}"
            )
            assert val not in seen, f"{xlsx_path.name} row {r}: duplicate id {val}"
            seen.add(val)
            row_count += 1
        assert row_count >= 1, f"{xlsx_path.name}: must contain at least 1 data row"

    json_files = sorted((ROOT / "JsonData").glob("*.json"))
    assert json_files, "JsonData/*.json must not be empty"
    for json_path in json_files:
        rows = json.loads(json_path.read_text(encoding="utf-8"))
        assert isinstance(rows, list) and len(rows) >= 1, f"{json_path.name}: must be a non-empty JSON array"
        seen = set()
        for idx, row in enumerate(rows, start=1):
            assert isinstance(row, dict) and row, f"{json_path.name}[{idx}]: row must be a non-empty object"
            first_key = next(iter(row.keys()))
            assert first_key == "id", f"{json_path.name}[{idx}]: first key must be 'id', got {first_key!r}"
            val = row["id"]
            assert isinstance(val, int) and not isinstance(val, bool) and val >= 1, (
                f"{json_path.name}[{idx}]: id must be positive int, got {val!r}"
            )
            assert val not in seen, f"{json_path.name}[{idx}]: duplicate id {val}"
            seen.add(val)
        luau_path = ROOT / "Scripts/ReplicatedStorage/Scripts/Shared/GameConfig" / (json_path.stem + ".luau")
        assert luau_path.exists(), f"Missing Luau module for {json_path.name}: {luau_path}"
        luau_text = luau_path.read_text(encoding="utf-8")
        first_fields = re.findall(r"\[\d+\]\s*=\s*\{\s*\[\"([^\"]+)\"\]\s*=\s*([^,\n]+)", luau_text)
        assert len(first_fields) == len(rows), f"{luau_path.name}: row count mismatch ({len(first_fields)} vs {len(rows)})"
        for idx, ((field_name, field_val), json_row) in enumerate(zip(first_fields, rows), start=1):
            assert field_name == "id", f"{luau_path.name}[{idx}]: first field must be 'id', got {field_name!r}"
            assert field_val.strip() == str(json_row["id"]), (
                f"{luau_path.name}[{idx}]: id mismatch ({field_val.strip()} vs {json_row['id']})"
            )
    print(f"PASS: Data table primary key gate ({len(excel_files)} xlsx, {len(json_files)} json/luau)")

verify_data_tables_primary_key()
OUT=ROOT/".cache"/"ragdoll-rules"
OUT.mkdir(parents=True,exist_ok=True)
(OUT/"NumberExtension.luau").write_text((ROOT/"Scripts/ReplicatedStorage/Core/Scripts/Shared/NumberExtension.luau").read_text(encoding="utf-8"),encoding="utf-8")
shared=ROOT/"Scripts/ReplicatedStorage/Scripts/Shared"
server=ROOT/"Scripts/ServerStorage/Scripts"
(OUT/"FoundationDateBoundary.luau").write_text((ROOT/"Tools/Gameplay/FoundationDateBoundary.luau").read_text(encoding="utf-8"),encoding="utf-8")
(OUT/"GameConfig").mkdir(parents=True,exist_ok=True)
for data_name in ("WeaponData","CarryToolData","PersonalAbilityData","AutomationFacilityData"):
    (OUT/"GameConfig"/(data_name+".luau")).write_text((shared/"GameConfig"/(data_name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
for name in ("GameConfig","GameData","GameTexts","GameTypes","Hints","SaveRules","PlayerProfileRules","PaintSurface","StrokePath","VisualRules","CurvedSurface","BodySurfaceData","PhysicsConfig","PaintBodyPose","PaintRotation","BodyPlacementMarkers","RuneGlyphData","RuneStampRules","ThrowArc","AutomationRules","WorldInteractionRules","AutoRunePattern"):
    src_path=(shared/"GameConfig"/"init.luau") if name == "GameConfig" else (shared/(name+".luau"))
    text=src_path.read_text(encoding="utf-8")
    text=text.replace('require(game:GetService("ReplicatedStorage").Core.Scripts.Shared.NumberExtension)', "require('./NumberExtension')")
    text=text.replace("require(ReplicatedStorage.Core.Scripts.Shared.NumberExtension)", "require('./NumberExtension')")
    for dep in ("GameConfig","GameData","GameTexts","GameTypes","Hints","SaveRules","PlayerProfileRules","PaintSurface","CurvedSurface","BodySurfaceData","PhysicsConfig","PaintBodyPose","PaintRotation","BodyPlacementMarkers","RuneGlyphData","RuneStampRules","ThrowArc","AutomationRules","WorldInteractionRules","VisualRules","AutoRunePattern"):
        text=text.replace("require(script.Parent."+dep+")", "require('./"+dep+"')")
    if name == "GameData":
        for data_name in ("WeaponData","CarryToolData","PersonalAbilityData","AutomationFacilityData"):
            text=text.replace("require(script.Parent.GameConfig."+data_name+")", "require('./GameConfig/"+data_name+"')")
    if name == "GameConfig":
        start=text.index('local replicatedStorage:')
        end=text.index('--游戏版本')
        text=text[:start]+"local D=require('./FoundationDateBoundary')\nlocal DateTimeExtension,DateTime=D.DateTimeExtension,D.DateTime\n"+text[end:]
        text="local Color3=require('@lune/roblox').Color3\nlocal Vector3=require('@lune/roblox').Vector3\nlocal game={GameId=0}\n"+text
    if name in ("PaintSurface","StrokePath","VisualRules","CurvedSurface","BodySurfaceData","PhysicsConfig","PaintBodyPose","PaintRotation","BodyPlacementMarkers","RuneStampRules","ThrowArc","AutomationRules","AutoRunePattern"):
        text="local roblox=require('@lune/roblox')\nlocal Vector2,Vector3,CFrame,Color3,Enum=roblox.Vector2,roblox.Vector3,roblox.CFrame,roblox.Color3,roblox.Enum\n"+text
    (OUT/(name+".luau")).write_text(text,encoding="utf-8")
(OUT/"test_throw_arc.luau").write_text((ROOT/"Tools/Gameplay/test_throw_arc.luau").read_text(encoding="utf-8"),encoding="utf-8")
upgrade_rules = shared / "PersonalUpgradeRules.luau"
(OUT / upgrade_rules.name).write_text("local Vector2=require('@lune/roblox').Vector2\n" + upgrade_rules.read_text(encoding="utf-8").replace("require(script.Parent.GameConfig)", "require('./GameConfig')").replace("require(script.Parent.GameData)", "require('./GameData')"), encoding="utf-8")
upgrade_test = ROOT / "Tools/Gameplay/test_personal_upgrades.luau"
(OUT / upgrade_test.name).write_text(upgrade_test.read_text(encoding="utf-8"), encoding="utf-8")
subprocess.run(["lune", "run", str(OUT / upgrade_test.name)], cwd=ROOT, check=True)
subprocess.run(["lune","run",str(OUT/"test_throw_arc.luau")],cwd=ROOT,check=True)
def run_hit_feedback_tests():
    # Execute production hit rules and rendering against real Lune instances; only services are replaced.
    (OUT/"HitFeedbackRules.luau").write_text((shared/"HitFeedbackRules.luau").read_text(encoding="utf-8"),encoding="utf-8")
    text=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/HitPresentation.luau").read_text(encoding="utf-8")
    start=text.index('local ReplicatedStorage =')
    end=text.index('local Presentation =')
    text=text[:start]+"local R=require('@lune/roblox')\nlocal Instance,Enum,CFrame,Vector3=R.Instance,R.Enum,R.CFrame,R.Vector3\nlocal workspace=require('./HitPresentationBoundary')\nlocal Config=require('./GameConfig')\nlocal Rules=require('./HitFeedbackRules')\n"+text[end:]
    text=text.replace("model.Parent=workspace", "model.Parent=workspace.world")
    (OUT/"HitPresentation.luau").write_text(text,encoding="utf-8")
    for name in ("HitPresentationBoundary","test_hit_feedback"):
        (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
    subprocess.run(["lune","run",str(OUT/"test_hit_feedback.luau")],cwd=ROOT,check=True)

    source=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/ClientProcessingManager.luau").read_text(encoding="utf-8")
    start=source.index("function Client.CancelHitFeedback(")
    end=source.index("function Client.OnNotice(",start)
    prefix=(
        "local R=require('@lune/roblox')\n"
        "local Vector3,CFrame=R.Vector3,R.CFrame\n"
        "local B=require('./AttackFeedbackBoundary')\n"
        "local workspace,player,Net,Config,HitRules,Sound=B.workspace,B.player,B.Net,require('./GameConfig'),require('./HitFeedbackRules'),B.Sound or {Play=function()end}\n"
        "local UIManager=B.UIManager\n"
        "local GameData=require('./GameData')\n"
        "local Types=require('./GameTypes')\n"
        "local PersonalRules=require('./PersonalUpgradeRules')\n"
        "local Client={}\n"
    )
    (OUT/"AttackFeedbackClient.luau").write_text(prefix+source[start:end]+"\nreturn Client\n",encoding="utf-8")
    source=(server/"ProcessingManager.luau").read_text(encoding="utf-8")
    start=source.index("function Manager.Attack(")
    end=source.index("function Manager.Paint(",start)
    throw_start = source.index("function Manager.Throw(")
    throw_end = source.index("local function SyncCarryRig(", throw_start)
    server_prefix = """local B = require('./AttackFeedbackBoundary')
local R = require('@lune/roblox')
local Vector3, CFrame = R.Vector3, R.CFrame
local workspace, task, Net, NPC = B.workspace, B.task, B.Net, B.NPC
local Carry, Ground = B.Carry, B.Ground
local Config = require('./GameConfig')
local Physics = require('./PhysicsConfig')
local ThrowArc = require('./ThrowArc')
local PersonalRules = require('./PersonalUpgradeRules')
local GameData = require('./GameData')
local NumberExtension = require('./NumberExtension')
local Manager = {}
"""
    (OUT / "AttackFeedbackServer.luau").write_text(
        server_prefix + source[start:end] + source[throw_start:throw_end] + "\nreturn Manager\n",
        encoding="utf-8",
    )
    source = (ROOT / "Scripts/ReplicatedStorage/Scripts/Client/ManualThrowController.luau").read_text(encoding="utf-8")
    controller_prefix = """local B = require('./AttackFeedbackBoundary')
local R = require('@lune/roblox')
local Vector2, UDim2, Enum = R.Vector2, R.UDim2, R.Enum
local workspace, Players, Net = B.workspace, {LocalPlayer = B.player}, B.Net
local Config = require('./PhysicsConfig').ManualThrow
local PersonalRules = require('./PersonalUpgradeRules')
"""
    (OUT / "ManualThrowController.luau").write_text(
        controller_prefix + source[source.index("local Controller = {}"):],
        encoding="utf-8",
    )
    text=(shared/"ProcessingNet.luau").read_text(encoding="utf-8")
    prefix="local Types=require('./GameTypes')\nlocal Surface=require('./PaintSurface')\nlocal VisualRules=require('./VisualRules')\nlocal Curve=require('./CurvedSurface')\nlocal Config=require('./GameConfig')\nlocal GameData=require('./GameData')\nlocal requestEvent,notifyEvent={},{}\nlocal BodyPose=require('./PaintBodyPose')\n"
    (OUT/"VisualProtocol.luau").write_text(prefix+text[text.index('local Net ='):],encoding="utf-8")
    for name in ("AttackFeedbackBoundary","test_attack_feedback"):
        (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
    subprocess.run(["lune","run",str(OUT/"test_attack_feedback.luau")],cwd=ROOT,check=True)

if "--hit-only" in sys.argv:
    run_hit_feedback_tests()
    raise SystemExit(0)

(OUT/"PlayerSaveLeaseRules.luau").write_text((server/"PlayerSaveLeaseRules.luau").read_text(encoding="utf-8"),encoding="utf-8")
(OUT/"test_curved_surface.luau").write_text((ROOT/"Tools/Gameplay/test_curved_surface.luau").read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_curved_surface.luau")],cwd=ROOT,check=True)
text=(server/"ServerPlayerSaveStore.luau").read_text(encoding="utf-8")
start=text.index('local ServerStorage =')
end=text.index('type Record =')
text=text.replace('local Config = require(Shared:WaitForChild("GameConfig"))',"local Config = require('./GameConfig')")
text=text[:start]+"local Mock=require('./Mock')\nlocal HttpService=Mock.HttpService\nlocal DataStoreTool=Mock.DataStoreTool\nlocal SaveRules=require('./SaveRules')\nlocal Rules=require('./PlayerSaveLeaseRules')\nlocal task=require('@lune/task')\n"+text[end:]
(OUT/"ServerPlayerSaveStore.luau").write_text(text,encoding="utf-8")
text=(server/"Painting.luau").read_text(encoding="utf-8")
start=text.index('local ReplicatedStorage =')
end=text.index('local Painting =')
text="local roblox=require('@lune/roblox')\nlocal Vector2,Vector3,CFrame=roblox.Vector2,roblox.Vector3,roblox.CFrame\nlocal Enum=roblox.Enum\nlocal RaycastParams={new=function() return {} end}\nlocal workspace=require('./PaintingWorld')\nlocal Config=require('./GameConfig')\nlocal Types=require('./GameTypes')\nlocal Surface=require('./PaintSurface')\nlocal Curve=require('./CurvedSurface')\nlocal Rotation=require('./PaintRotation')\nlocal BodyPose=require('./PaintBodyPose')\n"+text[end:]
(OUT/"Painting.luau").write_text(text,encoding="utf-8")
for name in ("PaintingWorld","test_painting","test_paint_rotation"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
client=ROOT/"Scripts/ReplicatedStorage/Scripts/Client"
text=(client/"BodyPresentation.luau").read_text(encoding="utf-8")
prefix="local R=require('@lune/roblox')\nlocal CFrame,Vector3,Instance,Enum=R.CFrame,R.Vector3,R.Instance,R.Enum\nlocal workspace={Gravity=196.2}\nlocal GameConfig=require('./GameConfig')\nlocal Config=require('./PhysicsConfig')\nlocal Rotation=require('./PaintRotation')\nlocal Pose=require('./PaintBodyPose')\n"
(OUT/"BodyPresentation.luau").write_text(prefix+text[text.index("local Presentation={}"):],encoding="utf-8")
text=(client/"PaintBrushContact.luau").read_text(encoding="utf-8")
prefix="local R=require('@lune/roblox')\nlocal Vector2,Vector3,Enum,CFrame=R.Vector2,R.Vector3,R.Enum,R.CFrame\nlocal Config=require('./GameConfig')\nlocal Surface=require('./PaintSurface')\nlocal Curve=require('./CurvedSurface')\nlocal Rotation=require('./PaintRotation')\nlocal workspace=require('./PaintingWorld')\nlocal RaycastParams={new=function() return {} end}\n"
(OUT/"PaintBrushContact.luau").write_text(prefix+text[text.index("local Brush ="):],encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_paint_rotation.luau")],cwd=ROOT,check=True)
for name in ("Mock","test_rules"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_rules.luau")],cwd=ROOT,check=True)

text=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/CharacterPresentation.luau").read_text(encoding="utf-8")
start=text.index("local Players =")
end=text.index("local Presentation =")
text=text[:start]+"local Boundary=require('./WeaponPresentationBoundary')\nlocal Players=Boundary.Players\nlocal Instance,Enum,CFrame=Boundary.Instance,Boundary.Enum,Boundary.CFrame\nlocal Config=require('./GameConfig')\nlocal PersonalRules=require('./PersonalUpgradeRules')\n"+text[end:]
(OUT/"CharacterPresentation.luau").write_text(text,encoding="utf-8")
for name in ("WeaponPresentationBoundary","test_weapon_presentation"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_weapon_presentation.luau")],cwd=ROOT,check=True)
def write_model_templates(out_name, rs_expr):
    src = (shared / "ModelTemplates.luau").read_text(encoding="utf-8")
    body = src[src.index("local ModelTemplates = {}"):].replace(":WaitForChild(", ":FindFirstChild(")
    (OUT / out_name).write_text(f"local ReplicatedStorage = {rs_expr}\n" + body, encoding="utf-8")

write_model_templates("ClientPreloadModelTemplates.luau", "require('./ClientPreloadBoundary').ReplicatedStorage")
preloader_src=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/AssetPreloader.luau").read_text(encoding="utf-8")
preloader_prefix="local task=require('@lune/task')\nlocal B=require('./ClientPreloadBoundary')\nlocal ContentProvider,RunService=B.ContentProvider,B.RunService\nlocal Instance,Enum,UDim2=B.Instance,B.Enum,B.UDim2\n"
(OUT/"AssetPreloader.luau").write_text(preloader_prefix+preloader_src[preloader_src.index("local AssetPreloader = {}"):],encoding="utf-8")

warmup_src=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/AssetWarmup.luau").read_text(encoding="utf-8")
warmup_src=warmup_src.replace("workspace.CurrentCamera", "B.GetCurrentCamera()").replace("clone:PivotTo(targetPose)", "B.PivotTo(clone, targetPose)")
warmup_prefix="local task=require('@lune/task')\nlocal B=require('./ClientPreloadBoundary')\nlocal Players,RunService,workspace=B.Players,B.RunService,B.workspace\nlocal Instance,Vector3,CFrame,Enum,UDim2=B.Instance,B.Vector3,B.CFrame,B.Enum,B.UDim2\n"
(OUT/"AssetWarmup.luau").write_text(warmup_prefix+warmup_src[warmup_src.index("local AssetWarmup = {}"):],encoding="utf-8")

text=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/ClientPreloadManager.luau").read_text(encoding="utf-8")
prefix="local B=require('./ClientPreloadBoundary')\nlocal Players,ReplicatedStorage,Lighting=B.Players,B.ReplicatedStorage,B.Lighting\nlocal AssetPreloader=require('./AssetPreloader')\nlocal AssetWarmup=require('./AssetWarmup')\nlocal Config=require('./GameConfig')\nlocal GameData=require('./GameData')\nlocal ModelTemplates=require('./ClientPreloadModelTemplates')\n"
(OUT/"ClientPreloadManager.luau").write_text(prefix+text[text.index("local Manager = {}"):],encoding="utf-8")
for name in ("ClientPreloadBoundary","test_client_preload"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_client_preload.luau")],cwd=ROOT,check=True)

subprocess.run(["lune","run",str(OUT/"test_painting.luau")],cwd=ROOT,check=True)

# Exercise the complete production request dispatcher with real painting rules.
source=(server/"ProcessingManager.luau").read_text(encoding="utf-8")
prefix="local CFrame=require('@lune/roblox').CFrame\nlocal Config=require('./GameConfig')\nlocal GameData=require('./GameData')\nlocal Painting=require('./Painting')\nlocal PaintRotation=require('./PaintRotation')\nlocal Surface=require('./PaintSurface')\nlocal NumberExtension=require('./NumberExtension')\nlocal AutomationAgents={New=function() return nil end,SyncUnlocked=function() end,Step=function() return false end,Destroy=function() end}\nlocal B=require('./PaintRequestBoundary')\nlocal Net,workspace,Scene=B.Net,B.workspace,B.Scene\nlocal Random={new=function() return {} end}\n"
(OUT/"PaintRequestManager.luau").write_text(prefix+source[source.index('type PlayerData ='):],encoding="utf-8")
for name in ("PaintRequestBoundary","test_paint_requests"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_paint_requests.luau")],cwd=ROOT,check=True)


text=(server/"Replication.luau").read_text(encoding="utf-8")
start=text.index('local ReplicatedStorage =')
end=text.index('local Replication =')
text="local Types=require('./GameTypes')\nlocal Net=require('./ReplicationNet')\n"+text[end:]
(OUT/"Replication.luau").write_text(text,encoding="utf-8")
for name in ("ReplicationNet","test_replication"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_replication.luau")],cwd=ROOT,check=True)
text=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/PotionShelfView.luau").read_text(encoding="utf-8")
write_model_templates("PotionShelfModelTemplates.luau", "require('./test_potion_shelf').Boundary.ReplicatedStorage")
prefix="""local R=require('@lune/roblox')
local Instance,Vector3=R.Instance,R.Vector3
local B=require('./test_potion_shelf').Boundary
local ReplicatedStorage,workspace=B.ReplicatedStorage,B.workspace
local ModelTemplates=require('./PotionShelfModelTemplates')
"""
text=text[text.index("local View ="):]
for model in ("bottle.model", "model"):
    text=text.replace(f"{model}:GetPivot()",f"{model}.WorldPivot").replace(f"{model}:PivotTo(",f"B.PivotTo({model}, ")
(OUT/"PotionShelfView.luau").write_text(prefix+text,encoding="utf-8")
(OUT/"test_potion_shelf.luau").write_text((ROOT/"Tools/Gameplay/test_potion_shelf.luau").read_text(encoding="utf-8"),encoding="utf-8")
(OUT/"run_potion_shelf.luau").write_text("require('./test_potion_shelf').Run(require('./PotionShelfView'))\n",encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"run_potion_shelf.luau")],cwd=ROOT,check=True)
(OUT/"test_stroke_path.luau").write_text((ROOT/"Tools/Gameplay/test_stroke_path.luau").read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_stroke_path.luau")],cwd=ROOT,check=True)
# Execute extracted UI managers with real Lune GUI instances; each simulated client owns a pair.
for name in ("PaintFaceGuiManager", "PaintCellFrameManager"):
    source=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/UIManager"/(name+".luau")).read_text(encoding="utf-8")
    prefix="local R=require('@lune/roblox')\nlocal Vector2,UDim2,Color3=R.Vector2,R.UDim2,R.Color3\nlocal B=require('./StrokeViewBoundary')\nlocal Players,ReplicatedStorage,AssetService,Content=B.Players,B.ReplicatedStorage,B.AssetService,B.Content\nlocal Config=require('./GameConfig')\nlocal RuneGlyphs=require('./RuneGlyphData')\n"
    (OUT/(name+".luau")).write_text(prefix+source[source.index('local Manager ='):],encoding="utf-8")
(OUT/"PaintUIBoundary.luau").write_text("local F=require('./PaintFaceGuiManager')\nlocal C=require('./PaintCellFrameManager')\nreturn {GetPaintFaceGuiManager=function() return F.new() end,GetPaintCellFrameManager=function() return C.new() end}\n",encoding="utf-8")
text=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/PaintView.luau").read_text(encoding="utf-8")
start=text.index('local View =')
text="local Roblox=require('@lune/roblox')\nlocal Vector2,Vector3,UDim2=Roblox.Vector2,Roblox.Vector3,Roblox.UDim2\nlocal Boundary=require('./StrokeViewBoundary')\nlocal Players,ReplicatedStorage=Boundary.Players,Boundary.ReplicatedStorage\nlocal Config=require('./GameConfig')\nlocal Types=require('./GameTypes')\nlocal Surface=require('./PaintSurface')\nlocal Curve=require('./CurvedSurface')\nlocal RuneRules=require('./RuneStampRules')\nlocal CurvedView={}\nlocal UIManager=require('./PaintUIBoundary')\n"+text[start:]
(OUT/"PaintView.luau").write_text(text,encoding="utf-8")
for name in ("StrokeViewBoundary","test_stroke_view"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_stroke_view.luau")],cwd=ROOT,check=True)

text=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/VisualUpload.luau").read_text(encoding="utf-8")
start=text.index('local Upload=')
text="local Config=require('./GameConfig')\nlocal Types=require('./GameTypes')\nlocal Net=require('./VisualNet')\nlocal BodyPose=require('./PaintBodyPose')\n"+text[start:]
(OUT/"VisualUpload.luau").write_text(text,encoding="utf-8")
for name in ("VisualNet","test_visual_sync"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
text=(shared/"ProcessingNet.luau").read_text(encoding="utf-8")
text="local Types=require('./GameTypes')\nlocal Surface=require('./PaintSurface')\nlocal VisualRules=require('./VisualRules')\nlocal Curve=require('./CurvedSurface')\nlocal Config=require('./GameConfig')\nlocal requestEvent,notifyEvent={},{}\nlocal BodyPose=require('./PaintBodyPose')\n"+text[text.index('local Net ='):]
(OUT/"VisualProtocol.luau").write_text(text,encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_visual_sync.luau")],cwd=ROOT,check=True)
(OUT/"PaintView.luau").write_text((OUT/"PaintView.luau").read_text(encoding="utf-8").replace("local CurvedView={}", "local CurvedView={new=function() return {Bind=function() end,Apply=function() end,Remove=function() end,ReleaseMirrors=function() end,Destroy=function() end} end}"),encoding="utf-8")
(OUT/"test_curved_visual_pipeline.luau").write_text((ROOT/"Tools/Gameplay/test_curved_visual_pipeline.luau").read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_curved_visual_pipeline.luau")],cwd=ROOT,check=True)
(OUT/"test_table_body_pose.luau").write_text((ROOT/"Tools/Gameplay/test_table_body_pose.luau").read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_table_body_pose.luau")],cwd=ROOT,check=True)
(OUT/"test_visual_scale.luau").write_text((ROOT/"Tools/Gameplay/test_visual_scale.luau").read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_visual_scale.luau")],cwd=ROOT,check=True)

# Execute the actual curved rasterizer. Only engine image binding and clock are mocked.
text=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/CurvedPaintView.luau").read_text(encoding="utf-8")
start=text.index('local View =')
text="local R=require('@lune/roblox')\nlocal Vector2,Vector3=R.Vector2,R.Vector3\nlocal B=require('./CurvedRasterBoundary')\nlocal AssetService,Content,workspace,os=B.AssetService,B.Content,B.workspace,B.os\nlocal Curve=require('./CurvedSurface')\nlocal Data=require('./BodySurfaceData')\nlocal Config=require('./GameConfig')\nlocal Types=require('./GameTypes')\nlocal RuneGlyphs=require('./RuneGlyphData')\nlocal RuneRules=require('./RuneStampRules')\n"+text[start:]
(OUT/"CurvedPaintView.luau").write_text(text,encoding="utf-8")
for name in ("CurvedRasterBoundary","CurvedRasterReference","test_curved_raster"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_curved_raster.luau")],cwd=ROOT,check=True)
(OUT/"test_curved_raster_stream.luau").write_text((ROOT/"Tools/Gameplay/test_curved_raster_stream.luau").read_text(encoding="utf-8"),encoding="utf-8")
for fps in (30, 60):
    for pixels in (100, 300):
        # Isolate large stress fixtures so another case's retained memory does not skew timing.
        subprocess.run(["lune","run",str(OUT/"test_curved_raster_stream.luau"),str(fps),str(pixels)],cwd=ROOT,check=True)

# Exercise production client lifecycle methods with input/camera/network boundaries.
source=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/ClientProcessingManager.luau").read_text(encoding="utf-8")
methods=[
    source[source.index("local function ActivePaintTarget("):source.index("function Client.new(")],
    source[source.index("function Client.Carried("):source.index("function Client.TriggerAutoFlip(")],
    source[source.index("local function PaintControl("):source.index("function Client.Paint(")],
]
for name in ("TriggerAutoFlip","ExitView","OnNotice","RequestPaintEnd","Paint","StepPaintRotation","Update","OnInput","OnMove","OnRelease","ResetPaintView","UpdateAltar"):
    start=source.index("function Client."+name+"(")
    end=source.find("\nfunction Client.",start+1)
    methods.append(source[start:end])
prefix=(
    "local R=require('@lune/roblox')\n"
    "local Vector2,Vector3,Enum,CFrame=R.Vector2,R.Vector3,R.Enum,R.CFrame\n"
    "local B=require('./PaintClientBoundary')\n"
    "local player,workspace,os,UserInputService=B.player,B.workspace,B.os,B.UserInputService\n"
    "local Config=require('./GameConfig')\n"
    "local PersonalRules=require('./PersonalUpgradeRules')\n"
    "local NumberExtension=require('./NumberExtension')\n"
    "local Physics=require('./PhysicsConfig')\n"
    "local Hints=require('./Hints')\n"
    "local Net=require('./VisualNet')\n"
    "local Rotation=require('./PaintRotation')\n"
    "local Surface=require('./PaintSurface')\n"
    "local Curve=require('./CurvedSurface')\n"
    "local PaintBrush=require('./PaintBrushContact')\n"
    "PaintBrush.Resolver=function() return B.resolve end\n"
    "local TablePose=function() return CFrame.identity end\n"
    "local positions={Pool=Vector3.new(100,0,0),Table=Vector3.new(100,0,0),Altar=Vector3.new(100,0,0),Shelf=Vector3.new(100,0,0),Sigil=Vector3.new(100,0,0)}\n"
    "local Sound={Play=function() end}\n"
    "local UIManager={GetTargetGuiManager=function() return {Refresh=function() end,RefreshHits=function() end} end,HasShowingWindow=function() return false end}\n"
    "local Client={}\n"
    "Client.__index=Client\n"
)
(OUT/"PaintClientLifecycle.luau").write_text(prefix+"\n".join(methods)+"\nreturn Client\n",encoding="utf-8")
for name in ("PaintClientBoundary","test_paint_client_lifecycle"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_paint_client_lifecycle.luau")],cwd=ROOT,check=True)

# Restore framework behavior under offline service boundaries; production methods are retained.
for name in ("FoundationBoundary", "test_foundation"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
(OUT/"LifecycleTool.luau").write_text("local task=require('@lune/task')\n"+(shared/"LifecycleTool.luau").read_text(encoding="utf-8"),encoding="utf-8")
def foundation_module(name, source_path, marker, prefix):
    source=(ROOT/source_path).read_text(encoding="utf-8")
    (OUT/(name+".luau")).write_text(prefix+source[source.index(marker):],encoding="utf-8")
foundation_module("FoundationProtocol", "Scripts/ReplicatedStorage/Scripts/Shared/FoundationNet.luau", "local Net =", "local requestEvent,notifyEvent={},{}\nlocal NetMsg={}\n")
foundation_module("ServerGameInfo", "Scripts/ServerStorage/Scripts/ServerGameInfo.luau", "export type PlayerInfo", "local Config=require('./GameConfig')\nlocal B=require('./FoundationBoundary')\nlocal SaveRules=require('./SaveRules')\nlocal ProfileRules=require('./PlayerProfileRules')\nlocal Config=require('./GameConfig')\nlocal Net=B.Net\nlocal Store=require('./ServerPlayerSaveStore')\nlocal ServerMsg=B.ServerMsg\nlocal task=require('@lune/task')\n")
foundation_module("ClientGameInfo", "Scripts/ReplicatedStorage/Scripts/Client/ClientGameInfo.luau", "local profile:", "local Config=require('./GameConfig')\nlocal SaveRules=require('./SaveRules')\nlocal ClientMsg=require('./FoundationBoundary').ClientMsg\n")
foundation_module("ServerMarketplaceManager", "Scripts/ServerStorage/Scripts/ServerGameManager/ServerMarketplaceManager.luau", "local Manager =", "local B=require('./FoundationBoundary')\nlocal MarketplaceService,Enum=B.MarketplaceService,B.Enum\nlocal Config=require('./GameConfig')\nlocal Lifecycle=require('./LifecycleTool')\nlocal Info=require('./ServerGameInfo')\nlocal Analytics=B.Analytics\n")
foundation_module("ServerPlayerSettingManager", "Scripts/ServerStorage/Scripts/ServerGameManager/ServerPlayerSettingManager.luau", "local Manager =", "local Net=require('./FoundationBoundary').Net\nlocal Config=require('./GameConfig')\nlocal Lifecycle=require('./LifecycleTool')\nlocal Info=require('./ServerGameInfo')\n")
foundation_module("ServerGameManager", "Scripts/ServerStorage/Scripts/ServerGameManager/init.luau", "local Manager =", "local B=require('./FoundationBoundary')\nlocal Players,RunService,DataStoreService,game=B.Players,B.RunService,B.DataStoreService,B.game\nlocal task=require('@lune/task')\nlocal Lifecycle=require('./LifecycleTool')\nlocal Config=require('./GameConfig')\nlocal Info=require('./ServerGameInfo')\nlocal Store=require('./ServerPlayerSaveStore')\nlocal Processing,Analytics,Chat=B.Processing,B.Analytics,B.Chat\nlocal Settings=require('./ServerPlayerSettingManager')\nlocal Marketplace=require('./ServerMarketplaceManager')\nlocal Context=B.Context\n")
foundation_module("ClientGameManager", "Scripts/ReplicatedStorage/Scripts/Client/ClientGameManager.luau", "local Manager =", "local B=require('./FoundationBoundary')\nlocal Players=B.Players\nlocal StarterGui,Enum=B.StarterGui,B.Enum\nlocal Config=require('./GameConfig')\nlocal RunService,Net,Sound,UIManager,Processing=B.RunService,B.Net,B.Sound,B.UI,B.ClientProcessing\nlocal Toolbar=B.ClientToolbar\nlocal Lifecycle=require('./LifecycleTool')\nlocal SaveRules=require('./SaveRules')\nlocal Info=require('./ClientGameInfo')\n")
foundation_module("PlayerSaveInfoVersionUpdateTool", "Scripts/ServerStorage/Scripts/PlayerSaveInfoVersionUpdateTool/init.luau", "local Tool =", "local Config=require('./GameConfig')\nlocal Rules=require('./SaveRules')\n")
subprocess.run(["lune","run",str(OUT/"test_foundation.luau")],cwd=ROOT,check=True)

foundation_module("GuiWrapperBase", "Scripts/ReplicatedStorage/Scripts/Client/UIManager/GuiWrapperBase.luau", "local GuiWrapperBase =", "local LifecycleTool=require('./LifecycleTool')\n")
foundation_module("GameFrameWrapper", "Scripts/ReplicatedStorage/Scripts/Client/UIManager/GameFrameWrapper.luau", "local Wrapper =", "local U=require('./FoundationUIBoundary')\nlocal workspace=U.workspace\nlocal GuiWrapperBase=require('./GuiWrapperBase')\nlocal Lifecycle=require('./LifecycleTool')\n")
for name in ("FoundationUIBoundary", "test_foundation_ui"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
foundation_module("ProcessingTextTool", "Scripts/ReplicatedStorage/Scripts/Client/ProcessingTextTool.luau", "local Tool =", "local U=require('./FoundationUIBoundary')\nlocal GameTexts=require('./GameTexts')\nlocal TranslationTool,TextFitting=U.TranslationTool,U.TextFitting\n")
for name in ("GameScreenGuiManager", "TargetGuiManager", "ScreenLayoutGuideFrameManager"):
    foundation_module(name, "Scripts/ReplicatedStorage/Scripts/Client/UIManager/"+name+".luau", "local Manager =", "local R=require('@lune/roblox')\nlocal UDim2,Vector2,Enum=R.UDim2,R.Vector2,R.Enum\nlocal U=require('./FoundationUIBoundary')\nlocal Players,ReplicatedStorage,workspace,UserInputService,GuiService=U.Players,{UI=U.templates},U.workspace,U.UserInputService,U.GuiService\nlocal TweenService,TweenInfo=U.TweenService,U.TweenInfo\nlocal ProcessingText=require('./ProcessingTextTool')\nlocal Lifecycle=require('./LifecycleTool')\nlocal NumberExtension=require('./NumberExtension')\nlocal Config=require('./GameConfig')\nlocal PaintPointer=U.PaintPointer\n")
source=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/UIManager/init.luau").read_text(encoding="utf-8")
start=source.index("local ModalTransparency:")
prefix="local U=require('./FoundationUIBoundary')\nlocal UIManager={}\nlocal LifecycleTool=require('./LifecycleTool')\nlocal scope=LifecycleTool.new()\nlocal initialized=false\nlocal buttonEffects={}\nlocal uiTemplatesFolder=U.templates\nlocal ClientMsg,TextFitting,GameSoundTool=U.ClientMsg,U.TextFitting,U.Sound\nlocal tweenService,workspace,Enum,TweenInfo=U.TweenService,U.workspace,U.Enum,U.TweenInfo\nlocal userInputService=U.UserInputService\nlocal guiService=U.GuiService\nlocal Vector2=require('@lune/roblox').Vector2\nlocal windowOrder={}\nlocal viewportScope=nil\nlocal ownedGui=nil\nlocal hudWrapper=nil\nlocal Players=U.Players\nlocal GameFrameWrapper=require('./GameFrameWrapper')\n"
prefix+="local screenManager=require('./GameScreenGuiManager').new()\nlocal targetManager=require('./TargetGuiManager').new()\nlocal faceManager=require('./PaintFaceGuiManager').new()\nlocal cellManager=require('./PaintCellFrameManager').new()\nlocal guideManager=require('./ScreenLayoutGuideFrameManager').new()\n"
(OUT/"UIManager.luau").write_text(prefix+source[start:],encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_foundation_ui.luau")],cwd=ROOT,check=True)
(OUT/"test_ui_template_managers.luau").write_text((ROOT/"Tools/Gameplay/test_ui_template_managers.luau").read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_ui_template_managers.luau")],cwd=ROOT,check=True)
foundation_module("TouchJumpController", "Scripts/ReplicatedStorage/Scripts/Client/TouchJumpController.luau", "local Controller =", "local R=require('@lune/roblox')\nlocal UDim2,Enum=R.UDim2,R.Enum\nlocal U=require('./FoundationUIBoundary')\nlocal Players,GuiService,RunService,UserInputService=U.Players,U.GuiService,U.RunService,U.UserInputService\nlocal Lifecycle=require('./LifecycleTool')\n")
(OUT/"test_touch_jump.luau").write_text((ROOT/"Tools/Gameplay/test_touch_jump.luau").read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_touch_jump.luau")],cwd=ROOT,check=True)


# Execute named wire and compatibility adapter against shared remote signals.
for name in ("FoundationWireBoundary", "test_foundation_wire"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
foundation_module("FoundationWire", "Scripts/ReplicatedStorage/Scripts/Shared/NetMsg.luau", "local Net =", "local W=require('./FoundationWireBoundary')\nlocal folder,Processing=W.folder,W.Processing\nlocal Config=require('./GameConfig')\n")
foundation_module("FoundationAdapter", "Scripts/ReplicatedStorage/Scripts/Shared/FoundationNet.luau", "local Net =", "local NetMsg=require('./FoundationWire')\n")
foundation_module("PlayerContextTool", "Scripts/ServerStorage/Scripts/PlayerContextTool.luau", "local Tool =", "local Config=require('./GameConfig')\nlocal LocalizationService={GetCountryRegionForPlayerAsync=function()error('test unavailable region')end}\nlocal ConfigService={}\n")
subprocess.run(["lune","run",str(OUT/"test_foundation_wire.luau")],cwd=ROOT,check=True)
subprocess.run(["python",str(ROOT/"Tools/Gameplay/check_foundation_contracts.py")],cwd=ROOT,check=True)

subprocess.run(["lune","run",str(ROOT/"Tools/Gameplay/test_foundation_assets.luau")],cwd=ROOT,check=True)

# Execute actual analytics queue and deadline code with memory HTTP and deterministic clocks.
for name in ("AnalyticsBoundary", "test_analytics"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
foundation_module("AnalyticsTool", "Scripts/ServerStorage/Scripts/AnalyticsTool.luau", "local Analytics =", "local A=require('./AnalyticsBoundary')\nlocal HttpService,RunService,Config,Info,GameAnalytics,ServerConfig=A.HttpService,A.RunService,A.Config,A.Info,A.GameAnalytics,A.ServerConfig\nlocal Lifecycle=require('./LifecycleTool')\nlocal os,task,warn=A.os,A.task,A.warn\n")
subprocess.run(["lune","run",str(OUT/"test_analytics.luau")],cwd=ROOT,check=True)

for name in ("ChatBoundary", "test_foundation_chat"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
foundation_module("ServerPlayerChatCommandManager", "Scripts/ServerStorage/Scripts/ServerGameManager/ServerPlayerChatCommandManager.luau", "local Manager =", "local C=require('./ChatBoundary')\nlocal Players,RunService,TextChatService,TeleportService,Config,GMConfig,Instance,Info,game=C.Players,C.RunService,C.TextChatService,C.TeleportService,C.Config,C.GMConfig,C.Instance,C.Info,C.game\nlocal Lifecycle=require('./LifecycleTool')\n")
subprocess.run(["lune","run",str(OUT/"test_foundation_chat.luau")],cwd=ROOT,check=True)


run_hit_feedback_tests()

geometry_source = (shared / "CageGeometry.luau").read_text(encoding="utf-8")
(OUT / "CageGeometry.luau").write_text(
    "local R=require('@lune/roblox')\nlocal CFrame,Vector3=R.CFrame,R.Vector3\nlocal Physics=require('./PhysicsConfig')\n"
    + geometry_source[geometry_source.index("local Geometry ="):],
    encoding="utf-8",
)

# Exercise station prompt distances, toolbar potion isolation, respawn rescue, and looped audio with production modules.
for name in ("StationPotionBoundary", "test_station_and_potions"):
    (OUT / (name + ".luau")).write_text((ROOT / "Tools/Gameplay" / (name + ".luau")).read_text(encoding="utf-8"), encoding="utf-8")

zone_src = (server / "StreetWalkZones.luau").read_text(encoding="utf-8")
(OUT / "StreetWalkZones.luau").write_text("local Vector3=require('@lune/roblox').Vector3\n" + zone_src, encoding="utf-8")
for test_name in ("test_street_walk_zones", "test_npc_street_motion", "test_npc_crowd_ai"):
    subprocess.run(["lune", "run", f"Tools/Gameplay/{test_name}.luau"], cwd=ROOT, check=True)
scene_src = (server / "Scene.luau").read_text(encoding="utf-8")
scene_body = scene_src[scene_src.index("local Scene = {}"):].replace(":WaitForChild(", ":FindFirstChild(")
scene_prefix = (
    "local R=require('@lune/roblox')\n"
    "local Instance,Vector3,CFrame,Enum=R.Instance,R.Vector3,R.CFrame,R.Enum\n"
    "local B=require('./StationPotionBoundary')\n"
    "local workspace,RaycastParams,PhysicsService=B.workspace,B.RaycastParams,B.PhysicsService\n"
    "local Physics=require('./PhysicsConfig')\n"
    "local Config=require('./GameConfig')\n"
    "local ThrowArc=require('./ThrowArc')\n"
    "local PaintRotation=require('./PaintRotation')\n"
    "local BodyPlacementMarkers=require('./BodyPlacementMarkers')\n"
    "local FixedCamera=require('./StationFixedCamera')\n"
    "local CageGeometry=require('./CageGeometry')\n"
    "local StreetZones=require('./StreetWalkZones')\n"
)
fixed_cam_src = (shared / "FixedCamera.luau").read_text(encoding="utf-8")
fixed_cam_body = fixed_cam_src[fixed_cam_src.index("export type MarkerSettings ="):]
station_cam_prefix = (
    "local R=require('@lune/roblox')\n"
    "local Instance,Vector3,CFrame,Color3,Enum=R.Instance,R.Vector3,R.CFrame,R.Color3,R.Enum\n"
    "local B=require('./StationPotionBoundary')\n"
    "local Players,Workspace=B.Players,B.workspace\n"
    "local TweenService={Create=function() return {Play=function() end,Cancel=function() end,Destroy=function() end,Completed={Connect=function() return {Disconnect=function() end} end}} end}\n"
)
(OUT / "StationFixedCamera.luau").write_text(station_cam_prefix + fixed_cam_body, encoding="utf-8")
(OUT / "StationScene.luau").write_text(scene_prefix + scene_body, encoding="utf-8")
(OUT / "StationSceneFallback.luau").write_text(scene_prefix + scene_body, encoding="utf-8")

rep_src = (server / "Replication.luau").read_text(encoding="utf-8")
(OUT / "StationReplication.luau").write_text(
    "local Types=require('./GameTypes')\nlocal Net=require('./StationPotionBoundary').Net\n" + rep_src[rep_src.index("local Replication ="):],
    encoding="utf-8",
)

write_model_templates("StationModelTemplates.luau", "require('./StationPotionBoundary').ReplicatedStorage")
agents_src = (server / "AutomationAgents.luau").read_text(encoding="utf-8")
agents_body = agents_src[agents_src.index("local AutomationAgents = {}"):]
agents_body = re.sub(r"\b([A-Za-z_][\w.]*):PivotTo\(", r"B.PivotTo(\1, ", agents_body)
agents_body = re.sub(r"([A-Za-z_][\w.]*):GetPivot\(\)", r"\1.WorldPivot", agents_body)
agents_prefix = (
    "local R=require('@lune/roblox')\n"
    "local CFrame,Vector3,Color3,Instance,Enum=R.CFrame,R.Vector3,R.Color3,R.Instance,R.Enum\n"
    "local Config=require('./GameConfig')\n"
    "local GameData=require('./GameData')\n"
    "local GameTexts=require('./GameTexts')\n"
    "local Types=require('./GameTypes')\n"
    "local Physics=require('./PhysicsConfig')\n"
    "local Lifecycle=require('./LifecycleTool')\n"
    "local ModelTemplates=require('./StationModelTemplates')\n"
    "local B=require('./StationPotionBoundary')\n"
    "local Players,ReplicatedStorage,workspace,RaycastParams=B.Players,B.ReplicatedStorage,B.workspace,B.RaycastParams\n"
    "local Net,NPC,Carry,Ragdoll,Scene=B.Net,B.NPC,B.Carry,B.Ragdoll,require('./StationScene')\n"
)
(OUT / "AutomationAgents.luau").write_text(agents_prefix + agents_body, encoding="utf-8")

movement_text = (server / "PersonalMovement.luau").read_text(encoding="utf-8")
(OUT / "PersonalMovement.luau").write_text(
    "local Vector3=require('@lune/roblox').Vector3\nlocal Config=require('./GameConfig')\nlocal Rules=require('./PersonalUpgradeRules')\n"
    + movement_text[movement_text.index("local Movement ="):],
    encoding="utf-8",
)
pm_src = (server / "ProcessingManager.luau").read_text(encoding="utf-8")
pm_body = pm_src[pm_src.index("type PlayerData ="):]
pm_body = re.sub(r"\b([A-Za-z_]\w*):WaitForChild\(", r"B.WaitForChild(\1, ", pm_body)
pm_body = re.sub(r"\b([A-Za-z_]\w*):EquipTool\(", r"B.EquipTool(\1, ", pm_body)
pm_body = re.sub(r"\b([A-Za-z_]\w*):UnequipTools\(\)", r"B.UnequipTools(\1)", pm_body)
pm_body = re.sub(r"\b([A-Za-z_]\w*)\.(CharacterRemoving|CharacterAdded|Died|Unequipped|Touched):Connect\(", r'B.Signal(\1, "\2"):Connect(', pm_body)
pm_body = pm_body.replace("wall:GetClosestPointOnSurface(other.Position)", "other.Position")
pm_body = pm_body.replace("self.runtime.Parent = workspace", "self.runtime.Parent = B.district")
# Lune instances lack Destroying. Keep scope ownership for runtime teardown.
pm_body = pm_body.replace("self.scope:Own(self.runtime)", "self.scope.instances[self.runtime] = true")
pm_body = pm_body.replace("slash:Stop()", "B.StopSound(slash)")
pm_body = pm_body.replace("model:PivotTo(", "B.PivotTo(model, ")
pm_body = re.sub(r"([A-Za-z_][\w.]*):GetPivot\(\)", r"\1.WorldPivot", pm_body)
pm_prefix = (
    "local R=require('@lune/roblox')\n"
    "local CFrame,Vector3,Instance,Enum=R.CFrame,R.Vector3,R.Instance,R.Enum\n"
    "local PhysicalProperties={new=function(...) return R.PhysicalProperties.new(...) end}\n"
    "local task=require('@lune/task')\n"
    "local Config=require('./GameConfig')\n"
    "local GameData=require('./GameData')\n"
    "local Physics=require('./PhysicsConfig')\n"
    "local Painting=require('./Painting')\n"
    "local RealPaintRotation=require('./PaintRotation')\n"
    "local PaintRotation=setmetatable({Create=function() return {center=Vector3.zero,radius=1} end},{__index=RealPaintRotation})\n"
    "local CurvedSurface=require('./CurvedSurface')\n"
    "local BodyPose=require('./PaintBodyPose')\n"
    "local VisualRules=require('./VisualRules')\n"
    "local Surface=require('./PaintSurface')\n"
    "local ThrowArc=require('./ThrowArc')\n"
    "local CageGeometry=require('./CageGeometry')\n"
    "local AutomationRules=require('./AutomationRules')\n"
    "local AutoRunePattern=require('./AutoRunePattern')\n"
    "local AutomationAgents=require('./AutomationAgents')\n"
    "local PersonalRules=require('./PersonalUpgradeRules')\n"
    "local NumberExtension=require('./NumberExtension')\n"
    "local PersonalMovement=require('./PersonalMovement')\n"
    "local ModelTemplates=require('./StationModelTemplates')\n"
    "local BodyPlacementMarkers=require('./BodyPlacementMarkers')\n"
    "local Lifecycle=require('./LifecycleTool')\n"
    "local B=require('./StationPotionBoundary')\n"
    "local RaycastParams=B.RaycastParams\n"
    "local Net,workspace,Scene=B.Net,B.workspace,require('./StationScene')\n"
    "local Players,ReplicatedStorage,HttpService,RunService=B.Players,B.ReplicatedStorage,B.HttpService,B.RunService\n"
    "local NPC,Carry,Ragdoll,Ground,Door,Info=B.NPC,B.Carry,B.Ragdoll,B.Ground,B.Door,B.Info\n"
    "local CollisionGroups={Init=function() end}\n"
    "local Replication=require('./StationReplication')\n"
    "local Random={new=function() return B.Random end}\n"
)
(OUT / "StationProcessingManager.luau").write_text(pm_prefix + pm_body, encoding="utf-8")

sound_src = (shared / "GameSoundTool.luau").read_text(encoding="utf-8")
sound_body = sound_src[sound_src.index("local soundsPools:"):].replace("part.Parent = workspace", "part.Parent = B.soundRoot")
sound_prefix = (
    "local R=require('@lune/roblox')\n"
    "local Instance,CFrame,Vector3=R.Instance,R.CFrame,R.Vector3\n"
    "local B=require('./StationPotionBoundary')\n"
    "local ReplicatedStorage,SoundService=B.ReplicatedStorage,B.SoundService\n"
    "local Config=require('./GameConfig')\n"
    "local Lifecycle=require('./LifecycleTool')\n"
)
(OUT / "StationSoundTool.luau").write_text(sound_prefix + sound_body, encoding="utf-8")

client_src = (client / "ClientProcessingManager.luau").read_text(encoding="utf-8")
potions_start = client_src.index("local function StackCount(")
potions_fn = client_src.index("function Client.Potions(", potions_start)
next_local = client_src.find("\nlocal function ", potions_fn + 1)
next_method = client_src.find("\nfunction Client.", potions_fn + 1)
potions_end = min(x for x in (next_local, next_method) if x != -1)
client_parts = [client_src[potions_start:potions_end]]
for cname in ("Carried", "Held", "Update", "PlayAltarOutput", "UpdateAltar"):
    cstart = client_src.index("function Client." + cname + "(")
    cend = client_src.find("\nfunction Client.", cstart + 1)
    client_parts.append(client_src[cstart:cend])
furnace_source = (ROOT / "Scripts/ReplicatedStorage/Scripts/Client/AltarFurnaceView.luau").read_text(encoding="utf-8")
(OUT / "AltarFurnaceView.luau").write_text(
    "local R=require('@lune/roblox')\n"
    "local Instance,Color3,Vector3,CFrame,Enum=R.Instance,R.Color3,R.Vector3,R.CFrame,R.Enum\n"
    "local workspace=R.Instance.new('Folder')\n"
    "local Config=require('./GameConfig')\n" + furnace_source[furnace_source.index("local View ="):],
    encoding="utf-8",
)
client_prefix = (
    "local R=require('@lune/roblox')\n"
    "local Vector2,Vector3,Enum,CFrame=R.Vector2,R.Vector3,R.Enum,R.CFrame\n"
    "local B=require('./StationPotionBoundary')\n"
    "local Players,player,workspace,os=B.Players,B.Players.LocalPlayer,B.workspace,B.os\n"
    "local UserInputService={TouchEnabled=false}\n"
    "local Config=require('./GameConfig')\n"
    "local GameData=require('./GameData')\n"
    "local Physics=require('./PhysicsConfig')\n"
    "local Hints=require('./Hints')\n"
    "local PersonalRules=require('./PersonalUpgradeRules')\n"
    "local NumberExtension=require('./NumberExtension')\n"
    "local Net=B.Net\n"
    "local Sound=B.SoundMock\n"
    "local positions={Pool=Vector3.new(-20,2,0),Table=Vector3.new(0,2,0),Altar=Vector3.new(20,2,0),Shelf=Vector3.new(40,2,0),Sigil=Vector3.new(60,2,0)}\n"
    "local UIManager={GetTargetGuiManager=function() return {Refresh=function() end,RefreshHits=function() end} end,HasShowingWindow=function() return false end}\n"
    "local function RestoreHiddenPlayers() end\n"
    "local function SyncHiddenPlayers() end\n"
    "local Client={}\n"
    "Client.__index=Client\n"
)
(OUT / "StationClient.luau").write_text(client_prefix + "\n".join(client_parts) + "\nreturn Client\n", encoding="utf-8")
subprocess.run(["lune", "run", str(OUT / "test_station_and_potions.luau")], cwd=ROOT, check=True)
(OUT / "test_m3_automation.luau").write_text((ROOT / "Tools/Gameplay/test_m3_automation.luau").read_text(encoding="utf-8"), encoding="utf-8")
subprocess.run(["lune", "run", str(OUT / "test_m3_automation.luau")], cwd=ROOT, check=True)
(OUT / "test_m4_automation.luau").write_text((ROOT / "Tools/Gameplay/test_m4_automation.luau").read_text(encoding="utf-8"), encoding="utf-8")
subprocess.run(["lune", "run", str(OUT / "test_m4_automation.luau")], cwd=ROOT, check=True)

# World prompts use production rules/controller with only native service boundaries mocked.
subprocess.run(["python",str(ROOT/"Tools/Gameplay/test_world_interaction.py")],cwd=ROOT,check=True)
subprocess.run([sys.executable,str(ROOT/"Tools/Gameplay/test_white_presentation.py")],cwd=ROOT,check=True)
subprocess.run(["lune", "run", str(ROOT / "Tools/Gameplay/test_m2_assets.luau")], cwd=ROOT, check=True)

# Exercise FixedCamera, PaintCamera, and Scene.CameraPose.
(OUT / "FixedCameraBoundary.luau").write_text((ROOT / "Tools/Gameplay/FixedCameraBoundary.luau").read_text(encoding="utf-8"), encoding="utf-8")
fixed_cam_prefix = (
    "local B=require('./FixedCameraBoundary')\n"
    "local R=B.R\n"
    "local Instance,Vector3,CFrame,Color3,Enum,TweenInfo=R.Instance,R.Vector3,R.CFrame,R.Color3,R.Enum,B.TweenInfo\n"
    "local Players,TweenService,Workspace=B.Players,B.TweenService,B.Workspace\n"
)
(OUT / "FixedCamera.luau").write_text(fixed_cam_prefix + fixed_cam_body, encoding="utf-8")
paint_cam_src = (client / "PaintCamera.luau").read_text(encoding="utf-8")
paint_cam_body = paint_cam_src[paint_cam_src.index("local Controller = {}"):]
paint_cam_prefix = (
    "local B=require('./FixedCameraBoundary')\n"
    "local R=B.R\n"
    "local Vector3,CFrame,workspace=R.Vector3,R.CFrame,B.workspace\n"
    "local Players=B.Players\n"
    "local Config=require('./GameConfig')\n"
    "local FixedCamera=require('./FixedCamera')\n"
)
(OUT / "PaintCamera.luau").write_text(paint_cam_prefix + paint_cam_body, encoding="utf-8")
cam_scene_prefix = (
    "local R=require('@lune/roblox')\n"
    "local Instance,Vector3,CFrame,Enum=R.Instance,R.Vector3,R.CFrame,R.Enum\n"
    "local B=require('./StationPotionBoundary')\n"
    "local workspace,RaycastParams,PhysicsService=B.workspace,B.RaycastParams,B.PhysicsService\n"
    "local Physics=require('./PhysicsConfig')\n"
    "local Config=require('./GameConfig')\n"
    "local ThrowArc=require('./ThrowArc')\n"
    "local PaintRotation=require('./PaintRotation')\n"
    "local BodyPlacementMarkers=require('./BodyPlacementMarkers')\n"
    "local FixedCamera=require('./StationFixedCamera')\n"
    "local CageGeometry=require('./CageGeometry')\n"
    "local StreetZones=require('./StreetWalkZones')\n"
)
# Reuse StationPotionBoundary workspace with a CameraMarker inside RuneBodyTable for CameraPose verification.
cam_scene_setup = (
    "local _tbl = B.workspace:FindFirstChild('NeonContractDistrict'):FindFirstChild('RuneBodyTable')\n"
    "if _tbl and not _tbl:FindFirstChild('CameraMarker') then\n"
    " local _m = Instance.new('Part'); _m.Name = 'CameraMarker'; _m.Transparency = 0.5\n"
    " _m:SetAttribute('CameraMarker', true)\n"
    " _m.CFrame = CFrame.new(-16, 13, 9) * CFrame.Angles(-0.5, 0, 0); _m.Parent = _tbl\n"
    "end\n"
)
(OUT / "CameraScene.luau").write_text(cam_scene_prefix + cam_scene_setup + scene_body, encoding="utf-8")
(OUT / "test_fixed_camera.luau").write_text((ROOT / "Tools/Gameplay/test_fixed_camera.luau").read_text(encoding="utf-8"), encoding="utf-8")
subprocess.run(["lune", "run", str(OUT / "test_fixed_camera.luau")], cwd=ROOT, check=True)

# Exercise the production collision matrix and cage geometry with a mocked PhysicsService.
collision_source = (server / "CollisionGroups.luau").read_text(encoding="utf-8")
(OUT / "CollisionGroups.luau").write_text(
    "local PhysicsService=require('./CagePhysicsBoundary')\nlocal Physics=require('./PhysicsConfig')\n"
    + collision_source[collision_source.index("local CollisionGroups ="):],
    encoding="utf-8",
)
(OUT / "CagePhysicsBoundary.luau").write_text(
    "local S={registrations=0};local groups={Default=true,Custom=true};local pairsByGroup={}\n"
    "function S:IsCollisionGroupRegistered(name) return groups[name]==true end\n"
    "function S:RegisterCollisionGroup(name) assert(not groups[name]);groups[name]=true;self.registrations+=1 end\n"
    "function S:GetRegisteredCollisionGroups() local out={} for n in groups do table.insert(out,{name=n}) end return out end\n"
    "function S:CollisionGroupSetCollidable(a,b,v) assert(groups[a] and groups[b]);pairsByGroup[a]=pairsByGroup[a] or {};pairsByGroup[b]=pairsByGroup[b] or {};pairsByGroup[a][b]=v;pairsByGroup[b][a]=v end\n"
    "function S:CollisionGroupsAreCollidable(a,b) assert(groups[a] and groups[b]);return not pairsByGroup[a] or pairsByGroup[a][b]~=false end\n"
    "S:CollisionGroupSetCollidable('Default','Custom',false);return S\n",
    encoding="utf-8",
)
carry_source = (server / "Carry.luau").read_text(encoding="utf-8")
(OUT / "CageCarry.luau").write_text(
    "local R=require('@lune/roblox')\nlocal Vector3,Enum=R.Vector3,R.Enum\nlocal B=require('./CageCarryBoundary')\n"
    "local Carry,Config,Ragdoll,Scene,Players={},require('./PhysicsConfig'),B.Ragdoll,B.Scene,B.Players\n"
    "local CageGeometry=require('./CageGeometry')\n"
    "local SetOwner,BodyTorso=B.SetOwner,B.BodyTorso\n"
    "local workspace,RaycastParams=B.workspace,B.RaycastParams\n"
    + carry_source[carry_source.index("function Carry.Contain("):carry_source.index("function Carry.ReleaseIntoChute(")]
    + carry_source[carry_source.index("function Carry.AdvanceManualToss("):carry_source.index("local function AltarRestOffset(")]
    + "\nreturn Carry\n",
    encoding="utf-8",
)
(OUT / "CageCarryBoundary.luau").write_text(
    """local R=require('@lune/roblox')
local B={changes={}}
local function record(value) table.insert(B.changes,value) end
B.Ragdoll={
    SetCageContained=function(model,cage) model.cage=cage;record(cage or 'clear') end,
    SetThrowPhysics=function(_,inFlight) assert(not inFlight);record('ground physics') end,
    LimitVelocity=function() end,
}
B.BodyTorso=function(model) return model.torso end
B.SetOwner=function(_,owner) assert(owner==nil);record('server owner') end
B.Players={online={},GetPlayerByUserId=function(self,uid) return self.online[uid] end}
B.RaycastParams={new=function() return {} end}
B.workspace={Raycast=function() return nil end}
B.Scene={
    CageAt=function(pos,allowChute) if allowChute and pos.X>=0 and pos.X<10 then return 'Chute' end end,
    CageRetains=function(_,pos) return pos.X>=0 and pos.X<11 end,
    ClampToCage=function(_,pos) return R.Vector3.new(math.clamp(pos.X, 0.35, 9.65), pos.Y, pos.Z) end,
    IsSoftCageEnabled=function() return false end,
    CageFloor=function() return nil end,
    CageInset=function() return 0 end,
    ChuteLandingContains=function(pos) return pos.X>=0 and pos.X<11 end,
    PoolBasinContains=function() return false end,
}
return B
""",
    encoding="utf-8",
)
(OUT / "test_cage_physics.luau").write_bytes((ROOT / "Tools/Gameplay/test_cage_physics.luau").read_bytes())
subprocess.run(["lune", "run", str(OUT / "test_cage_physics.luau")], cwd=ROOT, check=True)
(OUT / "test_body_placement_markers.luau").write_bytes((ROOT / "Tools/Gameplay/test_body_placement_markers.luau").read_bytes())
subprocess.run(["lune", "run", str(OUT / "test_body_placement_markers.luau")], cwd=ROOT, check=True)
