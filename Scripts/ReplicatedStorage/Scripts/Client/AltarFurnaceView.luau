-- 手动祭坛炉口表现：复用符文、聚能粒子、出药光迹与落位闪光。
--!strict
local Config = require(script.Parent.Parent.Shared.GameConfig)
local Types = require(script.Parent.Parent.Shared.GameTypes)

local View = {}
View.__index = View

local Cyan = Color3.fromRGB(108, 241, 255)
local Violet = Color3.fromRGB(187, 93, 255)
local GlyphCount = 8
local SparkCount = 6
local TrailCount = 5
local PulseSeconds = 0.36
local FlightSeconds = 0.32
local ImpactSeconds = 0.24
local RecentBodyLimit = 256

type Flight = {
	ids: { string },
	targetId: string?,
	origin: Vector3,
	head: Vector3,
	started: number,
	parts: { BasePart },
}

type Impact = { part: BasePart, started: number }

export type View = typeof(setmetatable({} :: {
	folder: Folder,
	mouth: Attachment,
	shelfSign: BasePart,
	glyphs: { { BasePart } },
	sparks: { BasePart },
	light: PointLight,
	lightRoot: BasePart,
	freeTrails: { { BasePart } },
	freeImpacts: { BasePart },
	flights: { Flight },
	impacts: { Impact },
	intakes: { [number]: { [string]: boolean } },
	lastIntake: number,
	pulseStarted: number,
	outputStarted: number,
	recentBodies: { string },
	completed: { [string]: boolean },
	active: boolean,
}, View))

local function MakePart(folder: Folder, name: string, color: Color3, ball: boolean?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
	part.CastShadow = false
	part.Size = Vector3.one * 0.1
	if ball then part.Shape = Enum.PartType.Ball end
	part.Parent = folder
	return part
end

local function DrawLine(part: BasePart, from: Vector3, to: Vector3, width: number, transparency: number): ()
	local length = (to - from).Magnitude
	if length < 0.001 then
		part.Transparency = 1
		return
	end
	part.Size = Vector3.new(width, width, length)
	part.CFrame = CFrame.lookAt((from + to) * 0.5, to)
	part.Transparency = transparency
end

function View.new(mouth: Attachment, shelfSign: BasePart): View
	local folder = Instance.new("Folder")
	folder.Name = "SoulAltarPresentation"
	folder.Parent = workspace
	local glyphs: { { BasePart } } = {}
	for index = 1, GlyphCount do
		local edges = {}
		for _ = 1, 4 do
			table.insert(edges, MakePart(folder, "FurnaceRune", if index % 2 == 0 then Cyan else Violet))
		end
		table.insert(glyphs, edges)
	end
	local sparks = {}
	for index = 1, SparkCount do
		table.insert(sparks, MakePart(folder, "FurnaceSpark", if index % 2 == 0 then Cyan else Violet, true))
	end
	local lightRoot = MakePart(folder, "FurnaceLight", Cyan)
	local light = Instance.new("PointLight")
	light.Color = Violet
	light.Range = 9
	light.Brightness = 0
	light.Enabled = false
	light.Parent = lightRoot
	return setmetatable({
		folder = folder, mouth = mouth, shelfSign = shelfSign, glyphs = glyphs, sparks = sparks,
		light = light, lightRoot = lightRoot, freeTrails = {}, freeImpacts = {},
		flights = {}, impacts = {}, intakes = {}, lastIntake = -math.huge, pulseStarted = -math.huge, outputStarted = -math.huge,
		recentBodies = {}, completed = {}, active = false,
	}, View)
end

function View.ScheduleIntake(self: View, id: string, ends: number): ()
	if ends <= self.lastIntake then return end
	local bodies = self.intakes[ends]
	if not bodies then
		bodies = {}
		self.intakes[ends] = bodies
	end
	bodies[id] = true
end

local function ConsumeIntakes(self: View, items: { [string]: Types.ItemView }, now: number): boolean
	local pulse = false
	for ends, bodies in self.intakes do
		if now < ends then continue end
		self.intakes[ends] = nil
		if now - ends > PulseSeconds then continue end
		for id in bodies do
			local item = items[id]
			if item and item.location == "Altar" then
				self.lastIntake = math.max(self.lastIntake, ends)
				pulse = true
				break
			end
		end
	end
	if pulse then self.pulseStarted = now end
	return pulse
end

local function DrawFurnace(self: View, earliest: number?, now: number): ()
	local pulseAge = now - self.pulseStarted
	local pulse = math.clamp(1 - pulseAge / PulseSeconds, 0, 1)
	local flare = math.clamp(1 - (now - self.outputStarted) / PulseSeconds, 0, 1)
	if not earliest and pulse == 0 and flare == 0 then
		if not self.active then return end
		self.active = false
		self.light.Enabled = false
		for _, edges in self.glyphs do
			for _, edge in edges do edge.Transparency = 1 end
		end
		for _, spark in self.sparks do spark.Transparency = 1 end
		return
	end
	self.active = true
	local mouth = self.mouth.WorldCFrame
	local remaining = if earliest then math.max(earliest - now, 0) else Config.ConversionSeconds
	local elapsed = math.clamp(Config.ConversionSeconds - remaining, 0, Config.ConversionSeconds)
	local charge = math.max(Config.ConversionSeconds - Config.AltarClimaxSeconds, 0.001)
	local climax = math.clamp((elapsed - charge) / Config.AltarClimaxSeconds, 0, 1)
	local gathering = climax ^ 1.5
	local radius = (2.1 - gathering * 1.62) + pulse * 0.5
	local orbit = elapsed * 0.6 + climax * climax * 3.5
	local visibility = if earliest then 0.88 - gathering * 0.2 else pulse
	self.lightRoot.CFrame = mouth * CFrame.new(0, 0.55, 0)
	self.light.Enabled = true
	self.light.Brightness = 0.55 * visibility + gathering * 0.95 + pulse * 1.35 + flare * 1.6
	for index, edges in self.glyphs do
		local angle = orbit + (index - 1) * (2 * math.pi / GlyphCount)
		local height = 0.45 + 0.14 * math.sin(angle * 2) + gathering * 0.35
		local glyph = mouth * CFrame.Angles(0, angle, 0) * CFrame.new(radius, height, 0)
			* CFrame.Angles(math.rad(27), 0, 0)
		local size = 0.22 - gathering * 0.07 + pulse * 0.06
		local points = {
			glyph * Vector3.new(-size, 0, 0), glyph * Vector3.new(0, 0, size * 0.8),
			glyph * Vector3.new(size, 0, 0), glyph * Vector3.new(0, 0, -size * 0.8),
		}
		for side, edge in edges do
			DrawLine(edge, points[side], points[side % #points + 1], 0.055, 1 - visibility)
		end
	end
	for index, spark in self.sparks do
		local phase = (elapsed * 0.8 + climax * climax * 2 + index / SparkCount) % 1
		local angle = -orbit + index * (2 * math.pi / SparkCount) + phase
		local distance = (2.5 - gathering * 0.75) * (1 - phase)
		spark.Position = mouth * Vector3.new(math.cos(angle) * distance, 1.65 - phase * 1.3, math.sin(angle) * distance)
		spark.Size = Vector3.one * (0.07 + (1 - phase) * 0.07)
		spark.Transparency = 1 - visibility * math.sin(phase * math.pi)
	end
end

local function FindTarget(self: View, ids: { string }, slots: { [string]: CFrame }): (string?, Vector3)
	for _, id in ids do
		local slot = slots[id]
		if slot then return id, slot.Position + Vector3.yAxis * 0.4 end
	end
	return nil, self.shelfSign.Position + Vector3.yAxis * 0.55
end

local function AcquireTrail(self: View): { BasePart }
	local cached = table.remove(self.freeTrails)
	if cached then return cached end
	local parts = {}
	for index = 1, TrailCount do
		table.insert(parts, MakePart(self.folder, "PotionLightTrail", Cyan:Lerp(Violet, (index - 1) / TrailCount)))
	end
	return parts
end

function View.PlayOutput(self: View, output: Types.AltarOutput, slots: { [string]: CFrame }, now: number): boolean
	local fresh = false
	for _, id in output.bodyIds do
		if self.completed[id] then continue end
		fresh = true
		self.completed[id] = true
		table.insert(self.recentBodies, id)
		if #self.recentBodies > RecentBodyLimit then
			local oldest = table.remove(self.recentBodies, 1)
			if oldest then self.completed[oldest] = nil end
		end
	end
	if not fresh then return false end

	local targetId = FindTarget(self, output.shelfIds, slots)
	local origin = self.mouth.WorldPosition + self.mouth.WorldCFrame.UpVector * 0.75
	table.insert(self.flights, {
		ids = output.shelfIds, targetId = targetId,
		origin = origin, head = origin, started = now, parts = AcquireTrail(self),
	})
	self.outputStarted = now
	return true
end

local function TrailPoint(from: Vector3, to: Vector3, t: number): Vector3
	return from:Lerp(to, t) + Vector3.yAxis * (math.sin(t * math.pi) * 1.7)
end

local function FlashSlot(self: View, position: Vector3, now: number): ()
	local part = table.remove(self.freeImpacts) or MakePart(self.folder, "PotionArrivalFlash", Cyan, true)
	part.Position = position
	table.insert(self.impacts, { part = part, started = now })
end

local function StepOutput(self: View, slots: { [string]: CFrame }, now: number): ()
	for index = #self.flights, 1, -1 do
		local flight = self.flights[index]
		local targetId, target = FindTarget(self, flight.ids, slots)
		if flight.targetId ~= targetId then
			flight.targetId = targetId
			flight.origin = flight.head
			flight.started = now
		end
		local t = math.clamp((now - flight.started) / FlightSeconds, 0, 1)
		flight.head = TrailPoint(flight.origin, target, t)
		if t >= 1 then
			if not targetId then
				FlashSlot(self, target, now)
			else
				for _, id in flight.ids do
					local slot = slots[id]
					if slot then FlashSlot(self, slot.Position + Vector3.yAxis * 0.4, now) end
				end
			end
			for _, part in flight.parts do part.Transparency = 1 end
			table.insert(self.freeTrails, flight.parts)
			table.remove(self.flights, index)
			continue
		end
		for step, part in flight.parts do
			local head = math.max(0, t - (step - 1) * 0.035)
			local tail = math.max(0, t - step * 0.035)
			DrawLine(part, TrailPoint(flight.origin, target, tail), TrailPoint(flight.origin, target, head),
				0.24 - step * 0.026, (step - 1) * 0.13)
		end
	end
	for index = #self.impacts, 1, -1 do
		local impact = self.impacts[index]
		local t = math.clamp((now - impact.started) / ImpactSeconds, 0, 1)
		impact.part.Size = Vector3.one * (0.27 + t * 1.0)
		impact.part.Transparency = 0.12 + 0.88 * t
		if t >= 1 then
			table.insert(self.freeImpacts, impact.part)
			table.remove(self.impacts, index)
		end
	end
end

function View.Step(self: View, items: { [string]: Types.ItemView }, earliest: number?, slots: { [string]: CFrame }, now: number): boolean
	local pulse = ConsumeIntakes(self, items, now)
	DrawFurnace(self, earliest, now)
	StepOutput(self, slots, now)
	return pulse
end

function View.Destroy(self: View): ()
	self.folder:Destroy()
end

return View
