-- NPC 模块：受限街道采样、白膜生成、RVO 群体避让、橱窗驻足、受惊扩散与击晕转换
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Config = require(ReplicatedStorage.Scripts.Shared.GameConfig)
local Surface = require(ReplicatedStorage.Scripts.Shared.PaintSurface)
local Types = require(ReplicatedStorage.Scripts.Shared.GameTypes)
local Ragdoll = require(script.Parent.Ragdoll)
local Scene = require(script.Parent.Scene)
local Physics = require(ReplicatedStorage.Scripts.Shared.PhysicsConfig)
local Ground = require(script.Parent.GroundAuthority)
local PersonalRules = require(ReplicatedStorage.Scripts.Shared.PersonalUpgradeRules)
local ModelTemplates = require(ReplicatedStorage.Scripts.Shared.ModelTemplates)
local StreetCrowd = require(script.Parent.StreetCrowd)
local NPC = {}
local random = Random.new()
local RootHeight = 3.2
local WalkCadenceSpeed = 7
local RunLoadGrace = 0.25
local RecoveryTolerance = 1
local FleeAngles = { 0, 45, -45, 90, -90, 135, -135, 180 }
local FleeDistances = { 15, 8, 3, 1.5 }
local WaypointRadius = 1.25
local PoiArriveRadius = 1.35
local StuckCheckDistance = 0.8
local YieldSpeedThreshold = 0.6

local crowd: StreetCrowd.Crowd? = if StreetCrowd then StreetCrowd.new() else nil

local function Flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function StopTrack(track: AnimationTrack?): ()
	if track and track.IsPlaying then track:Stop(Config.MotionFadeSeconds) end
end

local function SetMotion(item: Types.Item, state: string): ()
	if item.motionState == state then return end
	item.motionState = state
	item.model:SetAttribute("MotionState", state)
	if state ~= "LookAround" then item.model:SetAttribute("StreetLookStarted", nil) end
	if state ~= "Fleeing" then
		StopTrack(item.runTrack)
		item.runRequestedAt = nil
	end
	if state ~= "Walking" and state ~= "Fleeing" then StopTrack(item.walkTrack) end
	local idle = item.idleTrack
	if state == "Idle" or state == "LookAround" then
		if idle and not idle.IsPlaying then idle:Play(Config.MotionFadeSeconds) end
	else
		StopTrack(idle)
	end
end

local function PlayLocomotion(item: Types.Item, speed: number, running: boolean, now: number): ()
	local track = item.walkTrack
	local cadence = WalkCadenceSpeed
	local run = item.runTrack
	if running and run then
		local requestedAt = item.runRequestedAt or now
		item.runRequestedAt = requestedAt
		if not run.IsPlaying and (run.Length > 0 or now - requestedAt < RunLoadGrace) then
			run:Play(Config.MotionFadeSeconds)
		end
		if run.Length > 0 then
			track, cadence = run, Config.NpcFleeSpeed
			StopTrack(item.walkTrack)
		elseif now - requestedAt >= RunLoadGrace then
			StopTrack(run)
		end
	end
	if track then
		local rate = math.clamp(speed / cadence, 0.15, if track == item.walkTrack and running then 2.5 else 1.2)
		if track.IsPlaying then track:AdjustSpeed(rate) else track:Play(Config.MotionFadeSeconds, 1, rate) end
	end
end

local function LoadTrack(animator: Animator, asset: string, priority: Enum.AnimationPriority): AnimationTrack?
	if asset == "" then return nil end
	local animation = Instance.new("Animation")
	animation.AnimationId = asset
	local ok, track = pcall(function(): AnimationTrack return animator:LoadAnimation(animation) end)
	animation:Destroy()
	if not ok then return nil end
	track.Looped, track.Priority = true, priority
	return track
end

local function ClearPoi(item: Types.Item, now: number?, applyCooldown: boolean?): ()
	if item.poiId then
		item.lastPoiId = item.poiId
		item.poiId = nil
	end
	item.poiLookDir = nil
	if crowd then
		crowd:ReleasePoi(item.id, now, applyCooldown)
	end
end

function NPC.ResetCrowd(): ()
	if crowd then
		crowd:Reset()
	end
end

function NPC.StopMotion(item: Types.Item): ()
	if item.pushConnection then item.pushConnection:Disconnect(); item.pushConnection = nil end
	StopTrack(item.walkTrack)
	StopTrack(item.idleTrack)
	StopTrack(item.runTrack)
	item.staggerEnds = nil
	item.fleeUntil = nil
	item.fleeHeading = nil
	item.panicUntil = nil
	item.panicHeading = nil
	item.walkTarget = nil
	item.stuckAnchor = nil
	item.stuckSince = nil
	item.runRequestedAt = nil
	if crowd then
		crowd:RemoveAgent(item.id)
	end
	item.poiId = nil
	item.poiLookDir = nil
	item.model:SetAttribute("StreetLookStarted", nil)
end

function NPC.Spawn(runtime: Folder, items: { [string]: Types.Item }): Types.Item?
	local point: Vector3? = nil
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { Scene.Deck, runtime }
	overlap.MaxParts = 1
	overlap.RespectCanCollide = true
	local preferredSpacing = Config.NpcTargetMinSpacing or 7
	for attempt = 1, 24 do
		local candidate = Scene.StreetFloor(Scene.StreetPoint(random))
		if not candidate then continue end
		local minSpacing = if attempt <= 16 then preferredSpacing else 5
		local occupied = false
		for _, item in items do
			if item.model.PrimaryPart and (item.model.PrimaryPart.Position - candidate).Magnitude < minSpacing then
				occupied = true
				break
			end
		end
		if #workspace:GetPartBoundsInBox(CFrame.new(candidate + Vector3.new(0, 3, 0)), Vector3.new(3, 5.5, 3), overlap) > 0 then
			occupied = true
		end
		if not occupied then
			point = candidate
			break
		end
	end
	if not point then
		return nil
	end
	local model = ModelTemplates.WaitCharacter("WhiteR15-People"):Clone()
	local id = HttpService:GenerateGUID(false)
	model.Name = "WhiteNPC"
	model:SetAttribute("ItemId", id)
	model:SetAttribute("GroundPresentation", Physics.GroundRootEnabled)
	model:PivotTo(CFrame.new(point + Vector3.yAxis * RootHeight))
	model.Parent = runtime
	Ragdoll.Setup(model)
	Ragdoll.SetMode(model, "Walking")
	local item: Types.Item = {
		id = id,
		kind = "Body",
		stage = "Unpainted",
		location = "Street",
		version = 1,
		model = model,
		holder = nil,
		hits = 0,
		hp = Config.StreetNpcMaxHp,
		maxHp = Config.StreetNpcMaxHp,
		covered = {},
		strokes = {},
		strokePoints = 0,
		area = 0,
		totalArea = Surface.Total(model),
		progress = 0,
		paintSeconds = 0,
		streetSlot = true,
		nextWalk = 0,
		streetSafePoint = point,
		carryWeld = nil,
		walkTrack = nil,
	}
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	if not animator.Parent then animator.Parent = humanoid end
	item.walkTrack = LoadTrack(animator, Config.WalkAnimation, Enum.AnimationPriority.Movement)
	item.runTrack = LoadTrack(animator, Config.NpcRunAnimation, Enum.AnimationPriority.Movement)
	item.idleTrack = LoadTrack(animator, Config.IdleAnimation, Enum.AnimationPriority.Idle)
	SetMotion(item, "Idle")
	return item
end

local function MoveTo(item: Types.Item, humanoid: Humanoid, target: Vector3): ()
	item.walkTarget = target
	humanoid:MoveTo(target)
end

local function FallbackFleeTarget(position: Vector3, heading: Vector3): (Vector3?, Vector3)
	for _, degrees in FleeAngles do
		local direction = CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(heading)
		for _, distance in FleeDistances do
			local desired = position + direction * distance - Vector3.yAxis * RootHeight
			local target = Scene.StreetRoute(position, desired)
			if target then return target, direction end
		end
	end
	return nil, heading
end

local function PlanFleeTarget(item: Types.Item, position: Vector3, heading: Vector3, items: { [string]: Types.Item }?): (Vector3?, Vector3)
	if crowd and items then
		return crowd:ChooseFleeTarget(item.id, position, heading, items, random, Scene.StreetRoute)
	end
	return FallbackFleeTarget(position, heading)
end

local function Recover(item: Types.Item, root: BasePart, humanoid: Humanoid, now: number): ()
	local position = root.Position
	local target = Scene.ClampToStreetWalkZones(position) or item.streetSafePoint
	if not target then
		target = Scene.StreetFloor(Scene.StreetPoint(random))
	end
	if not target then
		humanoid:MoveTo(position)
		return
	end
	if Scene.IsInStreetWalkZones(position, RecoveryTolerance) and Scene.StreetRoute(position, target, true) then
		MoveTo(item, humanoid, target)
		return
	end
	humanoid:MoveTo(position)
	item.model:PivotTo(CFrame.new(target + Vector3.yAxis * RootHeight) * root.CFrame.Rotation)
	root.AssemblyLinearVelocity = Vector3.zero
	item.nextWalk = now
	item.walkTarget = nil
	item.stuckAnchor = nil
	item.stuckSince = nil
end

local function FaceDirection(model: Model, root: BasePart, dir: Vector3): ()
	local flat = Flat(dir)
	if flat.Magnitude <= 0.01 then return end
	local targetFrame = CFrame.lookAlong(root.Position, flat.Unit)
	model:PivotTo(targetFrame)
end

local function NearestWalkerDist(item: Types.Item, position: Vector3, items: { [string]: Types.Item }?): number
	if not items then return math.huge end
	local minDist = math.huge
	for otherId, other in items do
		if otherId ~= item.id and other.kind == "Body" and other.location == "Street" and other.hits < Config.StunHits then
			local otherRoot = other.model.PrimaryPart
			if otherRoot then
				local d = Flat(otherRoot.Position - position).Magnitude
				if d < minDist then minDist = d end
			end
		end
	end
	return minDist
end

local function CheckStuck(item: Types.Item, position: Vector3, now: number): boolean
	if not item.walkTarget then
		item.stuckAnchor = nil
		item.stuckSince = nil
		return false
	end
	local anchor = item.stuckAnchor
	if not anchor or not item.stuckSince then
		item.stuckAnchor = position
		item.stuckSince = now
		return false
	end
	if Flat(position - anchor).Magnitude >= StuckCheckDistance then
		item.stuckAnchor = position
		item.stuckSince = now
		return false
	end
	local stuckLimit = Config.NpcStuckSeconds or 1.2
	if now - item.stuckSince >= stuckLimit then
		item.stuckAnchor = position
		item.stuckSince = now
		return true
	end
	return false
end

local function PlanAgent(item: Types.Item, items: { [string]: Types.Item }?, now: number): (StreetCrowd.AgentGoal?, boolean)
	if item.location ~= "Street" or item.hits >= Config.StunHits then
		return nil, false
	end
	local root = item.model.PrimaryPart
	local humanoid = item.model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return nil, false
	end
	if item.staggerEnds then
		if now < item.staggerEnds then return nil, false end
		item.staggerEnds = nil
		if item.pushConnection then
			item.pushConnection:Disconnect()
			item.pushConnection = nil
			root.AssemblyLinearVelocity = Vector3.yAxis * root.AssemblyLinearVelocity.Y
		end
	end

	local position = root.Position
	local velocity = Flat(root.AssemblyLinearVelocity)
	local speed = velocity.Magnitude

	local fleeing = item.fleeUntil ~= nil and now < item.fleeUntil
	if not fleeing and item.fleeUntil then
		item.fleeUntil, item.fleeHeading, item.walkTarget = nil, nil, nil
		item.stuckAnchor, item.stuckSince = nil, nil
		humanoid:MoveTo(position)
		item.nextWalk = now
	end

	local panicking = not fleeing and item.panicUntil ~= nil and now < item.panicUntil
	if not panicking and item.panicUntil then
		item.panicUntil, item.panicHeading = nil, nil
		if not fleeing then
			item.walkTarget = nil
			item.stuckAnchor, item.stuckSince = nil, nil
			humanoid:MoveTo(position)
			item.nextWalk = now
		end
	end

	local escaping = fleeing or panicking
	local desiredMoveSpeed = if fleeing then Config.NpcFleeSpeed elseif panicking then (Config.NpcPanicSpeed or 11.0) else Config.NpcStrollSpeed

	if not Scene.IsInStreetWalkZones(position) then
		ClearPoi(item, now, false)
		humanoid.WalkSpeed = desiredMoveSpeed
		SetMotion(item, if escaping then "Fleeing" else "Walking")
		Recover(item, root, humanoid, now)
		PlayLocomotion(item, speed, escaping, now)
		return nil, false
	end

	local arriveRadius = if item.poiId then PoiArriveRadius else WaypointRadius
	local target = item.walkTarget
	local arrived = target ~= nil and Flat(target - position).Magnitude <= arriveRadius
	if not arrived and target and not escaping and item.motionState ~= "LookAround" and CheckStuck(item, position, now) then
		arrived = true
		ClearPoi(item, now, false)
		item.walkTarget = nil
	elseif escaping and target and CheckStuck(item, position, now) then
		item.nextWalk = now
	end

	if escaping then
		ClearPoi(item, now, false)
		SetMotion(item, "Fleeing")
		if now >= item.nextWalk or arrived or not item.walkTarget then
			local heading = (if fleeing then item.fleeHeading else item.panicHeading) or Flat(root.CFrame.LookVector)
			if heading.Magnitude <= 0.01 then heading = Vector3.xAxis else heading = heading.Unit end
			local destination, nextHeading = PlanFleeTarget(item, position, heading, items)
			if fleeing then
				item.fleeHeading = nextHeading
			else
				item.panicHeading = nextHeading
			end
			item.nextWalk = now + Config.NpcFleeReplanSeconds
			if destination then
				item.walkTarget = destination
				item.streetSafePoint = destination
				if not items then
					MoveTo(item, humanoid, destination)
				end
			else
				item.walkTarget = nil
				humanoid:MoveTo(position)
			end
		end
		if item.walkTarget then
			return {
				position = position,
				velocity = velocity,
				target = item.walkTarget,
				desiredSpeed = desiredMoveSpeed,
				maxSpeed = desiredMoveSpeed,
				priority = if fleeing then 0.85 else 0.70,
				elevation = position.Y - RootHeight,
				moving = true,
			}, true
		end
		humanoid.WalkSpeed = desiredMoveSpeed
		if speed > Config.WalkExitSpeed then
			PlayLocomotion(item, speed, true, now)
		else
			StopTrack(item.walkTrack)
			StopTrack(item.runTrack)
		end
		return nil, false
	end

	if now >= item.nextWalk or arrived then
		if arrived and item.poiId and item.motionState ~= "LookAround" then
			local lookDir = item.poiLookDir
			item.walkTarget = nil
			item.stuckAnchor, item.stuckSince = nil, nil
			humanoid:MoveTo(position)
			if lookDir then
				FaceDirection(item.model, root, lookDir)
			end
			local poiMin = Config.NpcPoiDurationMin or 2.5
			local poiMax = Config.NpcPoiDurationMax or 4.5
			item.nextWalk = now + random:NextNumber(poiMin, poiMax)
			item.model:SetAttribute("StreetLookStarted", if random:NextNumber() < 0.5 then -now else now)
			SetMotion(item, "LookAround")
			return {
				position = position,
				velocity = velocity,
				target = position,
				desiredSpeed = 0,
				maxSpeed = 1.6,
				priority = 0.25,
				elevation = position.Y - RootHeight,
				moving = false,
			}, false
		end

		if item.motionState == "LookAround" then
			ClearPoi(item, now, true)
			SetMotion(item, "Idle")
		end
		item.walkTarget = nil
		item.stuckAnchor, item.stuckSince = nil, nil

		local nearNeighbor = NearestWalkerDist(item, position, items)
		local canPauseHere = item.motionState ~= "LookAround"
			and nearNeighbor > (Config.NpcRvoRadius or 1.8) * 2.2
			and random:NextNumber() < Config.NpcLookAroundChance
			and now > 0
		if canPauseHere and not items then
			-- 兼容单白膜历史状态机测试行为
		end
		if canPauseHere then
			humanoid:MoveTo(position)
			item.nextWalk = now + random:NextNumber(Config.NpcLookAroundDurationMin, Config.NpcLookAroundDurationMax)
			item.model:SetAttribute("StreetLookStarted", if random:NextNumber() < 0.5 then -now else now)
			SetMotion(item, "LookAround")
			return {
				position = position,
				velocity = velocity,
				target = position,
				desiredSpeed = 0,
				maxSpeed = 1.6,
				priority = 0.25,
				elevation = position.Y - RootHeight,
				moving = false,
			}, false
		end

		local destination: Vector3? = nil
		if crowd and items and Scene.GetStreetInterestPoints and random:NextNumber() < (Config.NpcPoiChance or 0.3) then
			local poi = crowd:ReservePoi(item.id, position, item.lastPoiId, Scene.GetStreetInterestPoints(), items, now, random, Scene.StreetRoute)
			if poi then
				local routed = Scene.StreetRoute(position, poi.position)
				if routed then
					item.poiId = poi.id
					item.poiLookDir = poi.lookDirection
					destination = routed
				else
					crowd:ReleasePoi(item.id, now, false)
				end
			end
		end

		if not destination then
			if crowd and items then
				destination = crowd:ChooseStrollTarget(item.id, position, items, random, Scene.StreetPoint, Scene.StreetRoute)
			else
				for _ = 1, 8 do
					local sample = Scene.StreetPoint(random)
					local offset = Flat(sample - position)
					local goal = if offset.Magnitude > 15
						then position + offset.Unit * 15 - Vector3.yAxis * RootHeight
						else sample
					local candidate = Scene.StreetRoute(position, goal)
					if candidate and Flat(candidate - position).Magnitude > WaypointRadius then
						destination = candidate
						break
					end
				end
			end
		end

		if destination then
			item.walkTarget = destination
			item.streetSafePoint = destination
			item.stuckAnchor = position
			item.stuckSince = now
			local travelDist = Flat(destination - position).Magnitude
			local travelBudget = travelDist / math.max(Config.NpcStrollSpeed, 1) + 4.0
			item.nextWalk = now + if items then math.clamp(travelBudget, 4.0, 32.0) else random:NextNumber(2, 4)
			if not items then
				MoveTo(item, humanoid, destination)
			end
		else
			humanoid:MoveTo(position)
			item.nextWalk = now + random:NextNumber(1.5, 3.0)
		end
	end

	if item.motionState == "LookAround" then
		return {
			position = position,
			velocity = velocity,
			target = position,
			desiredSpeed = 0,
			maxSpeed = 1.6,
			priority = 0.25,
			elevation = position.Y - RootHeight,
			moving = false,
		}, false
	end

	if item.walkTarget then
		return {
			position = position,
			velocity = velocity,
			target = item.walkTarget,
			desiredSpeed = Config.NpcStrollSpeed,
			maxSpeed = Config.NpcStrollSpeed,
			priority = 0.50,
			elevation = position.Y - RootHeight,
			moving = true,
		}, false
	end

	humanoid.WalkSpeed = Config.NpcStrollSpeed
	local walking = if item.motionState == "Walking" then speed > Config.WalkExitSpeed else speed > Config.WalkEnterSpeed
	SetMotion(item, if walking then "Walking" else "Idle")
	if walking then PlayLocomotion(item, speed, false, now) end
	return nil, false
end

function NPC.Update(item: Types.Item, now: number): ()
	local goal, escaping = PlanAgent(item, nil, now)
	if not goal then return end
	local root = item.model.PrimaryPart
	local humanoid = item.model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then return end
	local speed = Flat(root.AssemblyLinearVelocity).Magnitude
	if goal.moving then
		humanoid.WalkSpeed = goal.maxSpeed
		MoveTo(item, humanoid, goal.target)
		local walking = if item.motionState == "Walking" then speed > Config.WalkExitSpeed else speed > Config.WalkEnterSpeed
		if not escaping then
			SetMotion(item, if walking then "Walking" else "Idle")
			if walking then PlayLocomotion(item, speed, false, now) end
		else
			PlayLocomotion(item, speed, true, now)
		end
	else
		humanoid.WalkSpeed = Config.NpcStrollSpeed
	end
end

function NPC.StepCrowd(
	items: { [string]: Types.Item },
	obstacles: { StreetCrowd.DynamicObstacle },
	now: number,
	dt: number
): ()
	if not crowd then
		for _, item in items do
			if item.kind == "Body" then
				NPC.Update(item, now)
			end
		end
		return
	end
	local goals: { [string]: StreetCrowd.AgentGoal } = {}
	local escapingById: { [string]: boolean } = {}
	for id, item in items do
		if item.kind == "Body" then
			local goal, escaping = PlanAgent(item, items, now)
			if goal then
				goals[id] = goal
				escapingById[id] = escaping
			end
		end
	end
	local velocities = crowd:Step(items, goals, obstacles, now, dt, Scene.StreetBoundaryPush)
	for id, goal in goals do
		local item = items[id]
		if not item then continue end
		local root = item.model.PrimaryPart
		local humanoid = item.model:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid then continue end
		local vel = velocities[id] or Vector3.zero
		local steeredSpeed = vel.Magnitude
		local actualSpeed = Flat(root.AssemblyLinearVelocity).Magnitude
		local escaping = escapingById[id] == true
		if goal.moving then
			if steeredSpeed > 0.2 then
				local horizon = math.clamp(steeredSpeed * 0.45, 2.5, 6.0)
				local toGoal = Flat(goal.target - goal.position)
				local steerTarget: Vector3
				if toGoal.Magnitude <= horizon and vel.Unit:Dot(if toGoal.Magnitude > 0.01 then toGoal.Unit else vel.Unit) > 0.7 then
					steerTarget = goal.target
				else
					steerTarget = goal.position + vel.Unit * horizon - Vector3.yAxis * RootHeight
					if not Scene.IsInStreetWalkZones(steerTarget) then
						steerTarget = Scene.ClampToStreetWalkZones(steerTarget) or goal.target
					end
				end
				humanoid.WalkSpeed = math.clamp(steeredSpeed, 0.5, goal.maxSpeed)
				humanoid:MoveTo(steerTarget)
			else
				humanoid.WalkSpeed = goal.maxSpeed
				humanoid:MoveTo(goal.position)
			end
			if escaping then
				if steeredSpeed > 0.2 or actualSpeed > Config.WalkExitSpeed then
					PlayLocomotion(item, math.max(actualSpeed, steeredSpeed), true, now)
				else
					StopTrack(item.walkTrack)
					StopTrack(item.runTrack)
				end
			else
				local walking = if item.motionState == "Walking" then actualSpeed > Config.WalkExitSpeed else actualSpeed > Config.WalkEnterSpeed or steeredSpeed > Config.WalkEnterSpeed
				SetMotion(item, if walking then "Walking" else "Idle")
				if walking then
					PlayLocomotion(item, math.max(actualSpeed, steeredSpeed * 0.8), false, now)
				end
			end
		else
			-- LookAround 让位：平时站定不动，有行人近距离逼近时轻微侧让
			if steeredSpeed > YieldSpeedThreshold then
				local stepTarget = goal.position + vel.Unit * 2.0 - Vector3.yAxis * RootHeight
				if not Scene.IsInStreetWalkZones(stepTarget) then
					stepTarget = Scene.ClampToStreetWalkZones(stepTarget) or goal.position
				end
				humanoid.WalkSpeed = math.min(steeredSpeed, 2.0)
				humanoid:MoveTo(stepTarget)
			else
				humanoid.WalkSpeed = 0
				humanoid:MoveTo(goal.position)
			end
		end
	end
end

-- 在短硬直内给权威装配施加衰减的水平速度，碰撞和实际位移由物理解算。
local function Push(item: Types.Item, root: BasePart, direction: Vector3)
	local model = item.model
	local cast = RaycastParams.new()
	cast.FilterType = Enum.RaycastFilterType.Exclude
	cast.FilterDescendantsInstances = { model }
	cast.RespectCanCollide = true
	cast.CollisionGroup = root.CollisionGroup
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { model }
	overlap.RespectCanCollide = true
	overlap.CollisionGroup = root.CollisionGroup
	overlap.MaxParts = 1
	local parts: { BasePart } = {}
	for _, name in { "Head", "UpperTorso", "LowerTorso" } do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then table.insert(parts, part) end
	end
	local elapsed = 0
	local duration = Config.NpcHitStaggerSeconds
	local function SetHorizontalVelocity(velocity: Vector3): ()
		root.AssemblyLinearVelocity = velocity + Vector3.yAxis * root.AssemblyLinearVelocity.Y
	end
	local function Finish(stop: boolean): ()
		if item.pushConnection then item.pushConnection:Disconnect(); item.pushConnection = nil end
		if stop then SetHorizontalVelocity(Vector3.zero) end
	end
	item.pushConnection = RunService.PreSimulation:Connect(function(dt: number)
		if item.location ~= "Street" or not model.Parent or root.Parent ~= model or item.hits >= Config.StunHits then
			Finish(false)
			return
		end
		if dt <= 0 then return end
		local previous = 1 - elapsed / duration
		elapsed = math.min(elapsed + dt, duration)
		local remaining = 1 - elapsed / duration
		local distance = Config.HitPushDistance * (previous ^ 2 - remaining ^ 2)
		if distance <= 0 then Finish(true); return end
		for _, part in parts do
			local size = part.Size * 0.94
			local hit = workspace:Blockcast(part.CFrame, size, direction * distance, cast)
			if hit then distance = math.max(0, hit.Distance - 0.03) end
			if distance <= 0 or #workspace:GetPartBoundsInBox(part.CFrame + direction * distance, size, overlap) > 0 then
				Finish(true)
				return
			end
		end
		if not Scene.IsInStreetWalkZones(root.Position + direction * distance) then Finish(true); return end
		SetHorizontalVelocity(direction * (distance / dt))
	end)
end

function NPC.Hit(item: Types.Item, direction: Vector3?, damage: number?, groundTravel: number?, attackerPosition: Vector3?, items: { [string]: Types.Item }?): ()
	item.maxHp = item.maxHp or Config.StreetNpcMaxHp
	local hp = PersonalRules.RemainingNpcHp(item.hp, item.hits, damage or Config.BruteDamage)
	item.hp = hp
	-- 保留已有击晕和表现协议的三档状态，血条读取实际 HP。
	item.hits = Config.StunHits - math.ceil(hp / Config.BruteDamage)
	item.version += 1
	local humanoid = item.model:FindFirstChildOfClass("Humanoid")
	local root = item.model.PrimaryPart
	local hitNow = workspace:GetServerTimeNow()
	local incidentPos = if root then root.Position else nil
	if humanoid and root then humanoid:MoveTo(root.Position) end
	NPC.StopMotion(item)
	if crowd and incidentPos then
		crowd:NotifyIncident(incidentPos, item.id, items, hitNow, random)
	end
	if item.hits >= Config.StunHits then
		SetMotion(item, "Down")
		if Physics.GroundRootEnabled and root then
			local axis = direction or root.CFrame.LookVector
			Ground.Place(item, axis, root.AssemblyLinearVelocity + axis * Config.StunImpulseSpeed, groundTravel)
			return
		end
		Ragdoll.SetMode(item.model, "Loose")
		local torso = item.model:FindFirstChild("UpperTorso")
		if direction and torso and torso:IsA("BasePart") then
			local horizontal = Flat(direction)
			if horizontal.Magnitude > 0.01 then torso:ApplyImpulse(horizontal.Unit * Config.StunImpulseSpeed * torso.AssemblyMass) end
		end
	elseif humanoid and root then
		local now = hitNow
		local push = if direction then Flat(direction) else Vector3.zero
		local away = if attackerPosition then Flat(root.Position - attackerPosition) else push
		if away.Magnitude <= 0.01 then away = if push.Magnitude > 0.01 then push else Flat(root.CFrame.LookVector) end
		item.fleeHeading = if away.Magnitude > 0.01 then away.Unit else Vector3.xAxis
		item.fleeUntil = now + Config.NpcFleeDuration
		local staggerEnds = now + Config.NpcHitStaggerSeconds
		item.staggerEnds, item.nextWalk = staggerEnds, staggerEnds
		SetMotion(item, "Hit")
		humanoid.WalkSpeed = 0
		if push.Magnitude > 0.01 then Push(item, root, push.Unit) end
	end
end

return NPC
