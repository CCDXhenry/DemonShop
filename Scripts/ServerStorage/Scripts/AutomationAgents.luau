-- 自动化 AI 代理：A01/A02 地狱打手巡逻互锁搬运与 A05 自动售货员全额结算
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Scripts.Shared
local Config = require(Shared.GameConfig)
local GameData = require(Shared.GameData)
local Types = require(Shared.GameTypes)
local Net = require(Shared.ProcessingNet)
local Lifecycle = require(Shared.LifecycleTool)
local ModelTemplates = require(Shared.ModelTemplates)
local Physics = require(Shared.PhysicsConfig)
local NPC = require(script.Parent.NPC)
local Carry = require(script.Parent.Carry)
local Scene = require(script.Parent.Scene)

local AutomationAgents = {}

export type Host = {
	runtime: Folder,
	scope: Lifecycle.Lifecycle,
	items: { [string]: Types.Item },
	stationVersions: { [string]: number },
	isUnlocked: (facilityId: number) -> boolean,
	getAutoShelfCount: () -> number,
	takeAutoShelf: () -> number,
	payPotionSale: (count: number, warnIfBlocked: boolean) -> boolean,
	pushChuteItem: (item: Types.Item) -> (),
	stepAutomation: (now: number) -> boolean,
	changed: () -> (),
}

type BrutePhase = "IdleAtPost" | "ExitShop" | "SeekTarget" | "LiftBody" | "CarryToChute" | "DropInChute" | "ReturnToPost"
type ClerkPhase = "IdleAtStation" | "GoToAutoShelf" | "GoToSigil" | "ReturnToStation"

type Tracks = {
	idle: AnimationTrack?,
	walk: AnimationTrack?,
	carry: AnimationTrack?,
	slash: AnimationTrack?,
}

export type BruteAgent = {
	id: string,
	facilityId: number,
	variant: number,
	model: Model,
	root: BasePart,
	tracks: Tracks,
	motionState: string,
	floorPos: Vector3,
	facing: Vector3,
	state: BrutePhase,
	targetId: string?,
	carryingId: string?,
	nextHitAt: number,
	pickupReadyAt: number,
	lift: { from: CFrame, started: number }?,
	stateEndsAt: number,
	dropStartPos: Vector3?,
	waypoints: { Vector3 },
	waypointIndex: number,
}

export type ClerkAgent = {
	id: string,
	model: Model,
	root: BasePart,
	tracks: Tracks,
	motionState: string,
	floorPos: Vector3,
	facing: Vector3,
	state: ClerkPhase,
	carryingPotions: number,
	retryAt: number,
	warnedLimit: boolean,
	potionParts: { BasePart },
	potionLights: { PointLight },
}

export type State = {
	host: Host,
	folder: Folder,
	destroyed: boolean,
	lastTick: number?,
	destroyingConn: RBXScriptConnection?,
	brutes: { [string]: BruteAgent },
	clerk: ClerkAgent?,
	targetLocks: { [string]: string },
}


local DEFAULT_CHUTE_TOP = Vector3.new(-58.8, 21.797, -37.25)
local SHOP_FLOOR_Y = 21.397
local SIDEWALK_Y = 20.345
local STREET_DECK_Y = 20.08
local POST_DECK_Y = 20.795
local CLERK_DECK_Y = 1.0
local BASEMENT_FLOOR_Y = 0.0

local WAYPOINT_STREET_LANE = Vector3.new(-58.8, STREET_DECK_Y, -51.0)
local WAYPOINT_DOOR_OUTSIDE = Vector3.new(-59.025, SIDEWALK_Y, -44.5)
local WAYPOINT_DOOR_INSIDE = Vector3.new(-59.025, SHOP_FLOOR_Y, -38.4)


local function FlatVector(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function FlatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function FlatUnit(delta: Vector3, fallback: Vector3): Vector3
	local flat = FlatVector(delta)
	if flat.Magnitude > 0.001 then
		return flat.Unit
	end
	local fb = FlatVector(fallback)
	return if fb.Magnitude > 0.001 then fb.Unit else -Vector3.zAxis
end

local function FacingFrame(position: Vector3, direction: Vector3): CFrame
	local dir = FlatUnit(direction, -Vector3.zAxis)
	local yaw = math.atan2(-dir.X, -dir.Z)
	return CFrame.new(position) * CFrame.Angles(0, yaw, 0)
end

local function RootPosFromFloor(floorPos: Vector3): Vector3
	return Vector3.new(floorPos.X, floorPos.Y + Config.AgentRootHeight, floorPos.Z)
end

local function ChuteTopPos(): Vector3
	return if Scene.ChuteTopDrop then Scene.ChuteTopDrop.Position else DEFAULT_CHUTE_TOP
end

local function IsStandardChuteLayout(): boolean
	local top = ChuteTopPos()
	return math.abs(top.X - DEFAULT_CHUTE_TOP.X) < 4 and math.abs(top.Z - DEFAULT_CHUTE_TOP.Z) < 4
end

local function ChuteStandPos(): Vector3
	local top = ChuteTopPos()
	local floorY = if IsStandardChuteLayout() then SHOP_FLOOR_Y else math.max(0, top.Y - 0.4)
	return Vector3.new(top.X, floorY, top.Z)
end

local function ChuteDropPos(): Vector3
	local top = ChuteTopPos()
	local opening = Scene.FastChuteOpening
	if opening then
		local entry = opening.CFrame * Vector3.new(0, 0, -opening.Size.Z * 0.5 + 2)
		return Vector3.new(entry.X, top.Y, entry.Z)
	end
	return top
end

local function BruteSpawnFloor(variant: number): Vector3
	local anchor = if variant == 1 then Scene.Brute1Spawn else Scene.Brute2Spawn
	if anchor then
		return Vector3.new(anchor.Position.X, math.max(0, anchor.Position.Y - 0.1), anchor.Position.Z)
	end
	return Vector3.new(if variant == 1 then -54.0 else -50.2, POST_DECK_Y, -41.0)
end

local function ClerkSpawnFloor(): Vector3
	local anchor = Scene.ClerkSpawn
	if anchor then
		return Vector3.new(anchor.Position.X, math.max(0, anchor.Position.Y - 0.15), anchor.Position.Z)
	end
	return Vector3.new(22.0, CLERK_DECK_Y, -27.25)
end

local function AutoShelfPickupFloor(): Vector3
	local anchor = Scene.AutoShelfPickup
	if anchor then
		return Vector3.new(anchor.Position.X, BASEMENT_FLOOR_Y, anchor.Position.Z)
	end
	return Vector3.new(10.0, BASEMENT_FLOOR_Y, -27.2)
end

local function SigilFloor(): Vector3
	local pos = Scene.SigilPosition
	return Vector3.new(pos.X, BASEMENT_FLOOR_Y, pos.Z)
end

local function SampleFloorY(host: Host, state: State, x: number, z: number, fallbackY: number): number
	local ignored: { Instance } = { host.runtime, state.folder }
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignored, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignored
	params.RespectCanCollide = true
	local hit = workspace:Raycast(Vector3.new(x, fallbackY + 4, z), Vector3.new(0, -10, 0), params)
	if hit and hit.Normal.Y > 0.6 and math.abs(hit.Position.Y - fallbackY) <= 2.5 then
		return hit.Position.Y
	end
	return fallbackY
end


local function LoadTrack(animator: Animator, animId: string, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack?
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local ok, result = pcall(function(): AnimationTrack
		return animator:LoadAnimation(anim)
	end)
	anim:Destroy()
	if ok and result then
		result.Looped = looped
		result.Priority = priority
		return result
	end
	return nil
end

local function LoadAgentTracks(model: Model): Tracks
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return {}
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local actualAnimator = animator :: Animator
	return {
		idle = LoadTrack(actualAnimator, Config.IdleAnimation, true, Enum.AnimationPriority.Idle),
		walk = LoadTrack(actualAnimator, Config.WalkAnimation, true, Enum.AnimationPriority.Movement),
		carry = LoadTrack(actualAnimator, Config.BodyCarryAnimation, true, Enum.AnimationPriority.Action),
		slash = LoadTrack(actualAnimator, Config.WeaponSlashAnimation, false, Enum.AnimationPriority.Action2),
	}
end

local function StopAndDestroyTracks(tracks: Tracks): ()
	for _, track in { tracks.idle, tracks.walk, tracks.carry, tracks.slash } do
		if track then
			pcall(function(): ()
				track:Stop(0)
				track:Destroy()
			end)
		end
	end
	tracks.idle = nil
	tracks.walk = nil
	tracks.carry = nil
	tracks.slash = nil
end

local function SetAgentMotion(tracks: Tracks, current: string, nextState: string): string
	if current == nextState then
		return current
	end
	if nextState == "Carry" or nextState == "Lift" then
		if tracks.idle and tracks.idle.IsPlaying then
			tracks.idle:Stop(Config.MotionFadeSeconds)
		end
		if tracks.walk then
			if nextState == "Carry" and not tracks.walk.IsPlaying then
				tracks.walk:Play(Config.MotionFadeSeconds)
			elseif nextState == "Lift" and tracks.walk.IsPlaying then
				tracks.walk:Stop(Config.MotionFadeSeconds)
			end
		end
		if tracks.carry and not tracks.carry.IsPlaying then
			tracks.carry:Play(Config.CarryAnimationFade)
		end
	elseif nextState == "Walk" then
		if tracks.carry and tracks.carry.IsPlaying then
			tracks.carry:Stop(Config.CarryAnimationFade)
		end
		if tracks.idle and tracks.idle.IsPlaying then
			tracks.idle:Stop(Config.MotionFadeSeconds)
		end
		if tracks.walk and not tracks.walk.IsPlaying then
			tracks.walk:Play(Config.MotionFadeSeconds)
		end
	else
		if tracks.carry and tracks.carry.IsPlaying then
			tracks.carry:Stop(Config.CarryAnimationFade)
		end
		if tracks.walk and tracks.walk.IsPlaying then
			tracks.walk:Stop(Config.MotionFadeSeconds)
		end
		if tracks.idle and not tracks.idle.IsPlaying then
			tracks.idle:Play(Config.MotionFadeSeconds)
		end
	end
	return nextState
end


local function SetClerkPotionVisible(agent: ClerkAgent, visible: boolean): ()
	for _, part in agent.potionParts do
		if part.Name == "Bottle" or part.Name == "Neck" then
			part.Transparency = if visible then 0.35 else 1
		else
			part.Transparency = if visible then 0 else 1
		end
	end
	for _, light in agent.potionLights do
		light.Enabled = visible
	end
end


local function SetModelPose(model: Model, pose: CFrame): ()
	model:PivotTo(pose)
end

local function ShoulderPose(agent: BruteAgent): CFrame
	local rootPos = RootPosFromFloor(agent.floorPos)
	local torsoCf = FacingFrame(rootPos + Vector3.new(0, 0.2, 0), agent.facing)
	return torsoCf * CFrame.new(Physics.ShoulderOffset) * Physics.ShoulderRotation
end

local function BuildInwardWaypoints(fromPos: Vector3): { Vector3 }
	local stand = ChuteStandPos()
	if not IsStandardChuteLayout() then
		return { stand }
	end
	if fromPos.Z <= -49.0 then
		return { WAYPOINT_STREET_LANE, WAYPOINT_DOOR_OUTSIDE, WAYPOINT_DOOR_INSIDE, stand }
	elseif fromPos.Z <= -39.5 then
		return { WAYPOINT_DOOR_OUTSIDE, WAYPOINT_DOOR_INSIDE, stand }
	end
	return { stand }
end

local function BuildOutwardWaypoints(): { Vector3 }
	if not IsStandardChuteLayout() then
		return {}
	end
	return { WAYPOINT_DOOR_INSIDE, WAYPOINT_DOOR_OUTSIDE, WAYPOINT_STREET_LANE }
end

local function BuildReturnPostWaypoints(fromPos: Vector3, variant: number): { Vector3 }
	local spawnFloor = BruteSpawnFloor(variant)
	if not IsStandardChuteLayout() then
		return { spawnFloor }
	end
	local approach = Vector3.new(spawnFloor.X, SIDEWALK_Y, -45.5)
	if fromPos.Z <= -49.0 then
		return { Vector3.new(WAYPOINT_STREET_LANE.X, STREET_DECK_Y, -51.0), approach, spawnFloor }
	end
	return { approach, spawnFloor }
end

local function AdvanceTowards(
	host: Host,
	state: State,
	floorPos: Vector3,
	facing: Vector3,
	goal: Vector3,
	speed: number,
	dt: number
): (Vector3, Vector3, boolean)
	local delta = FlatVector(goal - floorPos)
	local dist = delta.Magnitude
	local step = speed * dt
	if dist <= 0.01 or step <= 0 then
		return Vector3.new(goal.X, SampleFloorY(host, state, goal.X, goal.Z, goal.Y), goal.Z),
			FlatUnit(delta, facing),
			dist <= 0.05
	end
	local dir = delta / dist
	if step >= dist then
		local ny = SampleFloorY(host, state, goal.X, goal.Z, goal.Y)
		return Vector3.new(goal.X, ny, goal.Z), dir, true
	end
	local alpha = step / dist
	local nx = floorPos.X + delta.X * alpha
	local nz = floorPos.Z + delta.Z * alpha
	local approxY = floorPos.Y + (goal.Y - floorPos.Y) * alpha
	local ny = SampleFloorY(host, state, nx, nz, approxY)
	return Vector3.new(nx, ny, nz), dir, false
end

local function AdvanceWaypoints(
	host: Host,
	state: State,
	agent: BruteAgent,
	speed: number,
	dt: number
): boolean
	local budget = speed * dt
	while agent.waypointIndex <= #agent.waypoints and budget > 0 do
		local wp = agent.waypoints[agent.waypointIndex]
		local dist = FlatDistance(agent.floorPos, wp)
		if dist <= 0.05 then
			agent.floorPos = Vector3.new(wp.X, SampleFloorY(host, state, wp.X, wp.Z, wp.Y), wp.Z)
			agent.waypointIndex += 1
		else
			local travel = math.min(dist, budget)
			local stepDt = travel / math.max(speed, 0.001)
			local nextPos, nextFacing, reached = AdvanceTowards(host, state, agent.floorPos, agent.facing, wp, speed, stepDt)
			agent.floorPos = nextPos
			agent.facing = nextFacing
			budget -= travel
			if reached then
				agent.waypointIndex += 1
			end
		end
	end
	return agent.waypointIndex > #agent.waypoints
end

local function IsTargetClaimable(host: Host, state: State, agentId: string, item: Types.Item?): boolean
	if not item or item.kind ~= "Body" or item.location ~= "Street" then
		return false
	end
	if item.holder ~= nil or item.poolToss ~= nil or item.altarToss ~= nil then
		return false
	end
	if item.model.Parent == nil or item.model.PrimaryPart == nil then
		return false
	end
	local lockedBy = state.targetLocks[item.id]
	return lockedBy == nil or lockedBy == agentId
end

local function ReleaseTargetLock(state: State, agent: BruteAgent): ()
	if agent.targetId and state.targetLocks[agent.targetId] == agent.id then
		state.targetLocks[agent.targetId] = nil
	end
	agent.targetId = nil
end

local function CleanStaleLocks(host: Host, state: State): ()
	for itemId, agentId in state.targetLocks do
		local agent = state.brutes[agentId]
		local item = host.items[itemId]
		if not agent or not item then
			state.targetLocks[itemId] = nil
		elseif agent.carryingId == itemId then
			if item.location ~= "BruteCarried" or item.model.Parent == nil then
				state.targetLocks[itemId] = nil
				agent.carryingId = nil
			end
		elseif agent.targetId == itemId then
			if not IsTargetClaimable(host, state, agentId, item) then
				state.targetLocks[itemId] = nil
				agent.targetId = nil
			end
		else
			state.targetLocks[itemId] = nil
		end
	end
end

local function AcquireNearestTarget(host: Host, state: State, agent: BruteAgent): Types.Item?
	if not host.isUnlocked(GameData.FacilityId.FastChute) then
		return nil
	end
	local bestItem: Types.Item? = nil
	local bestDist = math.huge
	for _, item in host.items do
		if IsTargetClaimable(host, state, agent.id, item) then
			local root = item.model.PrimaryPart
			if root then
				local dist = FlatDistance(agent.floorPos, root.Position)
				if dist < bestDist or (math.abs(dist - bestDist) < 1e-4 and (bestItem == nil or item.id < bestItem.id)) then
					bestDist = dist
					bestItem = item
				end
			end
		end
	end
	if bestItem then
		ReleaseTargetLock(state, agent)
		state.targetLocks[bestItem.id] = agent.id
		agent.targetId = bestItem.id
	end
	return bestItem
end

local function EnterSeekTarget(agent: BruteAgent): ()
	agent.state = "SeekTarget"
	agent.waypoints = {}
	agent.waypointIndex = 1
	if IsStandardChuteLayout() and agent.floorPos.Z > -49.0 then
		table.insert(agent.waypoints, Vector3.new(agent.floorPos.X, STREET_DECK_Y, -51.0))
	end
end

local function BrutePickupBody(state: State, agent: BruteAgent, item: Types.Item, now: number): ()
	local from = item.model:GetPivot()
	Carry.Detach(item, false)
	NPC.StopMotion(item)
	-- 冻结当前倒姿，避免在提起第一帧把四肢重置到模板姿势。
	for _, part in item.model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
		end
	end
	item.location = "BruteCarried"
	item.motionState = "Carried"
	item.streetSlot = false
	item.version += 1
	item.model:SetAttribute("PhysicsMode", "Carried")
	item.model:SetAttribute("MotionState", "Carried")
	item.model:SetAttribute("BruteCarrier", agent.id)
	state.targetLocks[item.id] = agent.id
	agent.targetId = item.id
	agent.carryingId = item.id
	agent.state = "LiftBody"
	agent.lift = { from = from, started = now }
	local slash = agent.tracks.slash
	if slash and slash.IsPlaying then slash:Stop(Config.MotionFadeSeconds) end
end

local BruteReachFraction = 0.30
local BruteReachDepth = 0.32
local BruteReachLean = math.rad(16)
local BruteLiftArc = 0.42

local function SmoothStep(t: number): number
	return t * t * (3 - 2 * t)
end

local function BruteDepositBody(host: Host, state: State, agent: BruteAgent, now: number): boolean
	local itemId = agent.carryingId
	agent.carryingId = nil
	if itemId then
		if state.targetLocks[itemId] == agent.id then
			state.targetLocks[itemId] = nil
		end
		if agent.targetId == itemId then
			agent.targetId = nil
		end
	end
	local item = if itemId then host.items[itemId] else nil
	if item and item.model.Parent ~= nil then
		item.model:SetAttribute("BruteCarrier", nil)
		item.model:SetAttribute("PhysicsMode", nil)
		item.model:SetAttribute("MotionState", "Static")
		for _, part in item.model:GetDescendants() do
			if part:IsA("BasePart") then
				part.CanQuery = part.Name ~= "HumanoidRootPart" and part:GetAttribute("Paintable") == true
			end
		end
		if host.isUnlocked(GameData.FacilityId.FastChute) then
			host.pushChuteItem(item)
			host.stepAutomation(now)
		else
			Carry.Drop(item, agent.floorPos, false)
		end
		return true
	end
	return false
end

local missingBruteTemplate: { [string]: boolean } = {}
local missingClerkTemplate = false

local function PrepareClonedAgent(model: Model, agentId: string, role: string): BasePart
	model.Name = agentId
	model:SetAttribute("AgentId", agentId)
	model:SetAttribute("AgentRole", role)
	model:SetAttribute("Paintable", nil)
	model:SetAttribute("SurfaceVersion", nil)
	model:SetAttribute("GroundPresentation", nil)

	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	assert(root and root:IsA("BasePart"), "Agent rig requires HumanoidRootPart")
	model.PrimaryPart = root

	for _, desc in model:GetDescendants() do
		if desc:IsA("LuaSourceContainer") then
			desc:Destroy()
		elseif desc:IsA("BasePart") then
			desc:SetAttribute("Paintable", nil)
			desc:SetAttribute("SurfaceVersion", nil)
			desc.Anchored = desc == root
			desc.CanCollide = false
			desc.CanTouch = false
			desc.CanQuery = false
			desc.Massless = true
			desc.CollisionGroup = "Default"
			if desc == root then
				desc.Transparency = 1
			end
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.EvaluateStateMachine = false
		humanoid.PlatformStand = true
		humanoid.AutoRotate = false
		humanoid.BreakJointsOnDeath = false
		humanoid.WalkSpeed = 0
	end

	return root
end

local function SpawnBrute(state: State, variant: number, now: number): ()
	local agentId = "Brute" .. tostring(variant)
	local templateName = if variant == 1 then "HellBrute_1" else "HellBrute_2"
	local template = ModelTemplates.FindCharacter(templateName)
	if not template then
		if not missingBruteTemplate[templateName] then
			missingBruteTemplate[templateName] = true
			warn(string.format("[AutomationAgents] Missing ReplicatedStorage.Models.Characters.%s", templateName))
		end
		return
	end
	local model = template:Clone()
	local root = PrepareClonedAgent(model, templateName, "Brute")
	local floorPos = BruteSpawnFloor(variant)
	local facing = -Vector3.zAxis
	SetModelPose(model, FacingFrame(RootPosFromFloor(floorPos), facing))
	model.Parent = state.folder
	local tracks = LoadAgentTracks(model)
	local agent: BruteAgent = {
		id = agentId,
		facilityId = if variant == 1 then GameData.FacilityId.Brute1 else GameData.FacilityId.Brute2,
		variant = variant,
		model = model,
		root = root,
		tracks = tracks,
		motionState = "",
		floorPos = floorPos,
		facing = facing,
		state = "IdleAtPost",
		targetId = nil,
		carryingId = nil,
		nextHitAt = now,
		pickupReadyAt = 0,
		stateEndsAt = 0,
		dropStartPos = nil,
		waypoints = {},
		waypointIndex = 1,
	}
	agent.motionState = SetAgentMotion(tracks, agent.motionState, "Idle")
	state.brutes[agentId] = agent
end

local CLERK_POTION_PARTS: { [string]: boolean } = {
	Bottle = true,
	Neck = true,
	HeldPotionCore = true,
	HeldPotionStopper = true,
}

local function CollectClerkProps(model: Model): ({ BasePart }, { PointLight })
	local parts: { BasePart } = {}
	local lights: { PointLight } = {}
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") and CLERK_POTION_PARTS[desc.Name] then
			table.insert(parts, desc)
		elseif desc:IsA("PointLight") then
			table.insert(lights, desc)
		end
	end
	return parts, lights
end

local function SpawnClerk(state: State): ()
	local template = ModelTemplates.FindCharacter("AutoClerk")
	if not template then
		if not missingClerkTemplate then
			missingClerkTemplate = true
			warn("[AutomationAgents] Missing ReplicatedStorage.Models.Characters.AutoClerk")
		end
		return
	end
	local cloned = template:Clone()
	if not cloned:IsA("Model") then
		cloned:Destroy()
		return
	end
	local model = cloned
	local root = PrepareClonedAgent(model, "AutoClerk", "Clerk")
	local potionParts, potionLights = CollectClerkProps(model)
	local floorPos = ClerkSpawnFloor()
	local facing = Vector3.zAxis
	SetModelPose(model, FacingFrame(RootPosFromFloor(floorPos), facing))
	model.Parent = state.folder
	local tracks = LoadAgentTracks(model)
	local clerk: ClerkAgent = {
		id = "AutoClerk",
		model = model,
		root = root,
		tracks = tracks,
		motionState = "",
		floorPos = floorPos,
		facing = facing,
		state = "IdleAtStation",
		carryingPotions = 0,
		retryAt = 0,
		warnedLimit = false,
		potionParts = potionParts,
		potionLights = potionLights,
	}
	SetClerkPotionVisible(clerk, false)
	clerk.motionState = SetAgentMotion(tracks, clerk.motionState, "Idle")
	state.clerk = clerk
end

-- 创建并绑定自动化 AI 状态容器（随宿主生命周期或作用域销毁自动释放）
function AutomationAgents.New(host: Host): State
	local folder = Instance.new("Folder")
	folder.Name = "AutomationAgents"
	folder.Parent = host.runtime
	local state: State = {
		host = host,
		folder = folder,
		destroyed = false,
		lastTick = nil,
		destroyingConn = nil,
		brutes = {},
		clerk = nil,
		targetLocks = {},
	}
	local hasDestroying, destroyingSignal = pcall(function(): RBXScriptSignal
		return folder.Destroying
	end)
	if hasDestroying and destroyingSignal then
		host.scope:Own(folder)
		state.destroyingConn = destroyingSignal:Once(function(): ()
			AutomationAgents.Destroy(state)
		end)
	elseif host.scope.alive then
		host.scope.instances[folder] = true
	end
	return state
end

-- 根据当前已解锁的 A01/A02/A05 设施按需生成对应 AI 代理模型
function AutomationAgents.SyncUnlocked(state: State, now: number): ()
	if state.destroyed then
		return
	end
	if state.lastTick == nil then
		state.lastTick = now
	end
	local isUnlocked = state.host.isUnlocked
	if isUnlocked(GameData.FacilityId.Brute1) and not state.brutes.Brute1 then
		SpawnBrute(state, 1, now)
	end
	if isUnlocked(GameData.FacilityId.Brute2) and not state.brutes.Brute2 then
		SpawnBrute(state, 2, now)
	end
	if isUnlocked(GameData.FacilityId.AutoClerk) and not state.clerk then
		SpawnClerk(state)
	end
end

local function StepBrute(host: Host, state: State, agent: BruteAgent, now: number, dt: number): boolean
	local changed = false
	local speed = Config.BruteWalkSpeed
	local wantMotion = "Idle"
	local liftBend = 0

	if agent.state == "DropInChute" then
		local item = if agent.carryingId then host.items[agent.carryingId] else nil
		if item and item.model.Parent ~= nil then
			local topPos = ChuteDropPos()
			local startPos = agent.dropStartPos or ShoulderPose(agent).Position
			local duration = math.max(Config.BruteDropDuration, 0.01)
			local remaining = math.max(0, agent.stateEndsAt - now)
			local alpha = math.clamp(1 - remaining / duration, 0, 1)
			local pos = startPos:Lerp(topPos, alpha) + Vector3.yAxis * math.sin(alpha * math.pi) * 1.1
			SetModelPose(item.model, CFrame.new(pos) * CFrame.Angles(math.pi / 2, 0, 0))
		end
		if now >= agent.stateEndsAt then
			if BruteDepositBody(host, state, agent, now) then
				changed = true
			end
			agent.dropStartPos = nil
			agent.state = "ExitShop"
			agent.waypoints = BuildOutwardWaypoints()
			agent.waypointIndex = 1
		end
	elseif agent.state == "LiftBody" or agent.state == "CarryToChute" then
		local item = if agent.carryingId then host.items[agent.carryingId] else nil
		if not item or item.location ~= "BruteCarried" or item.model.Parent == nil or not item.model.PrimaryPart then
			if agent.carryingId and state.targetLocks[agent.carryingId] == agent.id then
				state.targetLocks[agent.carryingId] = nil
			end
			agent.carryingId = nil
			agent.targetId = nil
			agent.lift = nil
			agent.state = "ExitShop"
			agent.waypoints = BuildOutwardWaypoints()
			agent.waypointIndex = 1
		elseif agent.lift then
			local lift = agent.lift
			local progress = math.clamp((now - lift.started) / Config.BruteLiftDuration, 0, 1)
			local blend = SmoothStep(math.clamp((progress - BruteReachFraction) / (1 - BruteReachFraction), 0, 1))
			liftBend = if progress < BruteReachFraction then SmoothStep(progress / BruteReachFraction) else 1 - blend
			if progress >= BruteReachFraction then
				wantMotion = "Lift"
				local pose = lift.from:Lerp(ShoulderPose(agent), blend)
				SetModelPose(item.model, pose + Vector3.yAxis * (4 * BruteLiftArc * blend * (1 - blend)))
			end
			if progress >= 1 then
				agent.lift = nil
				agent.state = "CarryToChute"
				agent.waypoints = BuildInwardWaypoints(agent.floorPos)
				agent.waypointIndex = 1
			end
		else
			wantMotion = "Carry"
			local arrived = AdvanceWaypoints(host, state, agent, speed, dt)
			if arrived then
				agent.facing = FlatUnit(ChuteDropPos() - agent.floorPos, agent.facing)
				agent.dropStartPos = ShoulderPose(agent).Position
				agent.state = "DropInChute"
				agent.stateEndsAt = now + Config.BruteDropDuration
				wantMotion = "Idle"
			else
				SetModelPose(item.model, ShoulderPose(agent))
			end
		end
	elseif agent.state == "ExitShop" then
		wantMotion = "Walk"
		local exited = AdvanceWaypoints(host, state, agent, speed, dt)
		if exited then
			local nextTarget = AcquireNearestTarget(host, state, agent)
			if nextTarget then
				EnterSeekTarget(agent)
			else
				agent.state = "ReturnToPost"
				agent.waypoints = BuildReturnPostWaypoints(agent.floorPos, agent.variant)
				agent.waypointIndex = 1
			end
		end
	elseif agent.state == "IdleAtPost" then
		local nextTarget = AcquireNearestTarget(host, state, agent)
		if nextTarget then
			EnterSeekTarget(agent)
		else
			agent.facing = -Vector3.zAxis
		end
	elseif agent.state == "ReturnToPost" then
		local nextTarget = AcquireNearestTarget(host, state, agent)
		if nextTarget then
			EnterSeekTarget(agent)
		else
			wantMotion = "Walk"
			if AdvanceWaypoints(host, state, agent, speed, dt) then
				agent.state = "IdleAtPost"
				agent.facing = -Vector3.zAxis
				wantMotion = "Idle"
			end
		end
	end

	if agent.state == "SeekTarget" then
		local targetItem = if agent.targetId then host.items[agent.targetId] else nil
		if not IsTargetClaimable(host, state, agent.id, targetItem) then
			ReleaseTargetLock(state, agent)
			targetItem = AcquireNearestTarget(host, state, agent)
			if not targetItem then
				agent.state = "ReturnToPost"
				agent.waypoints = BuildReturnPostWaypoints(agent.floorPos, agent.variant)
				agent.waypointIndex = 1
			else
				EnterSeekTarget(agent)
			end
		end
		if agent.state == "SeekTarget" and targetItem then
			local targetRoot = targetItem.model.PrimaryPart
			if targetRoot then
				if agent.waypointIndex <= #agent.waypoints then
					wantMotion = "Walk"
					AdvanceWaypoints(host, state, agent, speed, dt)
				else
					local approxTargetY = if math.abs(targetRoot.Position.Y - 23.0) < 5
						then STREET_DECK_Y
						else math.max(0, targetRoot.Position.Y - Config.AgentRootHeight)
					local targetFloor = Vector3.new(targetRoot.Position.X, approxTargetY, targetRoot.Position.Z)
					local dist = FlatDistance(agent.floorPos, targetFloor)
					local desiredRange = if targetItem.hits >= Config.StunHits then Config.BrutePickupRange else Config.BruteHitRange
					if dist > desiredRange then
						wantMotion = "Walk"
						local nextPos, nextFacing = AdvanceTowards(host, state, agent.floorPos, agent.facing, targetFloor, speed, dt)
						agent.floorPos = nextPos
						agent.facing = nextFacing
						dist = FlatDistance(agent.floorPos, targetFloor)
					else
						agent.facing = FlatUnit(targetFloor - agent.floorPos, agent.facing)
					end
					if targetItem.hits >= Config.StunHits then
						local fall = targetItem.fall
						local readyAt = if fall then math.max(agent.pickupReadyAt, fall.started + Physics.Presentation.Fall.PhysicsSeconds) else agent.pickupReadyAt
						if dist <= Config.BrutePickupRange and now >= readyAt then
							BrutePickupBody(state, agent, targetItem, now)
							wantMotion = "Idle"
							changed = true
						end
					elseif dist <= Config.BruteHitRange and now >= agent.nextHitAt then
						local hitDir = FlatUnit(targetFloor - agent.floorPos, agent.facing)
						agent.facing = hitDir
						agent.nextHitAt = now + Config.BruteHitInterval
						local slashTrack = agent.tracks.slash
						if slashTrack then
							pcall(function(): ()
								slashTrack:Play(Config.WeaponAnimationFade)
							end)
						end
						NPC.Hit(targetItem, hitDir, Config.BruteDamage)
						local torso = targetItem.model:FindFirstChild("UpperTorso")
						local hitPos = targetRoot.Position
						if torso and torso:IsA("BasePart") then
							hitPos = torso.Position - hitDir * torso.Size.Z * 0.5
						end
						Net.Broadcast({
							kind = "Hit",
							actor = 0,
							id = targetItem.id,
							version = targetItem.version,
							hits = targetItem.hits,
							hp = targetItem.hp,
							maxHp = targetItem.maxHp,
							started = now,
							direction = hitDir,
							position = hitPos,
						})
						if targetItem.hits >= Config.StunHits then
							agent.pickupReadyAt = now + 0.12
						end
						changed = true
					end
				end
			end
		end
	end

	local rootPose = FacingFrame(RootPosFromFloor(agent.floorPos), agent.facing)
	if liftBend > 0 then
		rootPose *= CFrame.new(0, -BruteReachDepth * liftBend, 0) * CFrame.Angles(-BruteReachLean * liftBend, 0, 0)
	end
	SetModelPose(agent.model, rootPose)
	agent.motionState = SetAgentMotion(agent.tracks, agent.motionState, wantMotion)
	return changed
end

local function TrySubmitClerkPotions(host: Host, agent: ClerkAgent): (boolean, boolean)
	local count = agent.carryingPotions
	if count <= 0 then
		return false, true
	end
	if not host.payPotionSale(count, not agent.warnedLimit) then
		agent.warnedLimit = true
		return false, false
	end
	agent.carryingPotions = 0
	agent.warnedLimit = false
	SetClerkPotionVisible(agent, false)
	host.stationVersions.Sigil += 1
	return true, true
end

local function StepClerk(host: Host, state: State, agent: ClerkAgent, now: number, dt: number): boolean
	local changed = false
	local speed = Config.AutoClerkWalkSpeed
	local wantMotion = "Idle"

	if agent.state == "IdleAtStation" then
		agent.facing = Vector3.zAxis
		if host.getAutoShelfCount() > 0 then
			agent.state = "GoToAutoShelf"
		end
	elseif agent.state == "GoToAutoShelf" then
		if host.getAutoShelfCount() <= 0 then
			agent.state = "ReturnToStation"
		else
			local pickupPos = AutoShelfPickupFloor()
			local dist = FlatDistance(agent.floorPos, pickupPos)
			if dist > Config.AutoClerkPickupRange then
				wantMotion = "Walk"
				local nextPos, nextFacing = AdvanceTowards(host, state, agent.floorPos, agent.facing, pickupPos, speed, dt)
				agent.floorPos = nextPos
				agent.facing = nextFacing
				dist = FlatDistance(agent.floorPos, pickupPos)
			end
			if dist <= Config.AutoClerkPickupRange then
				local count = host.takeAutoShelf()
				if count > 0 then
					agent.carryingPotions = count
					agent.warnedLimit = false
					SetClerkPotionVisible(agent, true)
					agent.facing = -Vector3.zAxis
					agent.state = "GoToSigil"
					agent.retryAt = 0
					changed = true
				else
					agent.state = "ReturnToStation"
				end
			end
		end
	elseif agent.state == "GoToSigil" then
		local sigilPos = SigilFloor()
		local dist = FlatDistance(agent.floorPos, sigilPos)
		if dist > Config.AutoClerkSubmitRange then
			wantMotion = "Carry"
			local nextPos, nextFacing = AdvanceTowards(host, state, agent.floorPos, agent.facing, sigilPos, speed, dt)
			agent.floorPos = nextPos
			agent.facing = nextFacing
			dist = FlatDistance(agent.floorPos, sigilPos)
		else
			agent.facing = FlatUnit(sigilPos - agent.floorPos, agent.facing)
		end
		if dist <= Config.AutoClerkSubmitRange and now >= agent.retryAt then
			local paid, done = TrySubmitClerkPotions(host, agent)
			if paid then
				changed = true
			end
			if done then
				agent.state = "ReturnToStation"
			else
				agent.retryAt = now + 1.0
			end
		end
	elseif agent.state == "ReturnToStation" then
		local homePos = ClerkSpawnFloor()
		local dist = FlatDistance(agent.floorPos, homePos)
		if dist > 0.1 then
			wantMotion = "Walk"
			local nextPos, nextFacing, reached = AdvanceTowards(host, state, agent.floorPos, agent.facing, homePos, speed, dt)
			agent.floorPos = nextPos
			agent.facing = nextFacing
			if reached then
				agent.state = "IdleAtStation"
				agent.facing = Vector3.zAxis
				wantMotion = "Idle"
			end
		else
			agent.floorPos = homePos
			agent.state = "IdleAtStation"
			agent.facing = Vector3.zAxis
			wantMotion = "Idle"
		end
	end

	SetModelPose(agent.model, FacingFrame(RootPosFromFloor(agent.floorPos), agent.facing))
	agent.motionState = SetAgentMotion(agent.tracks, agent.motionState, wantMotion)
	return changed
end

-- 推进全部已解锁 AI 代理状态机与路径移动；有库存或命中状态变更时返回 true
function AutomationAgents.Step(state: State, now: number): boolean
	if state.destroyed then
		return false
	end
	AutomationAgents.SyncUnlocked(state, now)
	local host = state.host
	local lastTick = state.lastTick
	state.lastTick = now
	local rawDt = if lastTick then math.clamp(now - lastTick, 0, 0.5) else 0
	local simNow = if lastTick then now - rawDt else now
	local remaining = rawDt
	local changed = false
	local firstPass = true
	while firstPass or remaining > 1e-6 do
		firstPass = false
		local stepDt = math.min(remaining, 0.1)
		remaining -= stepDt
		simNow += stepDt
		CleanStaleLocks(host, state)
		for _, id in { "Brute1", "Brute2" } do
			local brute = state.brutes[id]
			if brute and StepBrute(host, state, brute, simNow, stepDt) then
				changed = true
			end
		end
		if state.clerk and StepClerk(host, state, state.clerk, simNow, stepDt) then
			changed = true
		end
	end
	return changed
end

-- 彻底释放全部 AI 模型、动画轨道、事件连接与目标互锁状态
function AutomationAgents.Destroy(state: State): ()
	if state.destroyed then
		return
	end
	state.destroyed = true
	if state.destroyingConn then
		state.destroyingConn:Disconnect()
		state.destroyingConn = nil
	end
	for _, brute in state.brutes do
		StopAndDestroyTracks(brute.tracks)
		if brute.carryingId then
			local item = state.host.items[brute.carryingId]
			if item and item.model.Parent ~= nil then
				item.model:SetAttribute("BruteCarrier", nil)
			end
		end
		if brute.model.Parent ~= nil then
			brute.model:Destroy()
		end
	end
	table.clear(state.brutes)
	if state.clerk then
		StopAndDestroyTracks(state.clerk.tracks)
		if state.clerk.model.Parent ~= nil then
			state.clerk.model:Destroy()
		end
		state.clerk = nil
	end
	table.clear(state.targetLocks)
	if state.folder.Parent ~= nil then
		state.folder:Destroy()
	end
end

return AutomationAgents
