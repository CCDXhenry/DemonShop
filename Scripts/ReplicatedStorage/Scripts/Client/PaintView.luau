-- 统一符文印记视图：本地等距落印、稳定 ID 增量和所有客户端同几何重建
--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Scripts.Shared.GameConfig)
local Types = require(ReplicatedStorage.Scripts.Shared.GameTypes)
local Surface = require(ReplicatedStorage.Scripts.Shared.PaintSurface)
local Curve = require(ReplicatedStorage.Scripts.Shared.CurvedSurface)
local RuneRules = require(ReplicatedStorage.Scripts.Shared.RuneStampRules)
local CurvedView = require(script.Parent.CurvedPaintView)
local UIManager = require(script.Parent.UIManager)

local View = {}
View.__index = View

type CurvedTip = { part: string, point: Vector3, restPoint: Vector3, carry: number }
type FlatTip = { part: string, face: number, point: Vector2, carry: number }
type StampGrid = { [string]: { [number]: { Vector3 } } }
type PulseSlot = {
	attachment: Attachment,
	gui: BillboardGui,
	dot: Frame,
	crossA: Frame,
	crossB: Frame,
	stroke: UIStroke,
	part: BasePart?,
	localPos: Vector3,
	bornAt: number,
	active: boolean,
}

local StampGridOffset = 64
local StampGridBase = 128
local PulsePoolSize = 8
local PulseDuration = 0.18
local PulseCooldown = 0.035

local function StampCellKey(gx: number, gy: number, gz: number): number
	return ((gx + StampGridOffset) * StampGridBase + (gy + StampGridOffset)) * StampGridBase + (gz + StampGridOffset)
end

export type View = typeof(setmetatable({} :: {
	faces: UIManager.PaintFaceManager,
	cells: UIManager.PaintCellManager,
	models: { [string]: Model },
	segments: { [string]: { [string]: Types.VisualSegment } },
	tips: { [string]: FlatTip },
	dirty: { [string]: { [string]: Types.VisualSegment } },
	counts: { [string]: number },
	glyphs: { [string]: number },
	budgetReached: boolean,
	curved: CurvedView.View?,
	curvedTips: { [string]: CurvedTip }?,
	stampGrids: { [string]: StampGrid },
	pulsePool: { PulseSlot }?,
	pulseCursor: number,
	lastPulse: number,
}, View))

function View.new(faces: UIManager.PaintFaceManager?, cells: UIManager.PaintCellManager?): View
	return setmetatable({
		faces = faces or UIManager.GetPaintFaceGuiManager(),
		cells = cells or UIManager.GetPaintCellFrameManager(),
		models = {},
		segments = {},
		tips = {},
		dirty = {},
		counts = {},
		glyphs = {},
		budgetReached = false,
		stampGrids = {},
		pulsePool = nil,
		pulseCursor = 0,
		lastPulse = 0,
	}, View)
end

local function EnsurePulsePool(self: View): { PulseSlot }?
	if self.pulsePool then
		return self.pulsePool
	end
	local okTerrain, terrain = pcall(function(): Instance?
		return workspace.Terrain
	end)
	if not okTerrain or not terrain then
		return nil
	end
	local pool: { PulseSlot } = {}
	for i = 1, PulsePoolSize do
		local okSlot, slot = pcall(function(): PulseSlot
			local attachment = Instance.new("Attachment")
			attachment.Name = "RuneAppearPulse_" .. tostring(i)
			attachment.Parent = terrain
			local gui = Instance.new("BillboardGui")
			gui.Name = "RunePulseGui"
			gui.AlwaysOnTop = false
			gui.LightInfluence = 0
			gui.MaxDistance = 40
			gui.Size = UDim2.fromScale(0.22, 0.22)
			gui.Enabled = false
			gui.Adornee = attachment
			gui.Parent = attachment
			local crossA = Instance.new("Frame")
			crossA.Name = "StarBeamH"
			crossA.AnchorPoint = Vector2.new(0.5, 0.5)
			crossA.Position = UDim2.fromScale(0.5, 0.5)
			crossA.Size = UDim2.fromScale(1, 0.16)
			crossA.BackgroundColor3 = Config.RuneAppearHighlightColor
			crossA.BackgroundTransparency = 0.15
			crossA.BorderSizePixel = 0
			crossA.Parent = gui
			local crossB = Instance.new("Frame")
			crossB.Name = "StarBeamV"
			crossB.AnchorPoint = Vector2.new(0.5, 0.5)
			crossB.Position = UDim2.fromScale(0.5, 0.5)
			crossB.Size = UDim2.fromScale(0.16, 1)
			crossB.BackgroundColor3 = Config.RuneAppearHighlightColor
			crossB.BackgroundTransparency = 0.15
			crossB.BorderSizePixel = 0
			crossB.Parent = gui
			local dot = Instance.new("Frame")
			dot.Name = "GlowDiamond"
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromScale(0.5, 0.5)
			dot.Size = UDim2.fromScale(0.56, 0.56)
			dot.Rotation = 45
			dot.BackgroundColor3 = Config.RuneAppearHighlightColor
			dot.BackgroundTransparency = 0.1
			dot.BorderSizePixel = 0
			dot.Parent = gui
			local stroke = Instance.new("UIStroke")
			stroke.Color = Config.RuneBaseColor
			stroke.Thickness = 1.5
			stroke.Transparency = 0
			stroke.Parent = dot
			return {
				attachment = attachment,
				gui = gui,
				dot = dot,
				crossA = crossA,
				crossB = crossB,
				stroke = stroke,
				part = nil,
				localPos = Vector3.zero,
				bornAt = 0,
				active = false,
			}
		end)
		if not okSlot then
			for _, created in pool do
				created.attachment:Destroy()
			end
			return nil
		end
		table.insert(pool, slot)
	end
	self.pulsePool = pool
	return pool
end

local function SpawnPulse(self: View, part: BasePart, localPosition: Vector3): ()
	local now = os.clock()
	if now - self.lastPulse < PulseCooldown then
		return
	end
	local pool = EnsurePulsePool(self)
	if not pool or #pool == 0 then
		return
	end
	self.lastPulse = now
	self.pulseCursor = (self.pulseCursor % #pool) + 1
	local slot = pool[self.pulseCursor]
	slot.part = part
	slot.localPos = localPosition
	slot.attachment.WorldPosition = part.CFrame:PointToWorldSpace(localPosition)
	slot.gui.Size = UDim2.fromScale(0.18, 0.18)
	slot.dot.BackgroundTransparency = 0.1
	slot.crossA.BackgroundTransparency = 0.15
	slot.crossB.BackgroundTransparency = 0.15
	slot.stroke.Transparency = 0
	slot.gui.Enabled = true
	slot.bornAt = now
	slot.active = true
end

local function StepPulses(self: View): ()
	local pool = self.pulsePool
	if not pool then
		return
	end
	local now = os.clock()
	for _, slot in pool do
		if not slot.active then
			continue
		end
		local part = slot.part
		local alpha = (now - slot.bornAt) / PulseDuration
		if not part or not part.Parent or alpha >= 1 then
			slot.active = false
			slot.part = nil
			slot.gui.Enabled = false
		else
			slot.attachment.WorldPosition = part.CFrame:PointToWorldSpace(slot.localPos)
			local eased = 1 - (1 - alpha) * (1 - alpha)
			local size = 0.18 + 0.30 * eased
			slot.gui.Size = UDim2.fromScale(size, size)
			slot.dot.BackgroundTransparency = 0.1 + 0.9 * eased
			slot.crossA.BackgroundTransparency = 0.15 + 0.85 * eased
			slot.crossB.BackgroundTransparency = 0.15 + 0.85 * eased
			slot.stroke.Transparency = eased
		end
	end
end

local ModelStampBucket = "__model__"

local function StampCoordAndBucket(partName: string, localPoint: Vector3): (string, Vector3)
	local restPoint = Curve.ToModelRest(partName, localPoint)
	if restPoint ~= localPoint then
		return ModelStampBucket, restPoint
	end
	return partName, localPoint
end

local function HasNearbyCurvedStamp(self: View, id: string, partName: string, point: Vector3, cellSize: number, minDist: number): boolean
	local bucketName, coord = StampCoordAndBucket(partName, point)
	local idGrid = self.stampGrids[id]
	if not idGrid then
		return false
	end
	local partGrid = idGrid[bucketName]
	if not partGrid then
		return false
	end
	local safeCell = math.max(cellSize, 0.05)
	local gx = math.floor(coord.X / safeCell)
	local gy = math.floor(coord.Y / safeCell)
	local gz = math.floor(coord.Z / safeCell)
	local minDistSq = minDist * minDist
	for dx = -1, 1 do
		local baseX = (gx + dx + StampGridOffset) * StampGridBase
		for dy = -1, 1 do
			local baseXY = (baseX + gy + dy + StampGridOffset) * StampGridBase
			for dz = -1, 1 do
				local bucket = partGrid[baseXY + gz + dz + StampGridOffset]
				if bucket then
					for _, existing in bucket do
						local diff = coord - existing
						if diff:Dot(diff) < minDistSq then
							return true
						end
					end
				end
			end
		end
	end
	return false
end

local function RecordCurvedStamp(self: View, id: string, partName: string, point: Vector3, cellSize: number): ()
	local bucketName, coord = StampCoordAndBucket(partName, point)
	local idGrid = self.stampGrids[id]
	if not idGrid then
		idGrid = {}
		self.stampGrids[id] = idGrid
	end
	local partGrid = idGrid[bucketName]
	if not partGrid then
		partGrid = {}
		idGrid[bucketName] = partGrid
	end
	local safeCell = math.max(cellSize, 0.05)
	local key = StampCellKey(math.floor(coord.X / safeCell), math.floor(coord.Y / safeCell), math.floor(coord.Z / safeCell))
	local bucket = partGrid[key]
	if not bucket then
		bucket = {}
		partGrid[key] = bucket
	end
	table.insert(bucket, coord)
end

local function FlatGuiPoint(face: number, u: number, v: number, dimensions: Vector2): Vector2
	local guiU = if face <= 4 then 1 - u else u
	return Vector2.new(guiU * dimensions.X, v * dimensions.Y)
end

local function NextGlyph(self: View, id: string): number
	local current = self.glyphs[id] or 1
	self.glyphs[id] = (current % Config.RuneGlyphCount) + 1
	return current
end

function View.Render(self: View, id: string, segment: Types.VisualSegment): ()
	local model = self.models[id]
	local part = model and model:FindFirstChild(segment.part)
	if not part or not part:IsA("BasePart") then
		return
	end
	if Curve.IsPart(part) then
		local curved: CurvedView.View = self.curved or CurvedView.new()
		self.curved = curved
		curved:Bind(id, model :: Model, self.segments[id] or {})
		curved:Apply(id, segment)
		return
	end
	local dimensions = Surface.Dimensions(part.Size, segment.face)
	local faceKey = id .. ":" .. segment.part .. ":" .. tostring(segment.face)
	local gui = self.faces:Acquire(faceKey, id, part, Surface.Faces[segment.face], dimensions * Config.PaintSurfacePixels)
	local key = id .. ":" .. segment.key
	local center = FlatGuiPoint(segment.face, segment.u, segment.v, dimensions) * Config.PaintSurfacePixels
	local pixels = Config.RuneStampSize * segment.scale * Config.PaintSurfacePixels
	self.cells:Update(key, id, {
		key = segment.key,
		version = segment.version,
		glyph = segment.glyph,
		position = center,
		size = Vector2.new(pixels, pixels),
		rotation = math.deg(segment.angle),
		parent = gui,
	})
end

function View.Apply(self: View, id: string, segments: { Types.VisualSegment }): ()
	local records = self.segments[id] or {}
	self.segments[id] = records
	local model = self.models[id]
	local dedupeDist = Config.RuneStampSpacing * 0.72
	for _, segment in segments do
		local old = records[segment.key]
		if old and old.version >= segment.version then
			continue
		end
		if not old then
			self.counts[id] = (self.counts[id] or 0) + 1
			if model and segment.surfaceVersion == Curve.Version and segment.triangle then
				local part = model:FindFirstChild(segment.part)
				if part and part:IsA("BasePart") and Curve.IsPart(part) then
					local tri = Curve.Geometry(part).triangles[segment.triangle]
					if tri then
						local center = tri.a + (tri.b - tri.a) * segment.u + (tri.c - tri.a) * segment.v
						if not HasNearbyCurvedStamp(self, id, segment.part, center, dedupeDist, 1e-4) then
							RecordCurvedStamp(self, id, segment.part, center, dedupeDist)
						end
					end
				end
			end
		end
		records[segment.key] = table.clone(segment)
		self:Render(id, segment)
	end
end

function View.DrawLocal(self: View, id: string, session: string, gesture: number, samples: { Types.Sample }): ()
	local model = self.models[id]
	if not model then
		return
	end
	local pathKey = id .. ":" .. session .. ":" .. tostring(gesture)
	local changed = self.dirty[id] or {}
	self.dirty[id] = changed
	local spacing = Config.RuneStampSpacing
	local count = self.counts[id] or 0

	if model:GetAttribute("SurfaceVersion") == Curve.Version then
		local tips = self.curvedTips or {}
		self.curvedTips = tips
		local tip: CurvedTip? = tips[pathKey]
		local batch: { Types.VisualSegment } = {}
		local dedupeDist = spacing * 0.72

		local function EmitCurved(part: BasePart, sample: Types.Sample, angle: number): boolean
			if count >= Config.PaintLocalSegmentBudget then
				self.budgetReached = true
				return false
			end
			local triIndex = sample.triangle
			if not triIndex then
				return false
			end
			local geometry = Curve.Geometry(part)
			local triangle = geometry.triangles[triIndex]
			if not triangle or not triangle.allowed then
				return false
			end
			local center = Curve.Point(part, sample)
			-- 部件级 3D 空间去重：旋转切片及连续滑动避开已有符文，防止重复调用 FitCurvedScale 与塞爆光栅化队列；主动首笔点击始终放行。
			if (sample.slice or tip ~= nil) and HasNearbyCurvedStamp(self, id, sample.part, center, dedupeDist, dedupeDist) then
				return false
			end
			local scale = RuneRules.FitCurvedScale(part, center, triangle.normal, angle, model)
			if not scale then
				return false
			end
			RecordCurvedStamp(self, id, sample.part, center, dedupeDist)
			SpawnPulse(self, part, center + triangle.normal * 0.03)
			count += 1
			local key = session .. ":" .. tostring(gesture) .. ":" .. tostring(count)
			local segment: Types.VisualSegment = {
				key = key,
				version = 1,
				gesture = gesture,
				part = sample.part,
				face = 1,
				u = sample.u,
				v = sample.v,
				glyph = NextGlyph(self, id),
				angle = angle,
				scale = scale,
				triangle = triIndex,
				surfaceVersion = Curve.Version,
			}
			table.insert(batch, segment)
			changed[key] = segment
			return true
		end

		local function ProjectInterp(partA: BasePart, partB: BasePart, interpRest: Vector3): (BasePart, Types.Sample)
			if partA == partB then
				local offset = Curve.ToModelRest(partA.Name, Vector3.zero)
				return partA, Curve.ProjectLocal(partA, interpRest - offset)
			end
			local offsetA = Curve.ToModelRest(partA.Name, Vector3.zero)
			local localA = interpRest - offsetA
			local projA = Curve.ProjectLocal(partA, localA)
			local distA = (Curve.Point(partA, projA) - localA).Magnitude

			local offsetB = Curve.ToModelRest(partB.Name, Vector3.zero)
			local localB = interpRest - offsetB
			local projB = Curve.ProjectLocal(partB, localB)
			local distB = (Curve.Point(partB, projB) - localB).Magnitude
			if distA <= distB then
				return partA, projA
			end
			return partB, projB
		end

		for _, sample in samples do
			local part = model:FindFirstChild(sample.part)
			if not part or not part:IsA("BasePart") or not Curve.Valid(part, sample) then
				tip = nil
				continue
			end
			local geometry = Curve.Geometry(part)
			local triIndex = sample.triangle :: number
			local triangle = geometry.triangles[triIndex]
			if not triangle or not triangle.allowed then
				tip = nil
				continue
			end
			local point = Curve.Point(part, sample)
			local restPoint = Curve.ToModelRest(sample.part, point)
			local isNeighbor = tip ~= nil and (tip.part == sample.part or Curve.AreNeighbors(tip.part, sample.part))
			local tipPart = if isNeighbor and tip then model:FindFirstChild((tip :: CurvedTip).part) else nil
			local jump = if isNeighbor and tip then (restPoint - (tip :: CurvedTip).restPoint).Magnitude else 0
			if not tip or sample.breakBefore or not isNeighbor or not tipPart or not tipPart:IsA("BasePart") or jump > spacing * 3 then
				local emitted = EmitCurved(part, sample, 0)
				if emitted then
					tip = { part = sample.part, point = point, restPoint = restPoint, carry = 0 }
				else
					tip = nil
				end
				continue
			end
			if jump < 1e-4 then
				continue
			end
			local prevTip = tip :: CurvedTip
			local delta = restPoint - prevTip.restPoint
			local remaining = prevTip.carry + jump
			local cursor = 0
			local carry = prevTip.carry
			while remaining >= spacing - 1e-5 do
				local advance = spacing - carry
				cursor += advance
				local alpha = math.clamp(cursor / jump, 0, 1)
				local interpRest = prevTip.restPoint:Lerp(restPoint, alpha)
				local chosenPart, projected = ProjectInterp(tipPart :: BasePart, part, interpRest)
				local projGeometry = Curve.Geometry(chosenPart)
				local projTri = projGeometry.triangles[projected.triangle :: number]
				if projTri and projTri.allowed then
					local right, up = RuneRules.Basis(projTri.normal)
					local angle = RuneRules.AngleFromDirection(delta, right, up)
					EmitCurved(chosenPart, projected, angle)
				end
				remaining = math.max(0, remaining - spacing)
				carry = 0
			end
			tip = { part = sample.part, point = point, restPoint = restPoint, carry = remaining }
		end

		if #batch > 0 then
			self:Apply(id, batch)
		end
		if tip then
			tips[pathKey] = tip
		else
			tips[pathKey] = nil
		end
		return
	end

	local tip: FlatTip? = self.tips[pathKey]
	local batch: { Types.VisualSegment } = {}

	local function EmitFlat(part: BasePart, face: number, u: number, v: number, dimensions: Vector2, angle: number): boolean
		if count >= Config.PaintLocalSegmentBudget then
			self.budgetReached = true
			return false
		end
		local scale = RuneRules.FitFlatScale(part, face, u, v, dimensions)
		if not scale then
			return false
		end
		count += 1
		local key = session .. ":" .. tostring(gesture) .. ":" .. tostring(count)
		local segment: Types.VisualSegment = {
			key = key,
			version = 1,
			gesture = gesture,
			part = part.Name,
			face = face,
			u = math.clamp(u, 0, 1),
			v = math.clamp(v, 0, 1),
			glyph = NextGlyph(self, id),
			angle = angle,
			scale = scale,
		}
		table.insert(batch, segment)
		changed[key] = segment
		return true
	end

	for _, sample in samples do
		local part = model:FindFirstChild(sample.part)
		if not part or not part:IsA("BasePart") or not Surface.Allowed(part, sample.face) then
			tip = nil
			continue
		end
		local dimensions = Surface.Dimensions(part.Size, sample.face)
		local guiPoint = FlatGuiPoint(sample.face, sample.u, sample.v, dimensions)
		local sameFace = tip ~= nil and tip.part == sample.part and tip.face == sample.face
		local jump = if sameFace then (guiPoint - (tip :: FlatTip).point).Magnitude else 0
		if not sameFace or sample.breakBefore or jump > spacing * 3 then
			EmitFlat(part, sample.face, sample.u, sample.v, dimensions, 0)
			tip = { part = sample.part, face = sample.face, point = guiPoint, carry = 0 }
			continue
		end
		if jump < 1e-4 then
			continue
		end
		local prevPoint = (tip :: FlatTip).point
		local delta = guiPoint - prevPoint
		local angle = math.atan2(delta.X, -delta.Y)
		local remaining = (tip :: FlatTip).carry + jump
		local cursor = 0
		local carry = (tip :: FlatTip).carry
		while remaining >= spacing - 1e-5 do
			local advance = spacing - carry
			cursor += advance
			local alpha = math.clamp(cursor / jump, 0, 1)
			local interp = prevPoint:Lerp(guiPoint, alpha)
			local rawU = math.clamp(interp.X / dimensions.X, 0, 1)
			local u = if sample.face <= 4 then 1 - rawU else rawU
			local v = math.clamp(interp.Y / dimensions.Y, 0, 1)
			EmitFlat(part, sample.face, u, v, dimensions, angle)
			remaining = math.max(0, remaining - spacing)
			carry = 0
		end
		tip = { part = sample.part, face = sample.face, point = guiPoint, carry = remaining }
	end

	if #batch > 0 then
		self:Apply(id, batch)
	end
	if tip then
		self.tips[pathKey] = tip
	else
		self.tips[pathKey] = nil
	end
end

function View.Mirror(self: View, id: string, followers: { string }): ()
	if #followers == 0 then return end
	local curved: CurvedView.View = self.curved or CurvedView.new()
	self.curved = curved
	for _, follower in followers do curved:SetMirror(follower, id) end
	local records = self.segments[id]
	if not records then return end
	local segments = {}
	for _, segment in records do
		table.insert(segments, segment)
	end
	for _, follower in followers do
		self:Apply(follower, segments)
	end
end

function View.Drain(self: View, id: string): { [string]: Types.VisualSegment }
	local changed = self.dirty[id] or {}
	self.dirty[id] = nil
	return changed
end

local function ReplayCurved(self: View, id: string): ()
	local curved = self.curved
	local records = self.segments[id]
	if not curved or not records then
		return
	end
	local seen: { [string]: boolean } = {}
	local queues = curved.queue
	local queue = if queues then queues[id] else nil
	if queue then
		for _, segment in queue do
			seen[segment.key] = true
		end
	end
	for _, segment in records do
		if not seen[segment.key] then
			seen[segment.key] = true
			curved:Apply(id, segment)
		end
	end
end
function View.Bind(self: View, id: string, model: Model): ()
	if self.models[id] == model then
		return
	end
	self.models[id] = model
	if model:GetAttribute("SurfaceVersion") == Curve.Version then
		local curved: CurvedView.View = self.curved or CurvedView.new()
		self.curved = curved
		curved:Bind(id, model, self.segments[id] or {})
		ReplayCurved(self, id)
		return
	end
	for _, segment in pairs(self.segments[id] or {}) do
		self:Render(id, segment)
	end
end

-- 流出只释放展示绑定；按 id 保存的符文记录在下一次 Bind 时重建。
function View.Detach(self: View, id: string): ()
	if self.curved then
		self.curved:Remove(id)
	end
	self.cells:Remove(id)
	self.faces:Remove(id)
	self.models[id] = nil
end

function View.Remove(self: View, id: string): ()
	if self.curved then
		self.curved:ReleaseMirrors(id)
		self.curved:Remove(id)
	end
	local prefix = id .. ":"
	self.cells:Remove(id)
	self.faces:Remove(id)
	for key in self.tips do
		if string.sub(key, 1, #prefix) == prefix then
			self.tips[key] = nil
		end
	end
	self.models[id], self.segments[id], self.dirty[id], self.counts[id], self.glyphs[id], self.stampGrids[id] = nil, nil, nil, nil, nil, nil
	local curvedTips = self.curvedTips
	if curvedTips then
		for key in curvedTips do
			if string.sub(key, 1, #prefix) == prefix then
				curvedTips[key] = nil
			end
		end
	end
end

function View.Update(self: View, active: string?): ()
	StepPulses(self)
	if self.curved then
		self.curved:Update(active)
	end
end

function View.Warmup(self: View, id: string): ()
	local model = self.models[id]
	if not model or model:GetAttribute("SurfaceVersion") ~= Curve.Version then
		return
	end
	local curved: CurvedView.View = self.curved or CurvedView.new()
	self.curved = curved
	curved:Bind(id, model, self.segments[id] or {})
	curved:Warmup(id)
end

function View.SetSacrifice(self: View, id: string, brightness: number, transparency: number): ()
	self.cells:SetSacrifice(id, brightness, transparency)
	if self.curved then
		self.curved:SetSacrifice(id, brightness)
	end
end

function View.ClearSacrifice(self: View, id: string): ()
	self:SetSacrifice(id, 0, 0)
end

function View.IsReady(self: View, id: string): boolean
	local model: Model? = self.models[id]
	return not self.curved or not model or model:GetAttribute("SurfaceVersion") ~= Curve.Version or self.curved:IsReady(id)
end

function View.Destroy(self: View): ()
	if self.pulsePool then
		for _, slot in self.pulsePool do
			slot.attachment:Destroy()
		end
		self.pulsePool = nil
	end
	if self.curved then
		self.curved:Destroy()
	end
	for id in self.models do
		self:Remove(id)
	end
	for id in self.segments do
		self:Remove(id)
	end
	self.cells:Destroy()
	self.faces:Destroy()
end

return View
