-- 自动化产线客户端全链路视觉特效与空间音效：着陆波纹、牵引光束、三头激光、扫描光幕、流光与出药能量轨迹
--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Scripts"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("GameConfig"))
local Types = require(Shared:WaitForChild("GameTypes"))
local Sound = require(Shared:WaitForChild("GameSoundTool"))
local PaintView = require(script.Parent:WaitForChild("PaintView"))

local View = {}
View.__index = View

local Cyan = Color3.fromRGB(108, 241, 255)
local Violet = Color3.fromRGB(187, 93, 255)
local Magenta = Color3.fromRGB(255, 68, 214)

local RipplePoolSize = 8
local RippleSeconds = 0.45
local BeamCount = 2
local LaserCount = 3
local BeltFlowCount = 4
local TrailCount = 5
local FlightSeconds = 0.32
local ImpactSeconds = 0.24
local FlashSeconds = 0.34
local ScanSeconds = 0.35
local SoundCooldownSeconds = 0.25

type Ripple = { part: BasePart, origin: Vector3, started: number }
type Flight = { ids: { string }, origin: Vector3, started: number, parts: { BasePart } }
type Impact = { part: BasePart, started: number }
type RuneFlash = { id: string, started: number }
type ChimneySpark = { part: BasePart, phase: number, offsetX: number, offsetZ: number }
type VisualRestore = { part: BasePart, color: Color3, material: Enum.Material, transparency: number }

export type View = typeof(setmetatable(
	{} :: {
		folder: Folder,
		paintView: PaintView.View,
		autoLine: Instance?,
		workBed: BasePart?,
		passAnchor: BasePart?,
		passLight: Light?,
		inletAnchor: BasePart?,
		smelterCenter: BasePart?,
		furnaceBelt: BasePart?,
		rampPart: BasePart?,
		emitters: { BasePart },
		gantryWest: BasePart?,
		gantryEast: BasePart?,
		gantryTop: BasePart?,
		reactorWindow: BasePart?,
		reactorSideL: BasePart?,
		reactorSideR: BasePart?,
		chimneyPart: BasePart?,
		restores: { VisualRestore },
		restoreMap: { [BasePart]: VisualRestore },
		tractorBeams: { BasePart },
		lasers: { BasePart },
		laserHits: { BasePart },
		beltFlows: { BasePart },
		scanCurtain: BasePart,
		scanStarted: number,
		prevPassLit: boolean,
		furnaceLightRoot: BasePart,
		furnaceLight: PointLight,
		furnacePulseStarted: number,
		eastFlashStarted: number,
		chimneySparks: { ChimneySpark },
		freeRipples: { BasePart },
		ripples: { Ripple },
		freeTrails: { { BasePart } },
		flights: { Flight },
		freeImpacts: { BasePart },
		impacts: { Impact },
		runeFlashes: { [string]: RuneFlash },
		lastSmelterEnds: number,
		lastAutoShelfCount: number,
		lastSoundAt: { [string]: number },
	},
	View
))

local function MakePart(folder: Folder, name: string, color: Color3, shape: Enum.PartType?, transparency: number?): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency or 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Size = Vector3.one * 0.1
	if shape then
		part.Shape = shape
	end
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

local function FindOptional(root: Instance?, ...: string): Instance?
	local current: Instance? = root
	for i = 1, select("#", ...) do
		if not current then
			return nil
		end
		local childName = select(i, ...)
		current = current:FindFirstChild(childName)
	end
	return current
end

local function FindBasePart(root: Instance?, ...: string): BasePart?
	local found = FindOptional(root, ...)
	return if found and found:IsA("BasePart") then found else nil
end

local function BodyAnchorPos(item: Types.ItemView): Vector3?
	local model = item.model
	if not model or model.Parent == nil then
		return nil
	end
	local torso = model:FindFirstChild("UpperTorso")
	if torso and torso:IsA("BasePart") then
		return torso.Position
	end
	local primary = model.PrimaryPart
	if primary then
		return primary.Position
	end
	return model:GetPivot().Position
end

local function PlayLocalAutoSound(self: View, name: string, pos: Vector3, multiplier: number, now: number): ()
	if not Sound or not Sound.Play then
		return
	end
	local lastAt = self.lastSoundAt[name]
	if lastAt and now - lastAt < SoundCooldownSeconds then
		return
	end
	local localPlayer = Players.LocalPlayer
	local char = if localPlayer then localPlayer.Character else nil
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	if (root.Position - pos).Magnitude > Config.AutoSoundMaxDistance then
		return
	end
	self.lastSoundAt[name] = now
	Sound.Play(name, pos, multiplier)
end

local function RecordVisual(restores: { VisualRestore }, restoreMap: { [BasePart]: VisualRestore }, part: BasePart?): BasePart?
	if part then
		local entry: VisualRestore = {
			part = part,
			color = part.Color,
			material = part.Material,
			transparency = part.Transparency,
		}
		table.insert(restores, entry)
		restoreMap[part] = entry
	end
	return part
end

local function RestorePartColor(self: View, part: BasePart?, fallback: Color3): ()
	if not part then
		return
	end
	local entry = self.restoreMap[part]
	part.Color = if entry then entry.color else fallback
end

function View.new(district: Instance, paintView: PaintView.View): View?
	local autoLine = district:FindFirstChild("AutomationLine")
	if not autoLine then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "AutomationLinePresentation"
	folder.Parent = workspace

	local restores: { VisualRestore } = {}
	local restoreMap: { [BasePart]: VisualRestore } = {}
	local runeMachine = autoLine:FindFirstChild("AutoRuneMachine")
	local smelterMachine = autoLine:FindFirstChild("AutoSmelterMachine")
	local workBed = FindBasePart(runeMachine, "WorkBedAnchor")
	local passAnchor = FindBasePart(runeMachine, "TransferPassAnchor")
	local passLightInst = if passAnchor then passAnchor:FindFirstChild("TransferPassLight") else nil
	local passLight = if passLightInst and passLightInst:IsA("Light") then passLightInst else nil
	local inletAnchor = FindBasePart(smelterMachine, "FurnaceInletAnchor")
	local smelterCenter = FindBasePart(smelterMachine, "MachineCenterAnchor")
	local furnaceBelt = FindBasePart(smelterMachine, "Colliders", "FurnaceBelt")
	local rampPart = FindBasePart(runeMachine, "Colliders", "Ramp")

	local emitters: { BasePart } = {}
	for _, name in { "light52", "light51", "light53" } do
		local found = if runeMachine then runeMachine:FindFirstChild(name, true) else nil
		if found and found:IsA("BasePart") then
			table.insert(emitters, found)
		end
	end

	local function VisualPart(parent: Instance?, name: string): BasePart?
		local found = if parent then parent:FindFirstChild(name, true) else nil
		return if found and found:IsA("BasePart") then RecordVisual(restores, restoreMap, found) else nil
	end

	local tractorBeams: { BasePart } = {}
	for i = 1, BeamCount do
		table.insert(tractorBeams, MakePart(folder, "TractorBeam_" .. tostring(i), if i == 1 then Cyan else Violet))
	end
	local lasers: { BasePart } = {}
	local laserHits: { BasePart } = {}
	for i = 1, LaserCount do
		table.insert(lasers, MakePart(folder, "RuneLaser_" .. tostring(i), if i % 2 == 1 then Cyan else Magenta))
		table.insert(laserHits, MakePart(folder, "LaserSpark_" .. tostring(i), Magenta, Enum.PartType.Ball))
	end
	local beltFlows: { BasePart } = {}
	for i = 1, BeltFlowCount do
		table.insert(beltFlows, MakePart(folder, "BeltFlow_" .. tostring(i), if i % 2 == 0 then Cyan else Violet))
	end

	local scanCurtain = MakePart(folder, "TransferScanCurtain", Cyan)
	local furnaceLightRoot = MakePart(folder, "AutoSmelterGlow", Violet)
	local furnaceLight = Instance.new("PointLight")
	furnaceLight.Color = Violet
	furnaceLight.Range = 14
	furnaceLight.Brightness = 0
	furnaceLight.Enabled = false
	furnaceLight.Parent = furnaceLightRoot

	local chimneySparks: { ChimneySpark } = {}
	for i = 1, 6 do
		table.insert(chimneySparks, {
			part = MakePart(folder, "ChimneySpark_" .. tostring(i), if i % 2 == 0 then Cyan else Violet, Enum.PartType.Ball),
			phase = (i - 1) / 6,
			offsetX = ((i % 3) - 1) * 0.65,
			offsetZ = (math.floor((i - 1) / 3) - 0.5) * 0.7,
		})
	end

	local freeRipples: { BasePart } = {}
	for i = 1, RipplePoolSize do
		local ring = MakePart(folder, "ChuteRipple_" .. tostring(i), Cyan, Enum.PartType.Cylinder)
		table.insert(freeRipples, ring)
	end

	return setmetatable({
		folder = folder,
		paintView = paintView,
		autoLine = autoLine,
		workBed = workBed,
		passAnchor = passAnchor,
		passLight = passLight,
		inletAnchor = inletAnchor,
		smelterCenter = smelterCenter,
		furnaceBelt = furnaceBelt,
		rampPart = rampPart,
		emitters = emitters,
		gantryWest = VisualPart(runeMachine, "light48"),
		gantryEast = VisualPart(runeMachine, "light47"),
		gantryTop = VisualPart(runeMachine, "light33"),
		reactorWindow = VisualPart(smelterMachine, "light58"),
		reactorSideL = VisualPart(smelterMachine, "light55"),
		reactorSideR = VisualPart(smelterMachine, "light57"),
		chimneyPart = VisualPart(smelterMachine, "light56"),
		restores = restores,
		restoreMap = restoreMap,
		tractorBeams = tractorBeams,
		lasers = lasers,
		laserHits = laserHits,
		beltFlows = beltFlows,
		scanCurtain = scanCurtain,
		scanStarted = -math.huge,
		prevPassLit = false,
		furnaceLightRoot = furnaceLightRoot,
		furnaceLight = furnaceLight,
		furnacePulseStarted = -math.huge,
		eastFlashStarted = -math.huge,
		chimneySparks = chimneySparks,
		freeRipples = freeRipples,
		ripples = {},
		freeTrails = {},
		flights = {},
		freeImpacts = {},
		impacts = {},
		runeFlashes = {},
		lastSmelterEnds = 0,
		lastAutoShelfCount = -1,
		lastSoundAt = {},
	}, View)
end

local function SpawnRipple(self: View, pos: Vector3, now: number): ()
	local ring = table.remove(self.freeRipples)
	if not ring then
		return
	end
	ring.Position = Vector3.new(pos.X, pos.Y, pos.Z)
	table.insert(self.ripples, { part = ring, origin = Vector3.new(pos.X, pos.Y, pos.Z), started = now })
end

local function AcquireTrail(self: View): { BasePart }
	local cached = table.remove(self.freeTrails)
	if cached then
		return cached
	end
	local parts: { BasePart } = {}
	for i = 1, TrailCount do
		table.insert(parts, MakePart(self.folder, "AutoPotionTrail_" .. tostring(i), Cyan:Lerp(Violet, (i - 1) / TrailCount)))
	end
	return parts
end

local function TrailPoint(from: Vector3, to: Vector3, t: number): Vector3
	return from:Lerp(to, t) + Vector3.yAxis * (math.sin(t * math.pi) * 2.1)
end

local function SpawnImpact(self: View, pos: Vector3, now: number): ()
	local part = table.remove(self.freeImpacts) or MakePart(self.folder, "AutoPotionImpact", Cyan, Enum.PartType.Ball)
	part.Position = pos
	table.insert(self.impacts, { part = part, started = now })
end

function View.OnSnapshot(
	self: View,
	snapshot: Types.Snapshot,
	prevItems: { [string]: Types.ItemView },
	nextItems: { [string]: Types.ItemView },
	prevAutoShelf: { [string]: CFrame }?,
	animate: boolean,
	now: number
): ()
	local prevShelfCount = self.lastAutoShelfCount
	local nextShelfCount = snapshot.autoShelfCount or 0
	self.lastAutoShelfCount = nextShelfCount
	if not animate then
		self.lastSmelterEnds = snapshot.autoSmelterEnds or 0
		return
	end

	for id, item in nextItems do
		local prior = prevItems[id]
		if item.location == "Chute" and (not prior or prior.location ~= "Chute") then
			local pos = BodyAnchorPos(item)
			if pos then
				SpawnRipple(self, Vector3.new(pos.X, 1.28, pos.Z), now)
			end
		end
		if prior and prior.location == "AutoRune" and (item.location == "AutoOutput" or item.location == "AutoSmelter") then
			self.eastFlashStarted = now
			self.runeFlashes[id] = { id = id, started = now }
			self.paintView:SetSacrifice(id, 1, 0)
			if self.workBed then
				PlayLocalAutoSound(self, "PaintComplete", self.workBed.Position, 0.30, now)
			end
		end
		if item.location == "AutoSmelter" and item.stage == "Converting" and (not prior or prior.stage ~= "Converting") then
			self.furnacePulseStarted = now
			local soundPos = if self.inletAnchor then self.inletAnchor.Position elseif self.smelterCenter then self.smelterCenter.Position else nil
			if soundPos then
				PlayLocalAutoSound(self, "AltarPlace", soundPos, 0.28, now)
			end
		end
	end

	local nextSmelterEnds = snapshot.autoSmelterEnds or 0
	if nextSmelterEnds > 0 and nextSmelterEnds ~= self.lastSmelterEnds then
		self.furnacePulseStarted = now
	end
	self.lastSmelterEnds = nextSmelterEnds

	local addedShelfIds: { string } = {}
	local nextSlots: { [string]: CFrame } = snapshot.autoShelfItems or {}
	if prevAutoShelf then
		for id in nextSlots do
			if not prevAutoShelf[id] then
				table.insert(addedShelfIds, id)
			end
		end
	end
	if #addedShelfIds > 0 or (prevShelfCount >= 0 and nextShelfCount > prevShelfCount) then
		local center = if self.smelterCenter then self.smelterCenter.Position else Vector3.new(2.5, 4.5, -27.5)
		local origin = center + Vector3.new(4.8, 1.0, -2.5)
		table.insert(self.flights, {
			ids = addedShelfIds,
			origin = origin,
			started = now,
			parts = AcquireTrail(self),
		})
		PlayLocalAutoSound(self, "AltarComplete", origin, 0.32, now)
	end
end

local function StepRipples(self: View, now: number): ()
	for index = #self.ripples, 1, -1 do
		local ripple = self.ripples[index]
		local t = math.clamp((now - ripple.started) / RippleSeconds, 0, 1)
		if t >= 1 then
			ripple.part.Transparency = 1
			table.insert(self.freeRipples, ripple.part)
			table.remove(self.ripples, index)
		else
			local diameter = 1.6 + t * 5.2
			ripple.part.Size = Vector3.new(0.08, diameter, diameter)
			ripple.part.CFrame = CFrame.new(ripple.origin) * CFrame.Angles(0, 0, math.pi / 2)
			ripple.part.Color = Cyan:Lerp(Violet, t)
			ripple.part.Transparency = 0.25 + 0.75 * t
		end
	end
end

local function StepRuneFlashes(self: View, now: number): ()
	for id, flash in self.runeFlashes do
		local t = math.clamp((now - flash.started) / FlashSeconds, 0, 1)
		if t >= 1 then
			self.paintView:ClearSacrifice(id)
			self.runeFlashes[id] = nil
		else
			self.paintView:SetSacrifice(id, 1 - t * t, 0)
		end
	end
end

local function StepFlights(self: View, slots: { [string]: CFrame }, now: number): ()
	local fallbackTarget = Vector3.new(15.1, 4.2, -29.2)
	for index = #self.flights, 1, -1 do
		local flight = self.flights[index]
		local target = fallbackTarget
		for _, id in flight.ids do
			if slots[id] then
				target = slots[id].Position + Vector3.yAxis * 0.4
				break
			end
		end
		local t = math.clamp((now - flight.started) / FlightSeconds, 0, 1)
		if t >= 1 then
			for _, id in flight.ids do
				local slot = slots[id]
				if slot then
					SpawnImpact(self, slot.Position + Vector3.yAxis * 0.4, now)
				end
			end
			for _, part in flight.parts do
				part.Transparency = 1
			end
			table.insert(self.freeTrails, flight.parts)
			table.remove(self.flights, index)
			continue
		end
		for step, part in flight.parts do
			local head = math.max(0, t - (step - 1) * 0.035)
			local tail = math.max(0, t - step * 0.035)
			DrawLine(part, TrailPoint(flight.origin, target, tail), TrailPoint(flight.origin, target, head), 0.24 - step * 0.025, (step - 1) * 0.13)
		end
	end
	for index = #self.impacts, 1, -1 do
		local impact = self.impacts[index]
		local t = math.clamp((now - impact.started) / ImpactSeconds, 0, 1)
		if t >= 1 then
			impact.part.Transparency = 1
			table.insert(self.freeImpacts, impact.part)
			table.remove(self.impacts, index)
		else
			impact.part.Size = Vector3.one * (0.3 + t * 1.1)
			impact.part.Transparency = 0.15 + 0.85 * t
		end
	end
end

function View.Step(self: View, snapshot: Types.Snapshot?, items: { [string]: Types.ItemView }, now: number, serverNow: number): ()
	StepRipples(self, now)
	StepRuneFlashes(self, now)
	StepFlights(self, (if snapshot and snapshot.autoShelfItems then snapshot.autoShelfItems else {}) :: { [string]: CFrame }, now)

	-- 查找处于 AutoRune 阶段的白膜并判断是在滑入床面还是已经上床画符
	local runeItem: Types.ItemView? = nil
	local hasMovingOnBeltOrRamp = false
	for _, item in items do
		if item.location == "AutoRune" then
			runeItem = item
		elseif item.location == "AutoSmelter" and item.stage ~= "Converting" then
			hasMovingOnBeltOrRamp = true
		elseif item.location == "AutoOutput" then
			local pos = BodyAnchorPos(item)
			if pos and self.rampPart and math.abs(pos.X - self.rampPart.Position.X) < 5.5 then
				hasMovingOnBeltOrRamp = true
			end
		end
	end

	local bedPos = if self.workBed then self.workBed.Position else Vector3.new(-32.2, 0.94, -27.5)
	local runePos = if runeItem then BodyAnchorPos(runeItem) else nil
	local isIntaking = runePos ~= nil and Vector3.new(runePos.X - bedPos.X, 0, runePos.Z - bedPos.Z).Magnitude > 1.25
	local isEngraving = runePos ~= nil and not isIntaking and snapshot ~= nil and (snapshot.autoRuneEnds or 0) > serverNow

	-- 1. 牵引光束（落料池 -> 绘画床）
	if isIntaking and runePos then
		local westPos = if self.gantryWest then self.gantryWest.Position else bedPos + Vector3.new(-6.7, 2.8, 0)
		for i, beam in self.tractorBeams do
			local zOff = if i == 1 then -1.9 else 1.9
			DrawLine(beam, westPos + Vector3.new(0, 0.5, zOff), runePos + Vector3.new(0, 0.25, zOff * 0.25), 0.12, 0.25 + 0.12 * math.sin(now * 16 + i))
		end
		if self.gantryWest then
			self.gantryWest.Color = Cyan
		end
	else
		for _, beam in self.tractorBeams do
			beam.Transparency = 1
		end
		RestorePartColor(self, self.gantryWest, Violet)
	end

	-- 2. 三头激光扫射 + 落点火花
	if isEngraving and runePos then
		for i = 1, LaserCount do
			local emitter = self.emitters[i]
			local startPos = if emitter then emitter.Position else bedPos + Vector3.new((i - 2) * 3.8, 4.6, 1.1)
			local sweepX = math.sin(now * (7.5 + i * 1.3) + i * 2.1) * 1.45
			local sweepZ = math.cos(now * (6.2 + i * 1.1) + i * 1.7) * 0.85
			local targetPos = runePos + Vector3.new(sweepX, 0.32, sweepZ)
			DrawLine(self.lasers[i], startPos, targetPos, 0.085, 0.15)
			local spark = self.laserHits[i]
			spark.Position = targetPos
			spark.Size = Vector3.one * (0.24 + 0.1 * math.sin(now * 28 + i))
			spark.Transparency = 0.08
		end
		if self.gantryTop then
			self.gantryTop.Color = Cyan:Lerp(Magenta, 0.5 + 0.5 * math.sin(now * 14))
		end
	else
		for i = 1, LaserCount do
			self.lasers[i].Transparency = 1
			self.laserHits[i].Transparency = 1
		end
		RestorePartColor(self, self.gantryTop, Cyan)
	end

	if self.gantryEast then
		local eastFlash = math.clamp(1 - (now - self.eastFlashStarted) / FlashSeconds, 0, 1)
		if eastFlash > 0 then
			self.gantryEast.Color = Violet:Lerp(Cyan, eastFlash)
		else
			RestorePartColor(self, self.gantryEast, Violet)
		end
	end

	-- 3. 检测台扫描光幕 + 斜坡/传送带流光
	local passLit = self.passLight ~= nil and self.passLight.Enabled
	if passLit and not self.prevPassLit then
		self.scanStarted = now
	end
	self.prevPassLit = passLit
	local scanAlpha = (now - self.scanStarted) / ScanSeconds
	if self.passAnchor and scanAlpha >= 0 and scanAlpha <= 1 then
		local p = self.passAnchor.Position
		local y = p.Y + 2.8 - scanAlpha * 3.2
		self.scanCurtain.Size = Vector3.new(0.14, 0.35, 5.2)
		self.scanCurtain.CFrame = CFrame.new(p.X, y, p.Z)
		self.scanCurtain.Color = Cyan:Lerp(Magenta, scanAlpha)
		self.scanCurtain.Transparency = 0.25 + 0.45 * math.abs(scanAlpha - 0.5) * 2
	else
		self.scanCurtain.Transparency = 1
	end

	if hasMovingOnBeltOrRamp and self.rampPart and self.inletAnchor then
		local startPos = self.rampPart.Position - Vector3.new(2.2, 0.8, 0)
		local endPos = self.inletAnchor.Position
		for i, flow in self.beltFlows do
			local phase = (now * 1.15 + (i - 1) / BeltFlowCount) % 1
			local headPos = startPos:Lerp(endPos, phase) + Vector3.yAxis * 0.45
			local tailPos = startPos:Lerp(endPos, math.max(0, phase - 0.08)) + Vector3.yAxis * 0.45
			DrawLine(flow, tailPos, headPos, 0.14, 0.2 + 0.6 * math.abs(phase - 0.5) * 2)
		end
	else
		for _, flow in self.beltFlows do
			flow.Transparency = 1
		end
	end

	-- 4. 炼化炉反应窗呼吸蓄能 + 烟囱魔力火星
	local smelterEnds = if snapshot then (snapshot.autoSmelterEnds or 0) else 0
	local smelting = smelterEnds > serverNow
	local pulse = math.clamp(1 - (now - self.furnacePulseStarted) / FlashSeconds, 0, 1)
	if smelting or pulse > 0 then
		local remaining = if smelting then math.max(0, smelterEnds - serverNow) else 0
		local progress = if smelting then math.clamp(1 - remaining / math.max(Config.AutoSmelterSeconds, 0.1), 0, 1) else 0
		local breathe = 0.5 + 0.5 * math.sin(now * (5 + progress * 10))
		local centerPos = if self.smelterCenter then self.smelterCenter.Position else Vector3.new(2.5, 4.0, -27.5)
		self.furnaceLightRoot.Position = centerPos + Vector3.new(0, 1.0, 2.5)
		self.furnaceLight.Enabled = true
		self.furnaceLight.Brightness = 0.6 + progress * 1.4 + breathe * 0.45 + pulse * 1.2
		self.furnaceLight.Color = Violet:Lerp(Magenta, progress * 0.65)
		local glowColor = Violet:Lerp(Magenta, 0.35 * breathe + 0.55 * progress)
		if self.reactorWindow then
			self.reactorWindow.Color = glowColor
		end
		if self.reactorSideL then
			self.reactorSideL.Color = glowColor
		end
		if self.reactorSideR then
			self.reactorSideR.Color = glowColor
		end
		local chimneyBase = if self.chimneyPart then self.chimneyPart.Position else centerPos + Vector3.new(0, 6.5, -3.0)
		for _, spark in self.chimneySparks do
			local p = (now * 0.75 + spark.phase) % 1
			spark.part.Position = chimneyBase + Vector3.new(spark.offsetX * (1 + p * 0.4), 0.3 + p * 3.8, spark.offsetZ * (1 + p * 0.4))
			spark.part.Size = Vector3.one * (0.28 * (1 - p * 0.65))
			spark.part.Transparency = 0.15 + 0.85 * p
		end
	else
		self.furnaceLight.Enabled = false
		RestorePartColor(self, self.reactorWindow, Violet)
		RestorePartColor(self, self.reactorSideL, Violet)
		RestorePartColor(self, self.reactorSideR, Violet)
		for _, spark in self.chimneySparks do
			spark.part.Transparency = 1
		end
	end
end

function View.Destroy(self: View): ()
	for id in self.runeFlashes do
		self.paintView:ClearSacrifice(id)
	end
	table.clear(self.runeFlashes)
	for _, entry in self.restores do
		if entry.part.Parent ~= nil then
			entry.part.Color = entry.color
			entry.part.Material = entry.material
			entry.part.Transparency = entry.transparency
		end
	end
	table.clear(self.restores)
	self.folder:Destroy()
end

return View
