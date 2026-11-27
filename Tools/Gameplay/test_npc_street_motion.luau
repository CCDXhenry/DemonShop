-- 独立运行生产假人状态机，只替换 Studio 物理、动画与时钟边界
local R = require("@lune/roblox")
local FS, Luau = require("@lune/fs"), require("@lune/luau")
local V, C = R.Vector3, R.CFrame
local scene = {Deck = {CFrame = C.identity, Size = V.new(40, 1, 12), Position = V.zero}}
local blocked, now = false, 100
function scene.IsInStreetWalkZones(position, margin)
	margin = margin or 0
	return math.abs(position.X) <= 20 + margin and math.abs(position.Z) <= 6 + margin and position.Y >= -1
end
function scene.ClampToStreetWalkZones(position)
	return V.new(math.clamp(position.X, -19, 19), 0, math.clamp(position.Z, -5, 5))
end
function scene.StreetRoute(from, target)
	if scene.IsInStreetWalkZones(target) and not (blocked and target.X > from.X) then
		return V.new(target.X, 0, target.Z)
	end
end
function scene.StreetPoint() return V.new(-10, 0, 0) end
local configSource = FS.readFile("Scripts/ReplicatedStorage/Scripts/Shared/GameConfig/init.luau")
local config = {}
for name, value in string.gmatch(configSource, "GameConfig%.(%w+)%s*=%s*([%d%.]+)") do config[name] = tonumber(value) end
local root = {Position = V.new(0, 3.2, 0), CFrame = C.new(0, 3.2, 0), AssemblyLinearVelocity = V.zero}
local humanoid = {WalkSpeed = 4.5}
function humanoid:MoveTo(point) self.target = point end
function humanoid:Move() end
local attributes = {}
local model = {PrimaryPart = root, Parent = true}
root.Parent = model
function model:FindFirstChildOfClass() return humanoid end
function model:FindFirstChild() return nil end
function model:SetAttribute(key, value) attributes[key] = value end
function model:PivotTo(pose) root.Position = pose.Position end
function model:GetPivot() return C.new(root.Position) end
local item = {model = model, location = "Street", hits = 0, hp = 30, version = 1, nextWalk = 0}
local ragdolled
local pushStep
local spawnPoints = {V.new(-10, 0, 0), V.new(0, 0, 0), V.new(10, 0, 0)}
local spawnCalls = 0
local fakeAnimator = {Parent = true}
function fakeAnimator:LoadAnimation()
	return {Play = function() end}
end
function humanoid:FindFirstChildOfClass() return fakeAnimator end
local spawnRoot = {}
local spawnModel = {PrimaryPart = spawnRoot, SetAttribute = function() end}
function spawnModel:PivotTo(pose) spawnRoot.Position = pose.Position end
function spawnModel:FindFirstChildOfClass() return humanoid end
local fakeRandom = {NextNumber = function(_, a, b) return if a then (a + b)/2 else 0.2 end}
local source = FS.readFile("Scripts/ServerStorage/Scripts/NPC.luau")
local bodyStart = assert(source:find("local NPC = {}", 1, true))
local NPC = Luau.load(source:sub(bodyStart), {environment = {
	Vector3 = V, CFrame = C, Enum = R.Enum, Instance = R.Instance, Scene = scene, Config = config,
	HttpService = {GenerateGUID = function() return "spawned" end},
	ModelTemplates = {WaitCharacter = function() return {Clone = function() return spawnModel end} end},
	Surface = {Total = function() return 1 end},
	Random = {new = function() return fakeRandom end},
	workspace = {
		GetServerTimeNow = function() return now end,
		Blockcast = function() return nil end,
		GetPartBoundsInBox = function(_, frame) return if frame.Position.X == 0 then {true} else {} end,
	},
	RunService = {PreSimulation = {Connect = function(_, callback)
		pushStep = callback
		return {Disconnect = function() pushStep = nil end}
	end}},
	RaycastParams = {new = function() return {} end},
	OverlapParams = {new = function() return {} end},
	Physics = {GroundRootEnabled = false},
	Ragdoll = {Setup = function() end, SetMode = function(_, mode) ragdolled = mode end},
	PersonalRules = {RemainingNpcHp = function(hp, _, damage) return math.max(0, hp - damage) end},
}})()

NPC.Update(item, now)
assert(item.motionState == "LookAround" and math.abs(attributes.StreetLookStarted) == now, "replicated look start")
assert(item.nextWalk - now == 2.25, "look duration")
NPC.Hit(item, -V.xAxis, 10, nil, V.new(-6, 3.2, 0))
assert(item.motionState == "Hit" and humanoid.WalkSpeed == 0 and attributes.StreetLookStarted == nil)
local originalPosition = root.Position
now += 1/60
pushStep(1/60)
assert(root.Position == originalPosition and root.AssemblyLinearVelocity.X < 0, "physical recoil uses velocity without pivoting")
now -= 1/60
NPC.Update(item, now + 0.119)
assert(item.motionState == "Hit")
NPC.Update(item, now + 0.121)
assert(item.motionState == "Fleeing" and humanoid.WalkSpeed == 15.5 and humanoid.target.X > 0, "flee away from attacker even when push points toward attacker")
blocked = true
NPC.Update(item, now + 0.5)
assert(scene.IsInStreetWalkZones(humanoid.target) and humanoid.target.X <= root.Position.X, "turn at the obstruction")
blocked = false
root.Position = V.new(10, 3.2, 0)
item.fleeHeading = V.xAxis
NPC.Update(item, now + 0.85)
assert(humanoid.target.X > root.Position.X, "keep heading when a shorter straight path fits")
now += 1
root.Position = V.new(19.8, 3.2, 0)
NPC.Hit(item, V.xAxis, 10, nil, V.new(15, 3.2, 0))
assert(item.fleeUntil == now + 4.5 and item.version == 3)
NPC.Update(item, now + 0.121)
assert(item.motionState == "Fleeing" and scene.IsInStreetWalkZones(humanoid.target), "turn at a narrow edge")
NPC.Update(item, now + 4.51)
assert(item.fleeUntil == nil and humanoid.WalkSpeed == 4.5 and item.motionState ~= "Fleeing")
root.Position = V.new(20.4, 3.2, 0)
NPC.Update(item, now + 4.52)
assert(root.Position.X > 20 and humanoid.target.X < 20, "walk back from slight drift")
root.Position = V.new(40, -10, 0)
NPC.Update(item, now + 4.53)
assert(root.Position.X < 20 and root.Position.Y > 0, "recover a fallen root")
NPC.Hit(item, -V.xAxis, 10, nil, V.new(-6, 3.2, 0))
assert(item.motionState == "Down" and item.fleeUntil == nil and ragdolled == "Loose")
function scene.StreetPoint()
	spawnCalls += 1
	return assert(spawnPoints[spawnCalls], "spawn must use only the expected candidates")
end
function scene.StreetFloor(point) return point end
config.WalkAnimation, config.NpcRunAnimation, config.IdleAnimation = "walk", "run", "idle"
local spawned = NPC.Spawn({}, {occupant = {model = {PrimaryPart = {Position = V.new(-10, 3.2, 0)}}}})
assert(spawned and spawnCalls == 3 and spawnRoot.Position == V.new(10, 3.2, 0), "spawn skips nearby item and world obstruction")
print("PASS: NPC look, stagger, source-aware flee, corner turn, hit refresh, recovery, stun and spawn overlap")
