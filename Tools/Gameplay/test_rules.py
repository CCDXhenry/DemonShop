"""Run production coverage/save/lease rules with Lune; only service boundaries are mocked."""
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/".cache"/"ragdoll-rules"
OUT.mkdir(parents=True,exist_ok=True)
shared=ROOT/"Scripts/ReplicatedStorage/Scripts/Shared"
server=ROOT/"Scripts/ServerStorage/Scripts"
(OUT/"FoundationDateBoundary.luau").write_text((ROOT/"Tools/Gameplay/FoundationDateBoundary.luau").read_text(encoding="utf-8"),encoding="utf-8")
for name in ("GameConfig","GameTexts","GameTypes","SaveRules","PlayerProfileRules","PaintSurface","StrokePath","VisualRules","CurvedSurface","BodySurfaceData","PhysicsConfig","PaintBodyPose"):
    text=(shared/(name+".luau")).read_text(encoding="utf-8")
    for dep in ("GameConfig","GameTexts","GameTypes","SaveRules","PlayerProfileRules","PaintSurface","CurvedSurface","BodySurfaceData","PhysicsConfig","PaintBodyPose"):
        text=text.replace("require(script.Parent."+dep+")", "require('./"+dep+"')")
    if name == "GameConfig":
        start=text.index('local replicatedStorage:')
        end=text.index('--游戏版本')
        text=text[:start]+"local D=require('./FoundationDateBoundary')\nlocal DateTimeExtension,DateTime=D.DateTimeExtension,D.DateTime\n"+text[end:]
        text="local game={GameId=0}\n"+text
    if name in ("PaintSurface","StrokePath","VisualRules","CurvedSurface","BodySurfaceData","PhysicsConfig","PaintBodyPose"):
        text="local roblox=require('@lune/roblox')\nlocal Vector2,Vector3,CFrame,Enum=roblox.Vector2,roblox.Vector3,roblox.CFrame,roblox.Enum\n"+text
    (OUT/(name+".luau")).write_text(text,encoding="utf-8")
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
text="local roblox=require('@lune/roblox')\nlocal Vector2,CFrame=roblox.Vector2,roblox.CFrame\nlocal Enum=roblox.Enum\nlocal RaycastParams={new=function() return {} end}\nlocal workspace=require('./PaintingWorld')\nlocal Config=require('./GameConfig')\nlocal Types=require('./GameTypes')\nlocal Surface=require('./PaintSurface')\nlocal Curve=require('./CurvedSurface')\nlocal BodyPose=require('./PaintBodyPose')\n"+text[end:]
(OUT/"Painting.luau").write_text(text,encoding="utf-8")
for name in ("PaintingWorld","test_painting"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
for name in ("Mock","test_rules"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_rules.luau")],cwd=ROOT,check=True)

text=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/CharacterPresentation.luau").read_text(encoding="utf-8")
start=text.index("local Players =")
end=text.index("local Presentation =")
text=text[:start]+"local Boundary=require('./WeaponPresentationBoundary')\nlocal Players,ContentProvider=Boundary.Players,Boundary.ContentProvider\nlocal Instance,Enum,CFrame=Boundary.Instance,Boundary.Enum,Boundary.CFrame\nlocal task=require('@lune/task')\nlocal Config=require('./GameConfig')\n"+text[end:]
(OUT/"CharacterPresentation.luau").write_text(text,encoding="utf-8")
for name in ("WeaponPresentationBoundary","test_weapon_presentation"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_weapon_presentation.luau")],cwd=ROOT,check=True)

subprocess.run(["lune","run",str(OUT/"test_painting.luau")],cwd=ROOT,check=True)

text=(server/"Replication.luau").read_text(encoding="utf-8")
start=text.index('local ReplicatedStorage =')
end=text.index('local Replication =')
text="local Types=require('./GameTypes')\nlocal Net=require('./ReplicationNet')\n"+text[end:]
(OUT/"Replication.luau").write_text(text,encoding="utf-8")
for name in ("ReplicationNet","test_replication"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_replication.luau")],cwd=ROOT,check=True)
(OUT/"test_stroke_path.luau").write_text((ROOT/"Tools/Gameplay/test_stroke_path.luau").read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_stroke_path.luau")],cwd=ROOT,check=True)
# Execute extracted UI managers with real Lune GUI instances; each simulated client owns a pair.
for name in ("PaintFaceGuiManager", "PaintCellFrameManager"):
    source=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/UIManager"/(name+".luau")).read_text(encoding="utf-8")
    prefix="local R=require('@lune/roblox')\nlocal Vector2,UDim2=R.Vector2,R.UDim2\nlocal B=require('./StrokeViewBoundary')\nlocal Players,ReplicatedStorage=B.Players,B.ReplicatedStorage\nlocal Config=require('./GameConfig')\n"
    (OUT/(name+".luau")).write_text(prefix+source[source.index('local Manager ='):],encoding="utf-8")
(OUT/"PaintUIBoundary.luau").write_text("local F=require('./PaintFaceGuiManager')\nlocal C=require('./PaintCellFrameManager')\nreturn {GetPaintFaceGuiManager=function() return F.new() end,GetPaintCellFrameManager=function() return C.new() end}\n",encoding="utf-8")
text=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/PaintView.luau").read_text(encoding="utf-8")
start=text.index('local View =')
text="local Roblox=require('@lune/roblox')\nlocal Vector2,UDim2=Roblox.Vector2,Roblox.UDim2\nlocal Boundary=require('./StrokeViewBoundary')\nlocal Players,ReplicatedStorage=Boundary.Players,Boundary.ReplicatedStorage\nlocal Config=require('./GameConfig')\nlocal Types=require('./GameTypes')\nlocal Surface=require('./PaintSurface')\nlocal Path=require('./StrokePath')\nlocal Curve=require('./CurvedSurface')\nlocal CurvedView={}\nlocal UIManager=require('./PaintUIBoundary')\n"+text[start:]
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
start=text.index('local View=')
text="local R=require('@lune/roblox')\nlocal Vector2=R.Vector2\nlocal B=require('./CurvedRasterBoundary')\nlocal AssetService,Content,workspace,os=B.AssetService,B.Content,B.workspace,B.os\nlocal Curve=require('./CurvedSurface')\nlocal Data=require('./BodySurfaceData')\nlocal Config=require('./GameConfig')\nlocal Types=require('./GameTypes')\n"+text[start:]
(OUT/"CurvedPaintView.luau").write_text(text,encoding="utf-8")
for name in ("CurvedRasterBoundary","CurvedRasterReference","test_curved_raster"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
subprocess.run(["lune","run",str(OUT/"test_curved_raster.luau")],cwd=ROOT,check=True)

# Exercise production client lifecycle methods with input/camera/network boundaries.
source=(ROOT/"Scripts/ReplicatedStorage/Scripts/Client/ClientProcessingManager.luau").read_text(encoding="utf-8")
methods=[]
for name in ("ExitView","RequestPaintEnd","Update","OnInput","OnMove","OnRelease","ResetPaintView"):
    start=source.index("function Client."+name+"(")
    end=source.find("\nfunction Client.",start+1)
    methods.append(source[start:end])
prefix="local R=require('@lune/roblox')\nlocal Vector2,Vector3,Enum=R.Vector2,R.Vector3,R.Enum\nlocal B=require('./PaintClientBoundary')\nlocal player,workspace,os,UserInputService=B.player,B.workspace,B.os,B.UserInputService\nlocal Config=require('./GameConfig')\nlocal Net=require('./VisualNet')\nlocal Client={}\nClient.__index=Client\n"
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
foundation_module("ClientGameManager", "Scripts/ReplicatedStorage/Scripts/Client/ClientGameManager.luau", "local Manager =", "local B=require('./FoundationBoundary')\nlocal Players=B.Players\nlocal StarterGui,Enum=B.StarterGui,B.Enum\nlocal Config=require('./GameConfig')\nlocal RunService,Net,Sound,UIManager,Processing=B.RunService,B.Net,B.Sound,B.UI,B.ClientProcessing\nlocal Lifecycle=require('./LifecycleTool')\nlocal SaveRules=require('./SaveRules')\nlocal Info=require('./ClientGameInfo')\n")
foundation_module("PlayerSaveInfoVersionUpdateTool", "Scripts/ServerStorage/Scripts/PlayerSaveInfoVersionUpdateTool/init.luau", "local Tool =", "local Config=require('./GameConfig')\nlocal Rules=require('./SaveRules')\n")
subprocess.run(["lune","run",str(OUT/"test_foundation.luau")],cwd=ROOT,check=True)

foundation_module("GuiWrapperBase", "Scripts/ReplicatedStorage/Scripts/Client/UIManager/GuiWrapperBase.luau", "local GuiWrapperBase =", "local LifecycleTool=require('./LifecycleTool')\n")
foundation_module("GameFrameWrapper", "Scripts/ReplicatedStorage/Scripts/Client/UIManager/GameFrameWrapper.luau", "local Wrapper =", "local U=require('./FoundationUIBoundary')\nlocal workspace=U.workspace\nlocal GuiWrapperBase=require('./GuiWrapperBase')\nlocal Lifecycle=require('./LifecycleTool')\n")
for name in ("FoundationUIBoundary", "test_foundation_ui"):
    (OUT/(name+".luau")).write_text((ROOT/"Tools/Gameplay"/(name+".luau")).read_text(encoding="utf-8"),encoding="utf-8")
foundation_module("ProcessingTextTool", "Scripts/ReplicatedStorage/Scripts/Client/ProcessingTextTool.luau", "local Tool =", "local U=require('./FoundationUIBoundary')\nlocal GameTexts=require('./GameTexts')\nlocal TranslationTool,TextFitting=U.TranslationTool,U.TextFitting\n")
for name in ("GameScreenGuiManager", "TargetGuiManager", "ScreenLayoutGuideFrameManager"):
    foundation_module(name, "Scripts/ReplicatedStorage/Scripts/Client/UIManager/"+name+".luau", "local Manager =", "local R=require('@lune/roblox')\nlocal UDim2=R.UDim2\nlocal U=require('./FoundationUIBoundary')\nlocal Players,ReplicatedStorage,workspace,UserInputService=U.Players,{UI=U.templates},U.workspace,U.UserInputService\nlocal ProcessingText=require('./ProcessingTextTool')\nlocal Lifecycle=require('./LifecycleTool')\nlocal Config=require('./GameConfig')\nlocal PaintPointer=U.PaintPointer\n")
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
