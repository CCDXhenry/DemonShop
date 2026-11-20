"""Run the presentation lifecycle on the exported WhiteR15 with Lune service/signal boundaries."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / ".cache" / "white-presentation-tests"
CLIENT = ROOT / "Scripts/ReplicatedStorage/Scripts/Client"
SHARED = CLIENT.parent / "Shared"
OUT.mkdir(parents=True, exist_ok=True)


def module(name, path, start, prefix, replacements=()):
    source = (path / (name + ".luau")).read_text(encoding="utf-8")
    source = prefix + "\n" + source[source.index(start):]
    for before, after in replacements:
        assert before in source, before
        source = source.replace(before, after)
    (OUT / (name + ".luau")).write_text(source, encoding="utf-8")


roblox = "local R=require('@lune/roblox')\nlocal Vector3,CFrame,Instance=R.Vector3,R.CFrame,R.Instance"
module("PhysicsConfig", SHARED, "export type Joint", roblox)
module("JointAdapter", CLIENT, "local Adapter =", "local Physics=require('./PhysicsConfig')")
module("PresentationTuning", CLIENT, "local Tuning =", "local Physics=require('./PhysicsConfig')\nlocal RunService=require('./Boundary').run")
for name,marker,dependencies in (
    ("Spring","local Spring =",()),
    ("LocalRagdoll","local Fall =",("Spring","PhysicsConfig","JointAdapter")),
    ("SoftContact","local Contact =",("Spring",)),
    ("ImpactReaction","local Impact =",("Spring",)),
    ("PoseMixer","local Mixer =",("Spring","JointAdapter")),
):
    aliases={"JointAdapter":"Adapter","PhysicsConfig":"Physics"}
    imports="\n".join(f"local {aliases.get(dep, dep)}=require('./{dep}')" for dep in dependencies)
    if name == "ImpactReaction":
        imports += "\nlocal GameConfig={StunHits=3}"
    module(name,CLIENT,marker,roblox+"\n"+imports)
module("WhiteBodyPresentationManager", CLIENT, "local Manager =", """
local B=require('./Boundary')
local workspace,RunService=B.world,B.run
local Adapter=require('./JointAdapter')
local Tuning=require('./PresentationTuning')
local Impact=require('./ImpactReaction')
local Mixer=require('./PoseMixer')
local Contact=require('./SoftContact')
local Fall=require('./LocalRagdoll')
local Physics=require('./PhysicsConfig')
local Input={TouchEnabled=false}
local Players={LocalPlayer=nil,GetPlayers=function() return {} end}
local Vector3=require('@lune/roblox').Vector3
local GameConfig={StunHits=3,HitPredictionLifetime=2}
""", [
    ("workspace:GetServerTimeNow()", '0'),
    ("local camera=workspace.CurrentCamera", 'local camera=B.camera'),
    ("source.DescendantAdded", 'B.signal(source,"added")'),
    ("source.DescendantRemoving", 'B.signal(source,"removing")'),
    ('source:GetPropertyChangedSignal("PrimaryPart")', 'B.signal(source,"root")'),
])
(OUT / "Boundary.luau").write_text("""
local R=require('@lune/roblox')
local B={world=R.Instance.new('Folder'),run={IsStudio=function() return true end,IsClient=function() return true end}}
B.signals={}
function B.signal(source,key)
    local signals=B.signals[source] or {}
    B.signals[source]=signals
    if not signals[key] then
        signals[key]={Connect=function(self,callback)
            self.last=callback
            return {Connected=true,Disconnect=function(c) c.Connected=false end}
        end}
    end
    return signals[key]
end
return B
""", encoding="utf-8")
module("HitFeedbackRules", SHARED, "local Rules =", "")
source=(CLIENT/"ClientProcessingManager.luau").read_text(encoding="utf-8")
methods=source[source.index("function Client.OnHit("):source.index("function Client.RequestPaintEnd(")]
(OUT/"FeedbackClient.luau").write_text("""
local CFrame=require('@lune/roblox').CFrame
local Client={}
local player={UserId=1}
local HitRules=require('./HitFeedbackRules')
local Config={StunHits=3,HitSecondPoseSeconds=0.45,HitEffectSeconds=0.12,HitFinalEffectSeconds=0.18}
local workspace={GetServerTimeNow=function() return 0.04 end}
local CFrame=require('@lune/roblox').CFrame
"""+methods+"\nreturn Client",encoding="utf-8")
test = (ROOT / "Tools/Gameplay/test_white_presentation.luau").read_text(encoding="utf-8")
(OUT / "test.luau").write_text(test, encoding="utf-8")
subprocess.run(["lune", "run", str(OUT / "test.luau")], cwd=ROOT, check=True)

server = ROOT / "Scripts/ServerStorage/Scripts"
module("Carry", server, "local Carry = {}", roblox + """
local B=require('./Boundary')
local workspace={GetServerTimeNow=function() return B.now end}
local Vector2=R.Vector2
local Random={new=function() return {} end}
local Config=require('./PhysicsConfig')
local NPC={StopMotion=function() end}
local Scene=require('./AltarScene')
local function GetPivot(model)
    return model.PrimaryPart.CFrame
end
local function PivotTo(model, frame)
    local from=GetPivot(model)
    for _,part in model:GetDescendants() do
        if part:IsA("BasePart") then part.CFrame=frame*from:ToObjectSpace(part.CFrame) end
    end
end
local Ragdoll={SetMode=function(model,mode,owner)
    model:SetAttribute("PhysicsMode",mode)
    if mode == "Loose" then
        B.altarOwner=owner
        for _,part in model:GetChildren() do
            if part:IsA("BasePart") then
                part.Anchored=false
                part.CanCollide=part.Name~="HumanoidRootPart"
            end
        end
    end
end}
""", [
    ("humanoid:UnequipTools()", "B.unequip(humanoid)"),
    ("support.AssemblyLinearVelocity", "Vector3.zero"),
    ("torso.AssemblyMass", "1"),
    ("item.model:GetPivot()", "GetPivot(item.model)"),
    ("model:GetPivot()", "GetPivot(model)"),
    ("item.model:PivotTo(", "PivotTo(item.model, "),
    ("model:PivotTo(", "PivotTo(model, "),
    ("then torso.Position else GetPivot(model)", "then torso.CFrame.Position else GetPivot(model)"),
])
scene = (server / "Scene.luau").read_text(encoding="utf-8")
pile_pose = scene[scene.index("local function Unit("):scene.index("function Scene.TablePose(")]
pile_pose += scene[scene.index("function Scene.AltarPilePose("):scene.index("function Scene.PoolPose(")]
(OUT / "AltarScene.luau").write_text(roblox + """
local bed=Instance.new("Part")
bed.Size=Vector3.new(9,.5,5)
bed.CFrame=CFrame.new(-12,1.25,-9)
local Scene={AltarRest=bed}
local Config={PaintLiePitch=math.pi/2,AltarPileSpread=1.2,AltarPilePitch=.2,AltarPileStep=.55}
""" + pile_pose + "\nreturn Scene", encoding="utf-8")
processing = (server / "ProcessingManager.luau").read_text(encoding="utf-8")
update = processing[processing.index("function Manager.Update("):processing.index("function Manager.Close(")]
(OUT / "AltarProcessing.luau").write_text("""
local B=require('./Boundary')
local workspace=B.world
local Carry=require('./Carry')
local Config={ConversionSeconds=5}
local Manager={}
""" + update.replace("workspace:GetServerTimeNow()", "B.now") + "\nreturn Manager", encoding="utf-8")
for name in ("test_carry_stack", "test_altar_toss"):
    test = (ROOT / "Tools/Gameplay" / f"{name}.luau").read_text(encoding="utf-8")
    (OUT / f"{name}.luau").write_text(test, encoding="utf-8")
    subprocess.run(["lune", "run", str(OUT / f"{name}.luau")], cwd=ROOT, check=True)
