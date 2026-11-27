-- 手动丢置瞄准预览：两段虚线 Beam 拟合斜抛，落点光圈区分可入池与普通落地
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Physics = require(ReplicatedStorage.Scripts.Shared.PhysicsConfig)
local Arc = require(ReplicatedStorage.Scripts.Shared.ThrowArc)
local CageGeometry = require(ReplicatedStorage.Scripts.Shared.CageGeometry)
local ModelTemplates = require(ReplicatedStorage.Scripts.Shared.ModelTemplates)
local Config = Physics.ManualThrow
local Preview = {}
Preview.__index = Preview
export type CageTarget = { kind: string, frame: CFrame, size: Vector3, inset: number }
type BeamArc = { beam: Beam, first: Attachment, finish: Attachment }
export type Preview = typeof(setmetatable(
	{} :: {
		model: Model,
		arcs: { BeamArc },
		ring: Model,
		disc: BasePart,
		params: RaycastParams,
		origin: Vector3?,
		velocity: Vector3?,
		gravity: number?,
		baffles: Instance?,
		baffleParams: RaycastParams,
		legal: boolean?,
		nextTrace: number,
	},
	Preview
))
local HiddenPosition = CFrame.new(0, -200, 0)

function Preview.Hide(self: Preview): ()
	for _, arc in self.arcs do
		arc.beam.Enabled = false
	end
	self.ring:PivotTo(HiddenPosition)
	self.origin = nil
	self.nextTrace = 0
end

function Preview.Update(self: Preview, origin: Vector3, direction: Vector3, gravity: number, legalAt: (Vector3, Vector3?, boolean?, string?) -> boolean, ignored: { Instance }, now: number, baffles: Instance?, cages: { CageTarget }?): ()
	local velocity = Arc.LaunchVelocity(direction, gravity)
	if self.origin == origin and self.velocity == velocity and self.gravity == gravity and self.baffles == baffles and now < self.nextTrace then
		return
	end
	self.params.FilterDescendantsInstances = ignored
	self.baffleParams.FilterDescendantsInstances = if baffles then { baffles } else {}
	local bestCageKind: string? = nil
	local bestCage: CageTarget? = nil
	local function Cast(frame: CFrame, size: Vector3, delta: Vector3): RaycastResult?
		local solid = workspace:Blockcast(frame, size, delta, self.params)
		local baffle = if baffles then workspace:Blockcast(frame, size, delta, self.baffleParams) else nil
		local best = Arc.FirstHit(solid, baffle)
		local bestDistance = if best then best.Distance else math.huge
		bestCageKind = nil
		bestCage = nil
		if cages then
			for _, cage in cages do
				local dist, pos, norm = CageGeometry.IntersectInnerWall(cage.frame, cage.size, cage.inset, frame.Position, delta)
				if dist and pos and norm and dist < bestDistance then
					bestDistance = dist
					bestCageKind = cage.kind
					bestCage = cage
					best = {
						Distance = dist,
						Position = pos,
						Normal = norm,
						Instance = workspace.Terrain,
						Material = Enum.Material.Air,
					} :: any
				end
			end
		end
		return best
	end
	local duration, landing, surface, normal, hit = Arc.Sweep(origin, velocity, gravity, Config.PreviewStepSeconds, Config.PreviewDurationSeconds, Config.SweepSize, Cast)
	local hitBaffle = hit ~= nil and baffles ~= nil and bestCageKind == nil and hit:IsDescendantOf(baffles)
	local ringSurface, ringNormal = surface, normal
	if bestCage and surface then
		local innerX, innerZ = CageGeometry.InnerHalfSize(bestCage.size, bestCage.inset)
		local localHit = bestCage.frame:PointToObjectSpace(surface)
		local clamped = Vector3.new(
			math.clamp(localHit.X, -math.max(0, innerX - 0.2), math.max(0, innerX - 0.2)),
			bestCage.size.Y * 0.5,
			math.clamp(localHit.Z, -math.max(0, innerZ - 0.2), math.max(0, innerZ - 0.2))
		)
		ringSurface = bestCage.frame:PointToWorldSpace(clamped)
		ringNormal = bestCage.frame.UpVector
	end
	local legal = if ringSurface then legalAt(ringSurface, ringNormal, hitBaffle, bestCageKind) else false
	self.origin, self.velocity, self.gravity, self.baffles, self.legal = origin, velocity, gravity, baffles, legal
	self.nextTrace = now + Config.RefreshIntervalSeconds
	local color = if legal then Config.LegalColor else Config.WarningColor
	local half = duration * 0.5
	for index, arc in self.arcs do
		local offset = if index == 1 then 0 else half
		local span = if index == 1 then math.min(duration, half) else math.max(0, duration - half)
		local start = Arc.Position(origin, velocity, gravity, offset)
		local startVelocity = Arc.Velocity(velocity, gravity, offset)
		local first, finish, size0, size1 = Arc.BeamCurve(start, startVelocity, gravity, span)
		arc.first.WorldCFrame = first
		arc.finish.WorldCFrame = finish
		arc.beam.CurveSize0, arc.beam.CurveSize1 = size0, size1
		arc.beam.Color = ColorSequence.new(color)
		arc.beam.Enabled = span > 0
	end
	local ending = if self.arcs[2].beam.Enabled then self.arcs[2] else self.arcs[1]
	if ringSurface and ringNormal then
		local frame = Arc.RingCFrame(ringSurface, ringNormal)
		self.disc.CFrame = frame
		if ending.beam.Enabled and not bestCage then
			local finish = ending.finish.WorldCFrame
			ending.finish.WorldCFrame = finish.Rotation + frame.Position
		end
	else
		self.ring:PivotTo(HiddenPosition)
	end
	for _, part in self.ring:GetDescendants() do
		if part:IsA("BasePart") then
			part.Color = color
		end
	end
end

function Preview.new(): Preview
	local template = ModelTemplates.WaitEffect("ThrowAim")
	local model = template:Clone()
	local ring = model:WaitForChild("Ring") :: Model
	local disc = ring.PrimaryPart or ring:FindFirstChild("RingPart")
	assert(disc and disc:IsA("BasePart"), "ThrowAim ring requires a part")
	local arcs: { BeamArc } = {}
	for _, node in model:GetDescendants() do
		if node:IsA("Beam") then
			local first, finish = node.Attachment0, node.Attachment1
			assert(first and finish, "ThrowAim requires both beam attachments")
			node.Enabled = false
			node.Width0, node.Width1 = Config.BeamWidthStuds, Config.BeamWidthStuds
			node.Segments = Config.BeamSegments / 2
			local keys = { NumberSequenceKeypoint.new(0, Config.BeamTransparency) }
			local count = Config.DashCount / 2
			for index = 0, count - 1 do
				local edge = (index + Config.DashFraction) / count
				table.insert(keys, NumberSequenceKeypoint.new(edge, Config.BeamTransparency))
				table.insert(keys, NumberSequenceKeypoint.new(math.min(edge + 0.001, 1), 1))
				if index < count - 1 then
					table.insert(keys, NumberSequenceKeypoint.new((index + 1) / count - 0.001, 1))
					table.insert(keys, NumberSequenceKeypoint.new((index + 1) / count, Config.BeamTransparency))
				end
			end
			table.insert(keys, NumberSequenceKeypoint.new(1, 1))
			node.Transparency = NumberSequence.new(keys)
			table.insert(arcs, { beam = node, first = first, finish = finish })
		end
	end
	table.sort(arcs, function(left: BeamArc, right: BeamArc): boolean
		return left.beam.Name < right.beam.Name
	end)
	assert(#arcs == 2, "ThrowAim requires two trajectory Beams")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local baffleParams = RaycastParams.new()
	baffleParams.FilterType = Enum.RaycastFilterType.Include
	baffleParams.CollisionGroup = Physics.BodyGroup
	baffleParams.RespectCanCollide = true
	local self = setmetatable({
		model = model,
		arcs = arcs,
		ring = ring,
		disc = disc,
		params = params,
		origin = nil,
		velocity = nil,
		gravity = nil,
		baffles = nil,
		baffleParams = baffleParams,
		legal = nil,
		nextTrace = 0,
	}, Preview)
	self:Hide()
	model.Parent = workspace
	table.insert(self.params.FilterDescendantsInstances, model)
	return self
end

function Preview.Destroy(self: Preview): ()
	self.model:Destroy()
end

return Preview
