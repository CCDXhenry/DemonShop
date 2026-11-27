-- 仿真验证生产 StreetCrowd + NPC + 真实 Core/RVO 在 18 名白膜、POI 驻足、受惊扩散与避障下的表现
local R = require("@lune/roblox")
local FS = require("@lune/fs")
local Luau = require("@lune/luau")
local V, C = R.Vector3, R.CFrame

local function loadCoreRvo()
	local dir = "Scripts/ReplicatedStorage/Core/Scripts/Shared/RVO/"
	local astarMath = Luau.load(FS.readFile(dir .. "AstarMath.luau"), { environment = { Vector3 = V } })()
	local rvoObstacle = Luau.load(FS.readFile(dir .. "RVOObstacle.luau"), {
		environment = {
			script = { Parent = { FindFirstChild = function(_, n) return n == "AstarMath" and true or nil end } },
			require = function() return astarMath end,
		},
	})()
	local agentEnv = {
		bit32 = bit32,
		script = { Parent = { FindFirstChild = function(_, n) return n end } },
		require = function(name)
			if name == "RVOObstacle" then return rvoObstacle end
			if name == "AstarMath" then return astarMath end
			error("unexpected require in RVOAgent: " .. tostring(name))
		end,
	}
	local rvoAgent = Luau.load(FS.readFile(dir .. "RVOAgent.luau"), { environment = agentEnv })()
	local quadtreeEnv = {
		script = { Parent = { FindFirstChild = function(_, n) return n end } },
		require = function(name)
			if name == "AstarMath" then return astarMath end
			if name == "RVOAgent" then return rvoAgent end
			error("unexpected require in RVOQuadtree: " .. tostring(name))
		end,
	}
	local rvoQuadtree = Luau.load(FS.readFile(dir .. "RVOQuadtree.luau"), { environment = quadtreeEnv })()
	local simEnv = {
		bit32 = bit32,
		Vector3 = V,
		script = { Parent = { FindFirstChild = function(_, n) return n end } },
		require = function(name)
			if name == "RVOAgent" then return rvoAgent end
			if name == "RVOObstacle" then return rvoObstacle end
			if name == "RVOQuadtree" then return rvoQuadtree end
			if name == "AstarMath" then return astarMath end
			error("unexpected require in RVOSimulator: " .. tostring(name))
		end,
	}
	local rvoSimulator = Luau.load(FS.readFile(dir .. "RVOSimulator.luau"), { environment = simEnv })()
	local initEnv = {
		script = { FindFirstChild = function(_, n) return n end },
		require = function(name)
			if name == "RVOAgent" then return rvoAgent end
			if name == "RVOObstacle" then return rvoObstacle end
			if name == "RVOSimulator" then return rvoSimulator end
			if name == "RVOQuadtree" then return rvoQuadtree end
			if name == "AstarMath" then return astarMath end
			error("unexpected require in RVO init: " .. tostring(name))
		end,
	}
	return Luau.load(FS.readFile(dir .. "init.luau"), { environment = initEnv })()
end

local RealRVO = loadCoreRvo()
local Zones = Luau.load(FS.readFile("Scripts/ServerStorage/Scripts/StreetWalkZones.luau"), { environment = { Vector3 = V } })()
local streetZones = {
	Zones.New(C.new(-74, 20.08, -67), V.new(12, 0.25, 14)),
	Zones.New(C.new(6, 20.08, -67.4), V.new(148, 0.25, 35.2)),
}
local pois = {
	{ id = "POI_N1", position = V.new(-62, 20.08, -82.5), lookDirection = V.new(0, 0, -1) },
	{ id = "POI_N2", position = V.new(-24, 20.08, -82.5), lookDirection = V.new(0, 0, -1) },
	{ id = "POI_N3", position = V.new(17, 20.08, -82.5), lookDirection = V.new(0, 0, -1) },
	{ id = "POI_N4", position = V.new(62.5, 20.08, -82.5), lookDirection = V.new(0, 0, -1) },
	{ id = "POI_S1", position = V.new(-36.4, 20.08, -52.3), lookDirection = V.new(0, 0, 1) },
	{ id = "POI_S2", position = V.new(-9.3, 20.08, -52.3), lookDirection = V.new(0, 0, 1) },
	{ id = "POI_S3", position = V.new(36, 20.08, -52.3), lookDirection = V.new(0, 0, 1) },
	{ id = "POI_S4", position = V.new(76.5, 20.08, -52.3), lookDirection = V.new(0, 0, 1) },
}

local Scene = { Deck = { CFrame = C.new(0, 20.08, -67.4), Size = V.new(160, 1, 35) } }
function Scene.IsInStreetWalkZones(pos, margin) return Zones.Contains(streetZones, pos, margin) end
function Scene.ClampToStreetWalkZones(pos) return Zones.Closest(streetZones, pos, 1.25) end
function Scene.StreetFloor(pos) return V.new(pos.X, 20.08, pos.Z) end
function Scene.StreetPoint(rng) return assert(Zones.Sample(streetZones, rng)) end
function Scene.StreetRoute(from, target, recovering)
	local floor = V.new(target.X, 20.08, target.Z)
	if not Scene.IsInStreetWalkZones(floor) then return nil end
	if not recovering and not Zones.CoversSegment(streetZones, from, floor) then return nil end
	return floor
end
function Scene.StreetBoundaryPush(pos, margin) return Zones.BoundaryPush(streetZones, pos, margin or 1.4) end
function Scene.GetStreetInterestPoints() return pois end

local configSource = FS.readFile("Scripts/ReplicatedStorage/Scripts/Shared/GameConfig/init.luau")
local Config = {}
for name, value in string.gmatch(configSource, "GameConfig%.(%w+)%s*=%s*([%-%d%.]+)") do
	local num = tonumber(value)
	if num then Config[name] = num end
end
Config.WalkAnimation = ""
Config.NpcRunAnimation = ""
Config.IdleAnimation = ""

local function makeRandom(seed)
	local state = seed or 12345
	local rng = {}
	function rng:NextNumber(minVal, maxVal)
		state = (state * 1103515245 + 12345) % 2147483648
		local u = state / 2147483648
		if minVal ~= nil and maxVal ~= nil then
			return minVal + (maxVal - minVal) * u
		end
		return u
	end
	return rng
end
local FakeRandom = {
	_seed = 42,
	new = function()
		return makeRandom(42)
	end,
}

local crowdSrc = FS.readFile("Scripts/ServerStorage/Scripts/StreetCrowd.luau")
local crowdStart = assert(crowdSrc:find("local StreetCrowd = {}", 1, true))
local StreetCrowd = Luau.load(crowdSrc:sub(crowdStart), {
	environment = {
		Vector3 = V, CFrame = C, Random = FakeRandom, Config = Config, RVO = RealRVO, Scene = Scene,
	},
})()

local now = 100.0
local guidSeq = 0
local function createBodyModel()
	guidSeq += 1
	local root = {
		Position = V.zero,
		CFrame = C.identity,
		AssemblyLinearVelocity = V.zero,
		CollisionGroup = "WalkingStreetBodies",
		IsA = function(_, cls) return cls == "BasePart" end,
	}
	local humanoid = { WalkSpeed = Config.NpcStrollSpeed, target = V.zero }
	function humanoid:MoveTo(point) self.target = point end
	function humanoid:FindFirstChildOfClass() return { Parent = true, LoadAnimation = function() return { Play = function() end, Stop = function() end, AdjustSpeed = function() end } end } end
	local attrs = {}
	local model = { PrimaryPart = root, Parent = true, Name = "WhiteNPC_" .. guidSeq }
	root.Parent = model
	function model:FindFirstChildOfClass(cls) if cls == "Humanoid" then return humanoid end return nil end
	function model:FindFirstChild(name) if name == "UpperTorso" then return root end return nil end
	function model:SetAttribute(k, v) attrs[k] = v end
	function model:GetAttribute(k) return attrs[k] end
	function model:PivotTo(cf)
		root.CFrame = cf
		root.Position = cf.Position
	end
	function model:GetPivot() return root.CFrame end
	return model
end

local npcSrc = FS.readFile("Scripts/ServerStorage/Scripts/NPC.luau")
local npcStart = assert(npcSrc:find("local NPC = {}", 1, true))
local NPC = Luau.load(npcSrc:sub(npcStart), {
	environment = {
		Vector3 = V, CFrame = C, Enum = R.Enum, Instance = R.Instance, Scene = Scene, Config = Config,
		StreetCrowd = StreetCrowd,
		HttpService = { GenerateGUID = function() guidSeq += 1; return "npc_" .. guidSeq end },
		ModelTemplates = { WaitCharacter = function() return { Clone = createBodyModel } end },
		Surface = { Total = function() return 1 end },
		Random = FakeRandom,
		workspace = {
			GetServerTimeNow = function() return now end,
			Blockcast = function() return nil end,
			GetPartBoundsInBox = function() return {} end,
		},
		RunService = { PreSimulation = { Connect = function() return { Disconnect = function() end } end } },
		RaycastParams = { new = function() return {} end },
		OverlapParams = { new = function() return {} end },
		Physics = { GroundRootEnabled = false },
		Ragdoll = { Setup = function() end, SetMode = function() end },
		PersonalRules = { RemainingNpcHp = function(hp, _, dmg) return math.max(0, hp - dmg) end },
	},
})()

local items = {}
local runtime = {}
for _ = 1, 18 do
	local item = assert(NPC.Spawn(runtime, items), "spawn 18 NPCs")
	items[item.id] = item
end

local function stepPhysics(dt)
	for _, item in items do
		if item.location ~= "Street" or item.hits >= Config.StunHits then continue end
		local root = item.model.PrimaryPart
		local hum = item.model:FindFirstChildOfClass("Humanoid")
		local target = hum.target
		local delta = V.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
		if delta.Magnitude > 0.05 and hum.WalkSpeed > 0.05 then
			local dir = delta.Unit
			local moveDist = math.min(delta.Magnitude, hum.WalkSpeed * dt)
			local nextPos = root.Position + dir * moveDist
			root.Position = nextPos
			root.CFrame = C.lookAlong(nextPos, dir)
			root.AssemblyLinearVelocity = dir * (moveDist / dt)
		else
			root.AssemblyLinearVelocity = V.zero
		end
	end
end

local dt = 0.05
local severeOverlapSamples = 0
local totalPairSamples = 0
local minNeighborSum = 0
local minNeighborSamples = 0
local poiVisited = 0
local duplicatePoiViolations = 0

local list = {}
for _, item in items do table.insert(list, item) end

for step = 1, 1200 do
	now += dt
	NPC.StepCrowd(items, {}, now, dt)
	stepPhysics(dt)

	local poiUsed = {}
	for i = 1, #list do
		local a = list[i]
		assert(Scene.IsInStreetWalkZones(a.model.PrimaryPart.Position, 1.5), "NPC stayed inside street walk zones")
		if a.poiId and a.motionState == "LookAround" then
			poiVisited += 1
			if poiUsed[a.poiId] then
				duplicatePoiViolations += 1
			end
			poiUsed[a.poiId] = true
		end
		local minD = math.huge
		for j = 1, #list do
			if i ~= j then
				local pa = a.model.PrimaryPart.Position
				local pb = list[j].model.PrimaryPart.Position
				local d = math.sqrt((pa.X - pb.X) ^ 2 + (pa.Z - pb.Z) ^ 2)
				if d < minD then minD = d end
				if j > i then
					totalPairSamples += 1
					if d < 1.8 then severeOverlapSamples += 1 end
				end
			end
		end
		minNeighborSum += minD
		minNeighborSamples += 1
	end
end

assert(duplicatePoiViolations == 0, "no two NPCs may occupy the same POI simultaneously")
assert(poiVisited > 0, "NPCs visited storefront POIs during 60s stroll")

local westCount, midCount, eastCount = 0, 0, 0
local sumX = 0
for _, item in list do
	local x = item.model.PrimaryPart.Position.X
	sumX += x
	if x < -25 then westCount += 1 elseif x <= 30 then midCount += 1 else eastCount += 1 end
end
local meanX = sumX / #list
local varX = 0
for _, item in list do
	varX += (item.model.PrimaryPart.Position.X - meanX) ^ 2
end
local stdX = math.sqrt(varX / #list)
local avgMinNeighbor = minNeighborSum / minNeighborSamples
local severeRate = severeOverlapSamples / totalPairSamples

assert(westCount >= 2 and midCount >= 2 and eastCount >= 2, string.format("balanced street spread W=%d M=%d E=%d", westCount, midCount, eastCount))
assert(stdX >= 28, string.format("no center clustering stdX=%.2f", stdX))
assert(avgMinNeighbor >= 5.5, string.format("healthy spacing avgMinNeighbor=%.2f", avgMinNeighbor))
assert(severeRate < 0.002, string.format("severe overlap rate=%.5f", severeRate))

-- 测试 2：群体受惊扩散（16 studs 内触发，24 studs 外不受影响）
NPC.ResetCrowd()
local victim = list[1]
local witness = list[2]
local bystander = list[3]
victim.model:PivotTo(C.new(0, 23.28, -67))
witness.model:PivotTo(C.new(10, 23.28, -67))
bystander.model:PivotTo(C.new(35, 23.28, -67))
for i = 4, #list do
	list[i].model:PivotTo(C.new(-70 + i * 3, 23.28, -80))
end
victim.fleeUntil, victim.panicUntil = nil, nil
witness.fleeUntil, witness.panicUntil = nil, nil
bystander.fleeUntil, bystander.panicUntil = nil, nil

NPC.Hit(victim, V.xAxis, 10, nil, V.new(-5, 23.28, -67), items)
assert(witness.panicUntil ~= nil and witness.panicUntil > now, "nearby witness within 16 studs enters panic")
assert(bystander.panicUntil == nil, "distant bystander beyond 16 studs ignores panic")
NPC.StepCrowd(items, {}, now + 0.05, dt)
assert(witness.motionState == "Fleeing" and witness.model:FindFirstChildOfClass("Humanoid").WalkSpeed <= Config.NpcPanicSpeed + 0.01)

-- 测试 3：动态避让迎面玩家与倒地白膜
NPC.ResetCrowd()
local walker = list[4]
walker.fleeUntil, walker.panicUntil, walker.poiId = nil, nil, nil
walker.model:PivotTo(C.new(-20, 23.28, -67))
walker.walkTarget = V.new(20, 20.08, -67)
walker.nextWalk = now + 20
local downed = list[5]
downed.hits = 3
downed.model:PivotTo(C.new(-12, 21.0, -67))
local obstacles = {
	{ id = "player1", position = V.new(-10, 23.28, -67), velocity = V.new(-16, 0, 0), radius = Config.NpcDynamicObstacleRadius, locked = false },
}
for _ = 1, 20 do
	now += dt
	NPC.StepCrowd(items, obstacles, now, dt)
	stepPhysics(dt)
end
assert(math.abs(walker.model.PrimaryPart.Position.Z - (-67)) > 0.35, "walker steers laterally around oncoming player & downed body")

print(string.format(
	"PASS: 18-NPC 60s crowd simulation (stdX=%.1f, avgMinNeighbor=%.2f, severeOverlap=%.4f%%, poiSamples=%d, panic+avoidance ok)",
	stdX, avgMinNeighbor, severeRate * 100, poiVisited
))
