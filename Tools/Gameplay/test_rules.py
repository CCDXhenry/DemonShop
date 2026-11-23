"""Run production coverage/save/lease rules with Lune; only service boundaries are mocked."""
from pathlib import Path
import re
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/".cache"/"ragdoll-rules"
OUT.mkdir(parents=True,exist_ok=True)
shared=ROOT/"Scripts/ReplicatedStorage/Scripts/Shared"
server=ROOT/"Scripts/ServerStorage/Scripts"
(OUT/"FoundationDateBoundary.luau").write_text((ROOT/"Tools/Gameplay/FoundationDateBoundary.luau").read_text(encoding="utf-8"),encoding="utf-8")
for name in ("GameConfig","GameTexts","GameTypes","Hints","SaveRules","PlayerProfileRules","PaintSurface","StrokePath","VisualRules","CurvedSurface","BodySurfaceData","PhysicsConfig","PaintBodyPose","PaintRotation","RuneGlyphData","RuneStampRules"):
    text=(shared/(name+".luau")).read_text(encoding="utf-8")
    for dep in ("GameConfig","GameTexts","GameTypes","Hints","SaveRules","PlayerProfileRules","PaintSurface","CurvedSurface","BodySurfaceData","PhysicsConfig","PaintBodyPose","RuneGlyphData","RuneStampRules"):
        text=text.replace("require(script.Parent."+dep+")", "require('./"+dep+"')")
    if name == "GameConfig":
        start=text.index('local replicatedStorage:')
        end=text.index('--游戏版本')
        text=text[:start]+"local D=require('./FoundationDateBoundary')\nlocal DateTimeExtension,DateTime=D.DateTimeExtension,D.DateTime\n"+text[end:]
        text="local Color3=require('@lune/roblox').Color3\nlocal game={GameId=0}\n"+text
    if name in ("PaintSurface","StrokePath","VisualRules","CurvedSurface","BodySurfaceData","PhysicsConfig","PaintBodyPose","PaintRotation","RuneStampRules"):
        text="local roblox=require('@lune/roblox')\nlocal Vector2,Vector3,CFrame,Enum=roblox.Vector2,roblox.Vector3,roblox.CFrame,roblox.Enum\n"+text
    (OUT/(name+".luau")).write_text(text,encoding="utf-8")
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
    prefix="local B=require('./AttackFeedbackBoundary')\nlocal workspace,player,Config,HitRules,Sound=B.workspace,B.player,require('./GameConfig'),require('./HitFeedbackRules'),B.Sound or {Play=function()end}\nlocal Client={}\n"
    (OUT/"AttackFeedbackClient.luau").write_text(prefix+source[start:end]+"\nreturn Client\n",encoding="utf-8")
    source=(server/"ProcessingManager.luau").read_text(encoding="utf-8")
    start=source.index("function Manager.Attack(")
    end=source.index("function Manager.Paint(",start)
    prefix="local B=require('./AttackFeedbackBoundary')\nlocal workspace,task,Net,NPC=B.workspace,B.task,B.Net,B.NPC\nlocal Config=require('./GameConfig')\nlocal Manager={}\n"
    (OUT/"AttackFeedbackServer.luau").write_text(prefix+source[start:end]+"\nreturn Manager\n",encoding="utf-8")
    text=(shared/"ProcessingNet.luau").read_text(encoding="utf-8")
    prefix="local Types=require('./GameTypes')\nlocal Surface=require('./PaintSurface')\nlocal VisualRules=require('./VisualRules')\nlocal Curve=require('./CurvedSurface')\nlocal Config=require('./GameConfig')\nlocal requestEvent,notifyEvent={},{}\nlocal BodyPose=require('./PaintBodyPose')\n"
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
text=text[:start]+"local Boundary=require('./WeaponPresentationBoundary')\nlocal Players=Boundary.Players\nlocal Instance,Enum,CFrame=Boundary.Instance,Boundary.Enum,Boundary.CFrame\nlocal Config=require('./GameConfig')\n"+text[end:]
(OUT/"CharacterPresentation.luau").write_text(text,encoding="utf-8")
for name in ("WeaponPresentationBoundary","test_weapon_presentation"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_weapon_presentation.luau")],cwd=ROOT,check=True)
text=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/ClientPreloadManager.luau").read_text(encoding="utf-8")
text=text.replace("instance:PivotTo(pose)", "B.PivotTo(instance, pose)", 1)
prefix="local B=require('./ClientPreloadBoundary')\nlocal ContentProvider,RunService,Players,ReplicatedStorage=B.ContentProvider,B.RunService,B.Players,B.ReplicatedStorage\nlocal workspace,Instance,Vector3,CFrame=B.workspace,B.Instance,B.Vector3,B.CFrame\nlocal task=require('@lune/task')\nlocal Config=require('./GameConfig')\n"
(OUT/"ClientPreloadManager.luau").write_text(prefix+text[text.index("local Manager = {}"):],encoding="utf-8")
for name in ("ClientPreloadBoundary","test_client_preload"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_client_preload.luau")],cwd=ROOT,check=True)

subprocess.run(["lune","run",str(OUT/"test_painting.luau")],cwd=ROOT,check=True)

# Exercise the complete production request dispatcher with real painting rules.
source=(server/"ProcessingManager.luau").read_text(encoding="utf-8")
prefix="local CFrame=require('@lune/roblox').CFrame\nlocal Config=require('./GameConfig')\nlocal Painting=require('./Painting')\nlocal PaintRotation=require('./PaintRotation')\nlocal B=require('./PaintRequestBoundary')\nlocal Net,workspace,Scene=B.Net,B.workspace,B.Scene\nlocal Random={new=function() return {} end}\n"
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
prefix="""local R=require('@lune/roblox')
local Instance,Vector3=R.Instance,R.Vector3
local B=require('./test_potion_shelf').Boundary
local ReplicatedStorage,workspace=B.ReplicatedStorage,B.workspace
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
text="local Roblox=require('@lune/roblox')\nlocal Vector2,UDim2=Roblox.Vector2,Roblox.UDim2\nlocal Boundary=require('./StrokeViewBoundary')\nlocal Players,ReplicatedStorage=Boundary.Players,Boundary.ReplicatedStorage\nlocal Config=require('./GameConfig')\nlocal Types=require('./GameTypes')\nlocal Surface=require('./PaintSurface')\nlocal Curve=require('./CurvedSurface')\nlocal RuneRules=require('./RuneStampRules')\nlocal CurvedView={}\nlocal UIManager=require('./PaintUIBoundary')\n"+text[start:]
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
(OUT/"PaintView.luau").write_text((OUT/"PaintView.luau").read_text(encoding="utf-8").replace("local CurvedView={}", "local CurvedView={new=function() return {Bind=function() end,Apply=function() end,Remove=function() end,Destroy=function() end} end}"),encoding="utf-8")
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
    "local UIManager={GetTargetGuiManager=function() return {Refresh=function() end} end,HasShowingWindow=function() return false end}\n"
    "local AltarSacrifice={new=function() return {Update=function() return nil end,Clear=function() end} end}\n"
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
    foundation_module(name, "Scripts/ReplicatedStorage/Scripts/Client/UIManager/"+name+".luau", "local Manager =", "local R=require('@lune/roblox')\nlocal UDim2,Vector2,Enum=R.UDim2,R.Vector2,R.Enum\nlocal U=require('./FoundationUIBoundary')\nlocal Players,ReplicatedStorage,workspace,UserInputService,GuiService=U.Players,{UI=U.templates},U.workspace,U.UserInputService,U.GuiService\nlocal TweenService,TweenInfo=U.TweenService,U.TweenInfo\nlocal ProcessingText=require('./ProcessingTextTool')\nlocal Lifecycle=require('./LifecycleTool')\nlocal Config=require('./GameConfig')\nlocal PaintPointer=U.PaintPointer\n")
source=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/UIManager/init.luau").read_text(encoding="utf-8")
start=source.index("local ModalTransparency:")
prefix="local U=require('./FoundationUIBoundary')\nlocal UIManager={}\nlocal LifecycleTool=require('./LifecycleTool')\nlocal scope=LifecycleTool.new()\nlocal initialized=false\nlocal buttonScopes={}\nlocal uiTemplatesFolder=U.templates\nlocal ClientMsg,TextFitting,GameSoundTool=U.ClientMsg,U.TextFitting,U.Sound\nlocal tweenService,workspace,Enum,TweenInfo=U.TweenService,U.workspace,U.Enum,U.TweenInfo\nlocal userInputService={PreferredInput=Enum.PreferredInput.KeyboardAndMouse}\nlocal windowOrder={}\nlocal viewportScope=nil\nlocal ownedGui=nil\nlocal hudWrapper=nil\nlocal Players=U.Players\nlocal GameFrameWrapper=require('./GameFrameWrapper')\n"
prefix+="local screenManager=require('./GameScreenGuiManager').new()\nlocal targetManager=require('./TargetGuiManager').new()\nlocal faceManager=require('./PaintFaceGuiManager').new()\nlocal cellManager=require('./PaintCellFrameManager').new()\nlocal guideManager=require('./ScreenLayoutGuideFrameManager').new()\n"
(OUT/"UIManager.luau").write_text(prefix+source[start:],encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_foundation_ui.luau")],cwd=ROOT,check=True)
(OUT/"test_ui_template_managers.luau").write_text((ROOT/"Tools/Gameplay/test_ui_template_managers.luau").read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_ui_template_managers.luau")],cwd=ROOT,check=True)


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
foundation_module("ServerPlayerChatCommandManager", "Scripts/ServerStorage/Scripts/ServerGameManager/ServerPlayerChatCommandManager.luau", "local Manager =", "local C=require('./ChatBoundary')\nlocal Players,RunService,TextChatService,TeleportService,Config,GMConfig,Instance=C.Players,C.RunService,C.TextChatService,C.TeleportService,C.Config,C.GMConfig,C.Instance\nlocal Lifecycle=require('./LifecycleTool')\n")
subprocess.run(["lune","run",str(OUT/"test_foundation_chat.luau")],cwd=ROOT,check=True)


run_hit_feedback_tests()

# Exercise station prompt distances, toolbar potion isolation, respawn rescue, and looped audio with production modules.
for name in ("StationPotionBoundary", "test_station_and_potions"):
    (OUT / (name + ".luau")).write_text((ROOT / "Tools/Gameplay" / (name + ".luau")).read_text(encoding="utf-8"), encoding="utf-8")

scene_src = (server / "Scene.luau").read_text(encoding="utf-8")
scene_body = scene_src[scene_src.index("local Scene = {}"):].replace(":WaitForChild(", ":FindFirstChild(")
scene_prefix = (
    "local R=require('@lune/roblox')\n"
    "local Instance,Vector3,CFrame,Enum=R.Instance,R.Vector3,R.CFrame,R.Enum\n"
    "local B=require('./StationPotionBoundary')\n"
    "local workspace,RaycastParams,PhysicsService=B.workspace,B.RaycastParams,B.PhysicsService\n"
    "local Physics=require('./PhysicsConfig')\n"
    "local Config=require('./GameConfig')\n"
    "local PaintRotation=require('./PaintRotation')\n"
)
(OUT / "StationScene.luau").write_text(scene_prefix + scene_body, encoding="utf-8")
(OUT / "StationSceneFallback.luau").write_text(scene_prefix + scene_body, encoding="utf-8")

rep_src = (server / "Replication.luau").read_text(encoding="utf-8")
(OUT / "StationReplication.luau").write_text(
    "local Types=require('./GameTypes')\nlocal Net=require('./StationPotionBoundary').Net\n" + rep_src[rep_src.index("local Replication ="):],
    encoding="utf-8",
)

pm_src = (server / "ProcessingManager.luau").read_text(encoding="utf-8")
pm_body = pm_src[pm_src.index("type PlayerData ="):]
pm_body = re.sub(r"\b([A-Za-z_]\w*):WaitForChild\(", r"B.WaitForChild(\1, ", pm_body)
pm_body = re.sub(r"\b([A-Za-z_]\w*):EquipTool\(", r"B.EquipTool(\1, ", pm_body)
pm_body = re.sub(r"\b([A-Za-z_]\w*):UnequipTools\(\)", r"B.UnequipTools(\1)", pm_body)
pm_body = re.sub(r"\b([A-Za-z_]\w*)\.(CharacterRemoving|CharacterAdded|Died|Unequipped):Connect\(", r'B.Signal(\1, "\2"):Connect(', pm_body)
pm_body = pm_body.replace("slash:Stop()", "B.StopSound(slash)")
pm_prefix = (
    "local R=require('@lune/roblox')\n"
    "local CFrame,Vector3,Instance,Enum=R.CFrame,R.Vector3,R.Instance,R.Enum\n"
    "local task=require('@lune/task')\n"
    "local Config=require('./GameConfig')\n"
    "local Physics=require('./PhysicsConfig')\n"
    "local Painting=require('./Painting')\n"
    "local RealPaintRotation=require('./PaintRotation')\n"
    "local PaintRotation=setmetatable({Create=function() return {center=Vector3.zero,radius=1} end},{__index=RealPaintRotation})\n"
    "local CurvedSurface=require('./CurvedSurface')\n"
    "local BodyPose=require('./PaintBodyPose')\n"
    "local VisualRules=require('./VisualRules')\n"
    "local Lifecycle=require('./LifecycleTool')\n"
    "local B=require('./StationPotionBoundary')\n"
    "local Net,workspace,Scene=B.Net,B.workspace,require('./StationScene')\n"
    "local Players,ReplicatedStorage,HttpService,RunService=B.Players,B.ReplicatedStorage,B.HttpService,B.RunService\n"
    "local NPC,Carry,Ragdoll,Ground,Door,Info=B.NPC,B.Carry,B.Ragdoll,B.Ground,B.Door,B.Info\n"
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
for cname in ("Carried", "Held", "Update", "UpdateAltar"):
    cstart = client_src.index("function Client." + cname + "(")
    cend = client_src.find("\nfunction Client.", cstart + 1)
    client_parts.append(client_src[cstart:cend])
client_prefix = (
    "local R=require('@lune/roblox')\n"
    "local Vector2,Vector3,Enum,CFrame=R.Vector2,R.Vector3,R.Enum,R.CFrame\n"
    "local B=require('./StationPotionBoundary')\n"
    "local Players,player,workspace,os=B.Players,B.Players.LocalPlayer,B.workspace,B.os\n"
    "local UserInputService={TouchEnabled=false}\n"
    "local Config=require('./GameConfig')\n"
    "local Physics=require('./PhysicsConfig')\n"
    "local Hints=require('./Hints')\n"
    "local Net=B.Net\n"
    "local Sound=B.SoundMock\n"
    "local positions={Pool=Vector3.new(-20,2,0),Table=Vector3.new(0,2,0),Altar=Vector3.new(20,2,0),Shelf=Vector3.new(40,2,0),Sigil=Vector3.new(60,2,0)}\n"
    "local UIManager={GetTargetGuiManager=function() return {Refresh=function() end} end,HasShowingWindow=function() return false end}\n"
    "local AltarSacrifice={new=function() return {Update=function() return nil end,Clear=function() end} end}\n"
    "local function RestoreHiddenPlayers() end\n"
    "local function SyncHiddenPlayers() end\n"
    "local Client={}\n"
    "Client.__index=Client\n"
)
(OUT / "StationClient.luau").write_text(client_prefix + "\n".join(client_parts) + "\nreturn Client\n", encoding="utf-8")
subprocess.run(["lune", "run", str(OUT / "test_station_and_potions.luau")], cwd=ROOT, check=True)

# World prompts use production rules/controller with only native service boundaries mocked.
subprocess.run(["python",str(ROOT/"Tools/Gameplay/test_world_interaction.py")],cwd=ROOT,check=True)
subprocess.run([sys.executable,str(ROOT/"Tools/Gameplay/test_white_presentation.py")],cwd=ROOT,check=True)
