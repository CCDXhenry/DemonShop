-- 街道白膜群体调度：外部复用 Core/RVO 避让、密度感知选点、橱窗驻足锁与受惊扩散
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Scripts.Shared.GameConfig)
local Types = require(ReplicatedStorage.Scripts.Shared.GameTypes)
local RVO = require(ReplicatedStorage.Core.Scripts.Shared.RVO)
local Scene = require(script.Parent.Scene)

local StreetCrowd = {}
StreetCrowd.__index = StreetCrowd

export type DynamicObstacle = {
	id: string,
	position: Vector3,
	velocity: Vector3,
	radius: number,
	locked: boolean,
}

export type AgentGoal = {
	position: Vector3,
	velocity: Vector3,
	target: Vector3,
	desiredSpeed: number,
	maxSpeed: number,
	priority: number,
	elevation: number,
	moving: boolean,
}

export type RouteCheck = (Vector3, Vector3) -> Vector3?
export type PointSampler = (Random) -> Vector3
export type BoundaryPushFn = (Vector3, number?) -> Vector3

export type Crowd = typeof(setmetatable(
	{} :: {
		sim: RVO.RVOSimulator,
		npcAgents: { [string]: RVO.AgentObject },
		proxyAgents: { [string]: RVO.AgentObject },
		poiOccupant: { [string]: string },
		itemPoi: { [string]: string },
		poiCooldownUntil: { [string]: number },
		lastItems: { [string]: Types.Item }?,
		random: Random,
	},
	StreetCrowd
))

local RootStandingOffset = 3.0
local AgentVerticalHeight = 6.0
local PoiCrowdCheckRadius = 4.5
local FleeAngles = { 0, 35, -35, 70, -70, 110, -110, 150, -150, 180 }
local FleeDistances = { 16, 10, 5, 2.5 }

local function Flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function FlatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function IsActiveStreetWalker(item: Types.Item): boolean
	return item.kind == "Body" and item.location == "Street" and item.hits < Config.StunHits and item.model.Parent ~= nil
end

local function IsStreetDownedBody(item: Types.Item): boolean
	return item.kind == "Body" and item.location == "Street" and item.hits >= Config.StunHits and item.model.Parent ~= nil
end

function StreetCrowd.new(rvoOverride: any?): Crowd
	local rvo = rvoOverride or RVO
	local defaults: RVO.AgentDefaults = {
		radius = Config.NpcRvoRadius,
		height = AgentVerticalHeight,
		agentTimeHorizon = Config.NpcRvoTimeHorizon,
		obstacleTimeHorizon = Config.NpcRvoTimeHorizon,
		maxNeighbours = Config.NpcRvoMaxNeighbours,
		maxSpeed = Config.NpcFleeSpeed,
		priority = 0.5,
		layer = rvo.RVOLayerDefaultAgent,
		collidesWith = rvo.RVOLayerAll,
	}
	local sim = rvo.RVOSimulator.new(Config.NpcRvoSymmetryBias, rvo.MovementPlaneXZ, defaults)
	sim:SetTimeStep(Config.NpcCrowdStepInterval)
	return setmetatable({
		sim = sim,
		npcAgents = {},
		proxyAgents = {},
		poiOccupant = {},
		itemPoi = {},
		poiCooldownUntil = {},
		lastItems = nil,
		random = Random.new(),
	}, StreetCrowd)
end

function StreetCrowd.Reset(self: Crowd): ()
	self.sim:ClearAgents()
	table.clear(self.npcAgents)
	table.clear(self.proxyAgents)
	table.clear(self.poiOccupant)
	table.clear(self.itemPoi)
	table.clear(self.poiCooldownUntil)
	self.lastItems = nil
end

function StreetCrowd.ReleasePoi(self: Crowd, itemId: string, now: number?, applyCooldown: boolean?): ()
	local poiId = self.itemPoi[itemId]
	if not poiId then
		return
	end
	self.itemPoi[itemId] = nil
	if self.poiOccupant[poiId] == itemId then
		self.poiOccupant[poiId] = nil
	end
	if applyCooldown and now then
		self.poiCooldownUntil[poiId] = now + Config.NpcPoiCooldownSeconds
	end
end

function StreetCrowd.RemoveAgent(self: Crowd, itemId: string, now: number?, applyCooldown: boolean?): ()
	self:ReleasePoi(itemId, now, applyCooldown)
	local agent = self.npcAgents[itemId]
	if agent then
		self.npcAgents[itemId] = nil
		if agent.simulator == self.sim then
			self.sim:RemoveAgent(agent)
		end
	end
end

function StreetCrowd.ReservePoi(
	self: Crowd,
	itemId: string,
	position: Vector3,
	lastPoiId: string?,
	points: { Scene.InterestPoint },
	items: { [string]: Types.Item },
	now: number,
	random: Random,
	routeCheck: RouteCheck
): Scene.InterestPoint?
	if #points == 0 then
		return nil
	end
	self:ReleasePoi(itemId, now, false)
	local candidates: { { poi: Scene.InterestPoint, weight: number } } = {}
	local totalWeight = 0
	for _, poi in points do
		local occupant = self.poiOccupant[poi.id]
		if occupant and occupant ~= itemId then
			continue
		end
		if poi.id == lastPoiId then
			continue
		end
		local cooldown = self.poiCooldownUntil[poi.id]
		if cooldown and now < cooldown then
			continue
		end
		local dist = FlatDist(position, poi.position)
		if dist < 2 or dist > 65 then
			continue
		end
		local crowded = false
		for otherId, other in items do
			if otherId ~= itemId and IsActiveStreetWalker(other) then
				local otherRoot = other.model.PrimaryPart
				if otherRoot and FlatDist(otherRoot.Position, poi.position) < PoiCrowdCheckRadius then
					crowded = true
					break
				end
			end
		end
		if crowded then
			continue
		end
		if not routeCheck(position, poi.position) then
			continue
		end
		local distScore = 1 / (1 + math.abs(dist - 22) * 0.06)
		totalWeight += distScore
		table.insert(candidates, { poi = poi, weight = distScore })
	end
	if #candidates == 0 then
		return nil
	end
	local pick = random:NextNumber(0, totalWeight)
	local chosen = candidates[#candidates].poi
	for _, candidate in candidates do
		pick -= candidate.weight
		if pick <= 0 then
			chosen = candidate.poi
			break
		end
	end
	self.poiOccupant[chosen.id] = itemId
	self.itemPoi[itemId] = chosen.id
	return chosen
end

local function NearestSpacing(candidate: Vector3, selfId: string, items: { [string]: Types.Item }): number
	local minDist = math.huge
	for otherId, other in items do
		if otherId == selfId or not IsActiveStreetWalker(other) then
			continue
		end
		local root = other.model.PrimaryPart
		if root then
			local d = FlatDist(candidate, root.Position)
			if d < minDist then
				minDist = d
			end
		end
		if other.walkTarget then
			local td = FlatDist(candidate, other.walkTarget)
			if td < minDist then
				minDist = td
			end
		end
	end
	return minDist
end

function StreetCrowd.ChooseStrollTarget(
	self: Crowd,
	itemId: string,
	position: Vector3,
	items: { [string]: Types.Item },
	random: Random,
	samplePoint: PointSampler,
	routeCheck: RouteCheck
): Vector3?
	local bestTarget: Vector3? = nil
	local bestScore = -math.huge
	local candidateCount = Config.NpcTargetCandidateCount
	local minSpacing = Config.NpcTargetMinSpacing
	local minTravel = Config.NpcStrollMinDistance
	for _ = 1, candidateCount do
		local raw = samplePoint(random)
		local dest = routeCheck(position, raw)
		if not dest then
			continue
		end
		local travel = FlatDist(position, dest)
		if travel <= 1.5 then
			continue
		end
		local spacing = NearestSpacing(dest, itemId, items)
		local score = if spacing < minSpacing
			then -40 + spacing * 3
			else math.min(spacing, 18) * 1.4
		if travel < minTravel then
			score -= (minTravel - travel) * 0.8
		end
		score += random:NextNumber(0, 4)
		if score > bestScore then
			bestScore = score
			bestTarget = dest
		end
	end
	return bestTarget
end

function StreetCrowd.ChooseFleeTarget(
	self: Crowd,
	itemId: string,
	position: Vector3,
	heading: Vector3,
	items: { [string]: Types.Item },
	random: Random,
	routeCheck: RouteCheck
): (Vector3?, Vector3)
	local baseHeading = if Flat(heading).Magnitude > 0.01 then Flat(heading).Unit else Vector3.xAxis
	local bestTarget: Vector3? = nil
	local bestDir = baseHeading
	local bestScore = -math.huge
	local foundPreferred = false
	for _, degrees in FleeAngles do
		local dir = CFrame.Angles(0, math.rad(degrees), 0):VectorToWorldSpace(baseHeading)
		for _, dist in FleeDistances do
			local desired = position + dir * dist - Vector3.yAxis * 3.2
			local target = routeCheck(position, desired)
			if target then
				local spacing = NearestSpacing(target, itemId, items)
				local score = dist * 0.9 - math.abs(degrees) * 0.14
				if spacing < Config.NpcRvoRadius * 2.2 then
					score -= 10
				else
					score += math.min(spacing, 12) * 0.45
				end
				score += random:NextNumber(0, 1.2)
				if score > bestScore then
					bestScore = score
					bestTarget = target
					bestDir = dir
				end
				if degrees == 0 and dist >= 8 and spacing >= Config.NpcRvoRadius * 2.2 then
					foundPreferred = true
					break
				end
			end
		end
		if foundPreferred then
			break
		end
	end
	return bestTarget, bestDir
end

function StreetCrowd.NotifyIncident(
	self: Crowd,
	incidentPos: Vector3,
	victimId: string,
	items: { [string]: Types.Item }?,
	now: number,
	random: Random?
): ()
	local pool: { [string]: Types.Item }? = items or self.lastItems
	if not pool then
		return
	end
	local itemsMap = pool :: { [string]: Types.Item }
	local rng = random or self.random
	local radius = Config.NpcPanicRadius
	local victimPos = Flat(incidentPos)
	local index = 0
	for id, other in itemsMap do
		if id == victimId or not IsActiveStreetWalker(other) then
			continue
		end
		if other.staggerEnds and now < other.staggerEnds then
			continue
		end
		if other.fleeUntil and now < other.fleeUntil then
			continue
		end
		local root = other.model.PrimaryPart
		if not root then
			continue
		end
		local offset = Flat(root.Position) - victimPos
		local dist = offset.Magnitude
		if dist <= radius and dist > 0.001 then
			index += 1
			self:ReleasePoi(id, now, false)
			other.poiId = nil
			other.poiLookDir = nil
			other.walkTarget = nil
			other.stuckAnchor = nil
			other.stuckSince = nil
			local spreadSign = if index % 2 == 0 then 1 else -1
			local spreadDeg = spreadSign * rng:NextNumber(8, 28)
			local away = CFrame.Angles(0, math.rad(spreadDeg), 0):VectorToWorldSpace(offset.Unit)
			other.panicHeading = away
			other.panicUntil = now + rng:NextNumber(Config.NpcPanicDurationMin, Config.NpcPanicDurationMax)
			other.nextWalk = now
		end
	end
end

function StreetCrowd.Step(
	self: Crowd,
	items: { [string]: Types.Item },
	goals: { [string]: AgentGoal },
	obstacles: { DynamicObstacle },
	now: number,
	dt: number,
	boundaryPush: BoundaryPushFn?
): { [string]: Vector3 }
	self.lastItems = items
	local sim = self.sim

	for id, agent in self.npcAgents do
		if not goals[id] then
			self.npcAgents[id] = nil
			if agent.simulator == sim then
				sim:RemoveAgent(agent)
			end
			self:ReleasePoi(id, now, false)
		end
	end

	for id, goal in goals do
		local agent: RVO.AgentObject
		local existing = self.npcAgents[id]
		if existing then
			agent = existing
		else
			local created = sim:AddAgentFromWorld(Vector3.new(goal.position.X, goal.elevation, goal.position.Z))
			created.Radius = Config.NpcRvoRadius
			created.Height = AgentVerticalHeight
			created.AgentTimeHorizon = Config.NpcRvoTimeHorizon
			created.ObstacleTimeHorizon = Config.NpcRvoTimeHorizon
			created.MaxNeighbours = Config.NpcRvoMaxNeighbours
			self.npcAgents[id] = created
			agent = created
		end
		local pos3 = Vector3.new(goal.position.X, goal.elevation, goal.position.Z)
		sim:SetAgentPositionFromWorld(agent, pos3)
		sim:SetAgentVelocityFromWorld(agent, Flat(goal.velocity))
		agent.Priority = goal.priority
		agent.Locked = false
		if goal.moving and goal.desiredSpeed > 0 then
			sim:SetAgentTargetFromWorld(agent, goal.target, goal.desiredSpeed, goal.maxSpeed)
		else
			sim:SetAgentTargetFromWorld(agent, pos3, 0, goal.maxSpeed)
		end
	end

	local activeProxyKeys: { [string]: boolean } = {}
	local function SyncProxy(key: string, pos: Vector3, elevation: number, vel: Vector3, radius: number, locked: boolean): ()
		activeProxyKeys[key] = true
		local proxy: RVO.AgentObject
		local existingProxy = self.proxyAgents[key]
		if existingProxy then
			proxy = existingProxy
		else
			local createdProxy = sim:AddAgentFromWorld(Vector3.new(pos.X, elevation, pos.Z))
			createdProxy.Height = AgentVerticalHeight
			createdProxy.MaxNeighbours = 4
			self.proxyAgents[key] = createdProxy
			proxy = createdProxy
		end
		proxy.Radius = radius
		proxy.Priority = 1.0
		sim:SetAgentPositionFromWorld(proxy, Vector3.new(pos.X, elevation, pos.Z))
		local flatVel = Flat(vel)
		if locked or flatVel.Magnitude < 0.25 then
			proxy.Locked = true
			sim:SetAgentTargetFromWorld(proxy, Vector3.new(pos.X, elevation, pos.Z), 0, 0)
		else
			proxy.Locked = false
			sim:ForceSetAgentVelocityFromWorld(proxy, flatVel)
		end
	end

	for _, obs in obstacles do
		SyncProxy("obs:" .. obs.id, obs.position, obs.position.Y - RootStandingOffset, obs.velocity, obs.radius, obs.locked)
	end

	for id, item in items do
		if IsStreetDownedBody(item) then
			local torso = item.model:FindFirstChild("UpperTorso") or item.model.PrimaryPart
			if torso and torso:IsA("BasePart") then
				SyncProxy("down:" .. id, torso.Position, torso.Position.Y - 1.5, Vector3.zero, Config.NpcDownedBodyRadius, true)
			end
		end
	end

	for key, proxy in self.proxyAgents do
		if not activeProxyKeys[key] then
			self.proxyAgents[key] = nil
			if proxy.simulator == sim then
				sim:RemoveAgent(proxy)
			end
		end
	end

	local stepDt = math.clamp(dt, 1 / 120, 0.2)
	sim:DoStep(stepDt)

	local pushFn: BoundaryPushFn = boundaryPush or Scene.StreetBoundaryPush
	local outputs: { [string]: Vector3 } = {}
	for id, goal in goals do
		local agent = self.npcAgents[id]
		if not agent then
			outputs[id] = Vector3.zero
			continue
		end
		local vel = sim:GetAgentVelocityWorld(agent, 0)
		if vel.X ~= vel.X or vel.Z ~= vel.Z then
			vel = Vector3.zero
		end
		local push = pushFn(goal.position, 1.4)
		if push.Magnitude > 0.01 then
			local outward = vel:Dot(-push)
			if outward > 0 then
				vel += push * (outward + 1.5)
			elseif vel.Magnitude > 0.25 then
				vel += push * 1.0
			end
		end
		if vel.Magnitude > goal.maxSpeed and goal.maxSpeed > 0 then
			vel = vel.Unit * goal.maxSpeed
		end
		outputs[id] = vel
	end
	return outputs
end

return StreetCrowd
