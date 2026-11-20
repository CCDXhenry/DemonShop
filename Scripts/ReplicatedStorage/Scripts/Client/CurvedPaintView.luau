-- 曲面符文图集渲染：AI 字形双线性贴印、分块帧预算、限量纹理缓存和献祭高亮
--!strict
local AssetService = game:GetService("AssetService")
local Curve = require(script.Parent.Parent.Shared.CurvedSurface)
local Data = require(script.Parent.Parent.Shared.BodySurfaceData)
local Config = require(script.Parent.Parent.Shared.GameConfig)
local Types = require(script.Parent.Parent.Shared.GameTypes)
local RuneGlyphs = require(script.Parent.Parent.Shared.RuneGlyphData)
local RuneRules = require(script.Parent.Parent.Shared.RuneStampRules)

local View = {}
View.__index = View

type Mapping = {
	tileBase: number,
	ax: number, ay: number, abx: number, aby: number, acx: number, acy: number, det: number,
	ox: number, oy: number, oz: number,
	dxX: number, dxY: number, dxZ: number, dyX: number, dyY: number, dyZ: number,
	gxX: number, gxY: number, gxZ: number, gyX: number, gyY: number, gyZ: number,
	gxMag: number, gyMag: number,
	nx: number, ny: number, nz: number, allowed: boolean,
	lowX: number, lowY: number, highX: number, highY: number,
	bx: number, by: number, bz: number, cx: number, cy: number, cz: number,
	minX: number, minY: number, minZ: number, maxX: number, maxY: number, maxZ: number,
}
type RasterPart = {
	part: BasePart,
	key: string,
	sx: number, sy: number, sz: number,
	bins: { [number]: { number } },
	triangleCount: number,
	candidateCount: number,
	candidates: { [number]: { Mapping } },
}
type Stamp = {
	cx: number, cy: number, cz: number,
	nx: number, ny: number, nz: number,
	ux: number, uy: number, uz: number,
	vx: number, vy: number, vz: number,
	depthLimit: number,
	glyph: number,
}
type Tile = { mapping: Mapping, x: number, y: number, stamps: { Stamp } }
type DirtyBox = { minX: number, minY: number, maxX: number, maxY: number }
type FlashBatch = { pixels: { number }, bornAt: number, lastStep: number }
type RasterTask = { thread: thread, count: number, rebuild: boolean }
type Diagnostics = { submitted: number, completed: number, scanned: number, commits: number, commitSeconds: number }
type Texture = {
	image: EditableImage,
	pixels: buffer,
	alpha: buffer,
	size: number,
	chunkGrid: number,
	model: Model,
	dirty: boolean,
	fullDirty: boolean,
	dirtyBoxes: { [number]: DirtyBox },
	flashes: { FlashBatch },
	used: number,
	rebuilding: boolean,
	rebuildRemaining: number,
	mappings: { [string]: { [number]: Mapping } },
	parts: { [string]: RasterPart },
	mappingCount: number,
	tinted: buffer?,
}

local TileSize = 8
local DirtyChunkSize = 64
local StrokeRed = math.floor(Config.RuneBaseColor.R * 255 + 0.5)
local StrokeGreen = math.floor(Config.RuneBaseColor.G * 255 + 0.5)
local StrokeBlue = math.floor(Config.RuneBaseColor.B * 255 + 0.5)
local AppearRed = math.floor(Config.RuneAppearHighlightColor.R * 255 + 0.5)
local AppearGreen = math.floor(Config.RuneAppearHighlightColor.G * 255 + 0.5)
local AppearBlue = math.floor(Config.RuneAppearHighlightColor.B * 255 + 0.5)
local FlashSteps = 3
local MaxActiveFlashBatches = 24
local FlashCoalesceWindow = 0.06
local NormalDotThreshold = 0.45
local PlaneDepthFactor = 0.65
local DiagonalFactor = 1.42
local SacrificeSteps = 20
local SegmentsPerBatch = 128
local ActiveSegmentsPerBatch = 16
local PrepareYieldInterval = 64
local CandidateCacheLimit = 256
local BinCount = Curve.BinCount
local BinKeyBase = BinCount + 2

export type View = typeof(setmetatable({} :: {
	textures: { [string]: Texture },
	models: { [string]: Model },
	records: { [string]: { [string]: Types.VisualSegment } },
	queue: { [string]: { Types.VisualSegment } },
	heads: { [string]: number },
	tasks: { [string]: RasterTask },
	retryAfter: { [string]: number },
	active: string?,
	failed: boolean,
	diagnostics: Diagnostics?,
	sacrifice: { [string]: number? },
	sacrificeStep: { [string]: number },
}, View))

function View.new(): View
	return setmetatable({
		textures = {},
		models = {},
		records = {},
		queue = {},
		heads = {},
		tasks = {},
		retryAfter = {},
		active = nil,
		failed = false,
		sacrifice = {},
		sacrificeStep = {},
	}, View)
end

local function Attach(texture: Texture): ()
	for _, part in texture.model:GetChildren() do
		if part:IsA("MeshPart") and Curve.IsPart(part) then
			part.TextureContent = Content.fromObject(texture.image)
		end
	end
end

function View.RemoveTexture(self: View, id: string): ()
	local taskInfo = self.tasks[id]
	if taskInfo then
		coroutine.close(taskInfo.thread)
		self.tasks[id] = nil
	end
	local texture: Texture? = self.textures[id]
	if not texture then
		return
	end
	for _, part in texture.model:GetChildren() do
		if part:IsA("MeshPart") then
			part.TextureContent = Content.none
		end
	end
	texture.image:Destroy()
	self.textures[id] = nil
end

function View.Ensure(self: View, id: string): Texture?
	if os.clock() < (self.retryAfter[id] or 0) then
		return nil
	end
	local model = self.models[id]
	if not model or not model.Parent then
		return nil
	end
	local size = if self.active == id then Config.PaintActiveTextureSize else Config.PaintObserverTextureSize
	local texture: Texture? = self.textures[id]
	-- 已有高分辨率图集退出后继续驻留，避免整张历史降采样重画。
	if texture and texture.size < size then
		self:RemoveTexture(id)
		texture = nil
	end
	if not texture then
		local count = 0
		local oldest: string? = nil
		for key, entry in self.textures do
			count += 1
			if key ~= self.active and (not oldest or entry.used < (self.textures[oldest] :: Texture).used) then
				oldest = key
			end
		end
		if count >= Config.PaintTextureResidentLimit and oldest then
			self:RemoveTexture(oldest)
		end
		local ok, image = pcall(function(): EditableImage?
			return AssetService:CreateEditableImage({ Size = Vector2.new(size, size) })
		end)
		if not ok or not image then
			if not self.failed then
				warn("[Paint] EditableImage unavailable; curved painting requires Mesh / Image APIs and client memory.")
			end
			self.failed = true
			self.retryAfter[id] = os.clock() + 3
			return nil
		end
		local pixels = buffer.create(size * size * 4)
		buffer.fill(pixels, 0, 255)
		local alpha = buffer.create(size * size)
		local initialQueue: { Types.VisualSegment } = {}
		for _, segment in pairs(self.records[id] or {}) do
			table.insert(initialQueue, table.clone(segment))
		end
		texture = {
			image = image,
			pixels = pixels,
			alpha = alpha,
			size = size,
			chunkGrid = math.ceil(size / DirtyChunkSize),
			model = model,
			dirty = true,
			fullDirty = true,
			dirtyBoxes = {},
			flashes = {},
			used = os.clock(),
			rebuilding = true,
			rebuildRemaining = #initialQueue,
			mappings = {},
			parts = {},
			mappingCount = 0,
		}
		self.textures[id] = texture
		self.failed = false
		self.queue[id] = initialQueue
		self.heads[id] = 1
	end
	if not texture then
		return nil
	end
	texture.model, texture.used = model, os.clock()
	return texture
end

function View.Bind(self: View, id: string, model: Model, records: { [string]: Types.VisualSegment }): ()
	if self.models[id] == model then
		self.records[id] = records
		return
	end
	self.models[id], self.records[id] = model, records
	local texture = self.textures[id]
	if texture then
		texture.model = model
		texture.parts = {}
		if not texture.rebuilding then
			Attach(texture)
		end
	end
end

function View.Apply(self: View, id: string, segment: Types.VisualSegment): ()
	local queue = self.queue[id] or {}
	self.queue[id] = queue
	table.insert(queue, table.clone(segment))
	if self.diagnostics then
		self.diagnostics.submitted += 1
	end
end

-- 转换矩阵按纹理尺寸/部件几何缓存；更换展示模型不改变相同尺寸的局部坐标。
local function MappingFor(texture: Texture, part: BasePart, index: number, key: string): Mapping?
	local mappings = texture.mappings[key]
	if not mappings then
		mappings = {}
		texture.mappings[key] = mappings
	end
	if mappings[index] then
		return mappings[index]
	end
	local source = Data.Parts[part.Name]
	local face = source.triangles[index]
	local a, b, c = source.uvs[face[1]], source.uvs[face[2]], source.uvs[face[3]]
	local ax, ay = a.X * texture.size, (1 - a.Y) * texture.size
	local bx, by = b.X * texture.size, (1 - b.Y) * texture.size
	local cx, cy = c.X * texture.size, (1 - c.Y) * texture.size
	local abx, aby, acx, acy = bx - ax, by - ay, cx - ax, cy - ay
	local determinant = abx * acy - aby * acx
	if math.abs(determinant) < 1e-8 then
		return nil
	end
	local triangle = Curve.Geometry(part).triangles[index]
	local edgeB, edgeC = triangle.b - triangle.a, triangle.c - triangle.a
	local bb, bc, cc = edgeB:Dot(edgeB), edgeB:Dot(edgeC), edgeC:Dot(edgeC)
	local gram = bb * cc - bc * bc
	if gram <= 0 then
		return nil
	end
	local gradientU, gradientV = (edgeB * cc - edgeC * bc) / gram, (edgeC * bb - edgeB * bc) / gram
	local dx, dy = (edgeB * acy - edgeC * aby) / determinant, (edgeC * abx - edgeB * acx) / determinant
	local gx, gy = gradientU * abx + gradientV * acx, gradientU * aby + gradientV * acy
	texture.mappingCount += 1
	local tileGrid = math.ceil(texture.size / TileSize)
	local mapping: Mapping = {
		tileBase = texture.mappingCount * tileGrid * tileGrid,
		ax = ax, ay = ay, abx = abx, aby = aby, acx = acx, acy = acy, det = determinant,
		ox = triangle.a.X, oy = triangle.a.Y, oz = triangle.a.Z,
		dxX = dx.X, dxY = dx.Y, dxZ = dx.Z, dyX = dy.X, dyY = dy.Y, dyZ = dy.Z,
		gxX = gx.X, gxY = gx.Y, gxZ = gx.Z, gyX = gy.X, gyY = gy.Y, gyZ = gy.Z,
		gxMag = gx.Magnitude, gyMag = gy.Magnitude,
		nx = triangle.normal.X, ny = triangle.normal.Y, nz = triangle.normal.Z, allowed = triangle.allowed,
		lowX = math.min(ax, bx, cx), lowY = math.min(ay, by, cy), highX = math.max(ax, bx, cx), highY = math.max(ay, by, cy),
		bx = edgeB.X, by = edgeB.Y, bz = edgeB.Z, cx = edgeC.X, cy = edgeC.Y, cz = edgeC.Z,
		minX = math.min(triangle.a.X, triangle.b.X, triangle.c.X),
		minY = math.min(triangle.a.Y, triangle.b.Y, triangle.c.Y),
		minZ = math.min(triangle.a.Z, triangle.b.Z, triangle.c.Z),
		maxX = math.max(triangle.a.X, triangle.b.X, triangle.c.X),
		maxY = math.max(triangle.a.Y, triangle.b.Y, triangle.c.Y),
		maxZ = math.max(triangle.a.Z, triangle.b.Z, triangle.c.Z),
	}
	mappings[index] = mapping
	return mapping
end

local function Prepare(texture: Texture, tiles: { [number]: Tile }, segment: Types.VisualSegment): ()
	local body = texture.parts[segment.part]
	if not body then
		local part = texture.model:FindFirstChild(segment.part)
		if not part or not part:IsA("BasePart") or not Curve.IsPart(part) then
			return
		end
		local geometry = Curve.Geometry(part)
		local size = part.Size
		body = {
			part = part,
			key = part.Name .. ":" .. tostring(size),
			sx = size.X, sy = size.Y, sz = size.Z,
			bins = geometry.bins,
			triangleCount = #geometry.triangles,
			candidateCount = 0,
			candidates = {},
		}
		texture.parts[segment.part] = body
	end
	local triIndex = segment.triangle
	if segment.surfaceVersion ~= Curve.Version or not triIndex then
		return
	end
	if triIndex < 1 or triIndex % 1 ~= 0 or triIndex > body.triangleCount then
		return
	end
	if not (segment.u >= 0 and segment.v >= 0 and segment.u + segment.v <= 1.00001) then
		return
	end
	local anchor = MappingFor(texture, body.part, triIndex, body.key)
	if not anchor or not anchor.allowed then
		return
	end

	local cx = anchor.ox + anchor.bx * segment.u + anchor.cx * segment.v
	local cy = anchor.oy + anchor.by * segment.u + anchor.cy * segment.v
	local cz = anchor.oz + anchor.bz * segment.u + anchor.cz * segment.v
	local normal = Vector3.new(anchor.nx, anchor.ny, anchor.nz)
	local scale = math.clamp(segment.scale, Config.RuneMinScale, 1)
	local width = Config.RuneStampSize * scale
	local half = width * 0.5
	local invWidth = 1 / width
	local glyphRight, glyphDown = RuneRules.Axes(normal, segment.angle)
	local uAxis = glyphRight * invWidth
	local vAxis = glyphDown * invWidth
	local boundRadius = half * DiagonalFactor

	local stamp: Stamp = {
		cx = cx, cy = cy, cz = cz,
		nx = anchor.nx, ny = anchor.ny, nz = anchor.nz,
		ux = uAxis.X, uy = uAxis.Y, uz = uAxis.Z,
		vx = vAxis.X, vy = vAxis.Y, vz = vAxis.Z,
		depthLimit = half * PlaneDepthFactor,
		glyph = segment.glyph,
	}

	local sx, sy, sz = body.sx, body.sy, body.sz
	local padding = boundRadius + 0.04
	local lowBinX = math.max(-1, math.floor((cx - padding) / sx * BinCount + BinCount * 0.5))
	local highBinX = math.min(BinCount, math.floor((cx + padding) / sx * BinCount + BinCount * 0.5))
	local lowBinY = math.max(-1, math.floor((cy - padding) / sy * BinCount + BinCount * 0.5))
	local highBinY = math.min(BinCount, math.floor((cy + padding) / sy * BinCount + BinCount * 0.5))
	local lowBinZ = math.max(-1, math.floor((cz - padding) / sz * BinCount + BinCount * 0.5))
	local highBinZ = math.min(BinCount, math.floor((cz + padding) / sz * BinCount + BinCount * 0.5))

	local queryKey = (((((lowBinX + 1) * BinKeyBase + highBinX + 1) * BinKeyBase + lowBinY + 1) * BinKeyBase + highBinY + 1) * BinKeyBase + lowBinZ + 1) * BinKeyBase + highBinZ + 1
	local candidates = body.candidates[queryKey]
	if not candidates then
		local built: { Mapping } = {}
		local seen: { [number]: boolean } = {}
		local scannedTris = 0
		for ix = lowBinX, highBinX do
			local baseX = (ix + 1) * BinKeyBase
			for iy = lowBinY, highBinY do
				local baseXY = (baseX + iy + 1) * BinKeyBase
				for iz = lowBinZ, highBinZ do
					local bucket = body.bins[baseXY + iz + 1]
					if not bucket then
						continue
					end
					for _, index in ipairs(bucket) do
						if seen[index] then
							continue
						end
						seen[index] = true
						local m = MappingFor(texture, body.part, index, body.key)
						if m and m.allowed then
							table.insert(built, m)
						end
						scannedTris += 1
						if scannedTris % PrepareYieldInterval == 0 then
							coroutine.yield()
						end
					end
				end
			end
		end
		candidates = built
		if body.candidateCount < CandidateCacheLimit then
			body.candidates[queryKey] = built
			body.candidateCount += 1
		end
	end

	local minX, minY, minZ = cx - boundRadius, cy - boundRadius, cz - boundRadius
	local maxX, maxY, maxZ = cx + boundRadius, cy + boundRadius, cz + boundRadius
	local tileGrid = math.ceil(texture.size / TileSize)
	for _, m in candidates do
		if m.maxX < minX or m.minX > maxX or m.maxY < minY or m.minY > maxY or m.maxZ < minZ or m.minZ > maxZ then
			continue
		end
		if m.nx * anchor.nx + m.ny * anchor.ny + m.nz * anchor.nz < NormalDotThreshold then
			continue
		end
		local pcX = m.ax + m.gxX * (cx - m.ox) + m.gxY * (cy - m.oy) + m.gxZ * (cz - m.oz)
		local pcY = m.ay + m.gyX * (cx - m.ox) + m.gyY * (cy - m.oy) + m.gyZ * (cz - m.oz)
		local extentX = m.gxMag * boundRadius + 1
		local extentY = m.gyMag * boundRadius + 1
		local lowX = math.max(m.lowX, pcX - extentX, 0)
		local lowY = math.max(m.lowY, pcY - extentY, 0)
		local highX = math.min(m.highX, pcX + extentX, texture.size - 1)
		local highY = math.min(m.highY, pcY + extentY, texture.size - 1)
		if lowX > highX or lowY > highY then
			continue
		end
		for ty = math.floor(lowY / TileSize), math.floor(highY / TileSize) do
			for tx = math.floor(lowX / TileSize), math.floor(highX / TileSize) do
				local key = m.tileBase + ty * tileGrid + tx
				local tile = tiles[key]
				if not tile then
					tile = { mapping = m, x = tx * TileSize, y = ty * TileSize, stamps = {} }
					tiles[key] = tile
				end
				table.insert(tile.stamps, stamp)
			end
		end
	end
end

local function MarkDirtyPixel(texture: Texture, x: number, y: number): ()
	texture.dirty = true
	if texture.fullDirty then
		return
	end
	local chunkKey = math.floor(y / DirtyChunkSize) * texture.chunkGrid + math.floor(x / DirtyChunkSize)
	local box = texture.dirtyBoxes[chunkKey]
	if box then
		if x < box.minX then box.minX = x end
		if y < box.minY then box.minY = y end
		if x > box.maxX then box.maxX = x end
		if y > box.maxY then box.maxY = y end
	else
		texture.dirtyBoxes[chunkKey] = { minX = x, minY = y, maxX = x, maxY = y }
	end
end

local function ApplyFlashColor(texture: Texture, pixels: { number }, ratio: number): ()
	local size = texture.size
	local alphaBuf = texture.alpha
	local pixelBuf = texture.pixels
	local inkR = StrokeRed + (AppearRed - StrokeRed) * ratio
	local inkG = StrokeGreen + (AppearGreen - StrokeGreen) * ratio
	local inkB = StrokeBlue + (AppearBlue - StrokeBlue) * ratio
	for _, pixelIndex in pixels do
		local a = buffer.readu8(alphaBuf, pixelIndex)
		if a > 0 then
			local offset = pixelIndex * 4
			buffer.writeu8(pixelBuf, offset, math.floor(255 + (inkR - 255) * a / 255 + 0.5))
			buffer.writeu8(pixelBuf, offset + 1, math.floor(255 + (inkG - 255) * a / 255 + 0.5))
			buffer.writeu8(pixelBuf, offset + 2, math.floor(255 + (inkB - 255) * a / 255 + 0.5))
			local y = math.floor(pixelIndex / size)
			local x = pixelIndex - y * size
			MarkDirtyPixel(texture, x, y)
		end
	end
end

local function StepFlashes(texture: Texture, now: number): ()
	local flashes = texture.flashes
	if texture.rebuilding or #flashes == 0 then
		return
	end
	local duration = math.max(Config.RuneAppearSeconds, 0.05)
	for index = #flashes, 1, -1 do
		local batch = flashes[index]
		local ratio = math.clamp(1 - (now - batch.bornAt) / duration, 0, 1)
		local step = math.floor(ratio * FlashSteps + 0.5)
		if step ~= batch.lastStep then
			ApplyFlashColor(texture, batch.pixels, step / FlashSteps)
			batch.lastStep = step
		end
		if step <= 0 then
			table.remove(flashes, index)
		end
	end
end

local function RasterTile(texture: Texture, tile: Tile, diagnostics: Diagnostics?, flashPixels: { number }?): ()
	local m = tile.mapping
	local size = texture.size
	local alphaBuf = texture.alpha
	local pixelBuf = texture.pixels
	local inkR = if flashPixels then AppearRed else StrokeRed
	local inkG = if flashPixels then AppearGreen else StrokeGreen
	local inkB = if flashPixels then AppearBlue else StrokeBlue
	local minX, minY, maxX, maxY = size, size, -1, -1
	for y = tile.y, math.min(size - 1, tile.y + TileSize - 1) do
		for x = tile.x, math.min(size - 1, tile.x + TileSize - 1) do
			local pixelIndex = y * size + x
			local oldAlpha = buffer.readu8(alphaBuf, pixelIndex)
			if oldAlpha >= 255 then
				continue
			end
			local px, py = x + 0.5 - m.ax, y + 0.5 - m.ay
			local u = (px * m.acy - py * m.acx) / m.det
			local v = (m.abx * py - m.aby * px) / m.det
			if u < -0.005 or v < -0.005 or u + v > 1.005 then
				continue
			end
			local wx = m.ox + m.dxX * px + m.dyX * py
			local wy = m.oy + m.dxY * px + m.dyY * py
			local wz = m.oz + m.dxZ * px + m.dyZ * py
			local currentAlpha = oldAlpha
			for _, stamp in tile.stamps do
				local rx, ry, rz = wx - stamp.cx, wy - stamp.cy, wz - stamp.cz
				if math.abs(rx * stamp.nx + ry * stamp.ny + rz * stamp.nz) > stamp.depthLimit then
					continue
				end
				local gu = rx * stamp.ux + ry * stamp.uy + rz * stamp.uz + 0.5
				local gv = rx * stamp.vx + ry * stamp.vy + rz * stamp.vz + 0.5
				if gu <= 0 or gu >= 1 or gv <= 0 or gv >= 1 then
					continue
				end
				local sampled = RuneGlyphs.Sample(stamp.glyph, gu, gv)
				if sampled <= 0.5 then
					continue
				end
				currentAlpha = math.min(255, currentAlpha + math.floor((255 - currentAlpha) * sampled / 255 + 0.5))
				if currentAlpha >= 255 then
					break
				end
			end
			if currentAlpha > oldAlpha then
				buffer.writeu8(alphaBuf, pixelIndex, currentAlpha)
				local offset = pixelIndex * 4
				buffer.writeu8(pixelBuf, offset, math.floor(255 + (inkR - 255) * currentAlpha / 255 + 0.5))
				buffer.writeu8(pixelBuf, offset + 1, math.floor(255 + (inkG - 255) * currentAlpha / 255 + 0.5))
				buffer.writeu8(pixelBuf, offset + 2, math.floor(255 + (inkB - 255) * currentAlpha / 255 + 0.5))
				if flashPixels then
					table.insert(flashPixels, pixelIndex)
				end
				if x < minX then minX = x end
				if y < minY then minY = y end
				if x > maxX then maxX = x end
				if y > maxY then maxY = y end
			end
		end
	end
	if maxX >= minX then
		texture.dirty = true
		if not texture.fullDirty then
			-- 8×8 Tile 完整落入单个 64×64 脏块，避免跨部位 UV 岛合并为整图拷贝。
			local chunkKey = math.floor(tile.y / DirtyChunkSize) * texture.chunkGrid + math.floor(tile.x / DirtyChunkSize)
			local box = texture.dirtyBoxes[chunkKey]
			if box then
				if minX < box.minX then box.minX = minX end
				if minY < box.minY then box.minY = minY end
				if maxX > box.maxX then box.maxX = maxX end
				if maxY > box.maxY then box.maxY = maxY end
			else
				texture.dirtyBoxes[chunkKey] = { minX = minX, minY = minY, maxX = maxX, maxY = maxY }
			end
		end
	end
	if diagnostics then
		diagnostics.scanned += (math.min(size, tile.x + TileSize) - tile.x) * (math.min(size, tile.y + TileSize) - tile.y)
	end
end

local function DrawBatch(texture: Texture, segments: { Types.VisualSegment }, diagnostics: Diagnostics?, recordFlash: boolean): (number, { number }?)
	local tiles: { [number]: Tile } = {}
	for _, segment in segments do
		Prepare(texture, tiles, segment)
		coroutine.yield()
	end
	local flashPixels: { number }? = if recordFlash then {} else nil
	-- 同批符文共享三角面分块，一个像素只扫描一次；分块之间检查帧预算。
	for _, tile in tiles do
		RasterTile(texture, tile, diagnostics, flashPixels)
		coroutine.yield()
	end
	return #segments, flashPixels
end

function View.IsReady(self: View, id: string): boolean
	local texture = self.textures[id]
	-- 图像 API 失败由客户端提示并退出，不能永久等待无法创建的图集。
	if not texture then
		return self.failed
	end
	return not texture.rebuilding and not texture.dirty and self.tasks[id] == nil and (self.heads[id] or 1) > #(self.queue[id] or {})
end

local function UploadTint(texture: Texture, brightness: number): ()
	local length = buffer.len(texture.pixels)
	local existing = texture.tinted
	local tinted: buffer = if existing and buffer.len(existing) == length then existing else buffer.create(length)
	texture.tinted = tinted
	buffer.copy(tinted, 0, texture.pixels, 0, length)
	if brightness > 0 then
		local highlight = Config.AltarStrokeHighlight
		local targetRed = math.floor(highlight.R * 255 + 0.5)
		local targetGreen = math.floor(highlight.G * 255 + 0.5)
		local targetBlue = math.floor(highlight.B * 255 + 0.5)
		local inkR = StrokeRed + (targetRed - StrokeRed) * brightness
		local inkG = StrokeGreen + (targetGreen - StrokeGreen) * brightness
		local inkB = StrokeBlue + (targetBlue - StrokeBlue) * brightness
		local alphaBuf = texture.alpha
		local totalPixels = texture.size * texture.size
		for pixelIndex = 0, totalPixels - 1 do
			local a = buffer.readu8(alphaBuf, pixelIndex)
			if a > 0 then
				local offset = pixelIndex * 4
				buffer.writeu8(tinted, offset, math.floor(255 + (inkR - 255) * a / 255 + 0.5))
				buffer.writeu8(tinted, offset + 1, math.floor(255 + (inkG - 255) * a / 255 + 0.5))
				buffer.writeu8(tinted, offset + 2, math.floor(255 + (inkB - 255) * a / 255 + 0.5))
			end
		end
	end
	texture.image:WritePixelsBuffer(Vector2.zero, Vector2.new(texture.size, texture.size), tinted)
end

local function Commit(texture: Texture): ()
	if texture.fullDirty then
		texture.image:WritePixelsBuffer(Vector2.zero, Vector2.new(texture.size, texture.size), texture.pixels)
		texture.fullDirty = false
		table.clear(texture.dirtyBoxes)
		texture.dirty = false
		return
	end
	local size = texture.size
	local source = texture.pixels
	for _, box in texture.dirtyBoxes do
		local width = box.maxX - box.minX + 1
		local height = box.maxY - box.minY + 1
		local rowBytes = width * 4
		local pixels = buffer.create(rowBytes * height)
		for row = 0, height - 1 do
			buffer.copy(pixels, row * rowBytes, source, ((box.minY + row) * size + box.minX) * 4, rowBytes)
		end
		texture.image:WritePixelsBuffer(Vector2.new(box.minX, box.minY), Vector2.new(width, height), pixels)
	end
	table.clear(texture.dirtyBoxes)
	texture.dirty = false
end

function View.Warmup(self: View, id: string): ()
	self:Update(id)
end

function View.Update(self: View, active: string?): ()
	self.active = active
	local camera = workspace.CurrentCamera
	local selected: string? = nil
	local selectedDistance = math.huge
	local visible: { { id: string, distance: number } } = {}
	for id, records in self.records do
		local model = self.models[id]
		if not model or not model.Parent or (next(records) == nil and id ~= active) then
			continue
		end
		local distance = if camera then (model:GetPivot().Position - camera.CFrame.Position).Magnitude else 0
		if distance > Config.PaintTextureViewDistance and id ~= active then
			self:RemoveTexture(id)
			continue
		end
		table.insert(visible, { id = id, distance = if id == active then -1 else distance })
	end
	table.sort(visible, function(a, b)
		return a.distance < b.distance
	end)
	local resident: { [string]: boolean } = {}
	for index, entry in visible do
		if index <= Config.PaintTextureResidentLimit then
			resident[entry.id] = true
		end
	end
	for id in self.textures do
		if not resident[id] then
			self:RemoveTexture(id)
		end
	end
	for index, entry in visible do
		if index > Config.PaintTextureResidentLimit then
			break
		end
		local id, distance = entry.id, entry.distance
		local texture = self.textures[id]
		local queued = self.queue[id]
		local needs = not texture
			or self.tasks[id] ~= nil
			or (queued and (self.heads[id] or 1) <= #queued)
			or (texture and (texture.dirty or #texture.flashes > 0 or (id == active and texture.size < Config.PaintActiveTextureSize)))
		if needs and (not selected or id == active or (selected ~= active and distance < selectedDistance)) then
			selected, selectedDistance = id, distance
		end
	end
	if not selected then
		return
	end
	local texture = self:Ensure(selected)
	if not texture then
		return
	end
	local queue = self.queue[selected] or {}
	local isActive = selected == active
	local budget = if isActive then Config.PaintActiveRasterBudgetSeconds else Config.PaintRasterBudgetSeconds
	local deadline = os.clock() + budget
	local head = self.heads[selected] or 1
	local committed = false

	local function FlushCommit(): ()
		local diagnostics = self.diagnostics
		local before = if diagnostics then os.clock() else 0
		Commit(texture)
		committed = true
		if diagnostics then
			diagnostics.commits += 1
			diagnostics.commitSeconds += os.clock() - before
		end
	end

	-- 空白新建图集直接完成重建并挂载，避免首笔进入前被 rebuilding 阻塞。
	if texture.rebuilding and texture.rebuildRemaining <= 0 and not self.tasks[selected] then
		if texture.dirty then
			FlushCommit()
		end
		texture.rebuilding = false
		Attach(texture)
	end

	while self.tasks[selected] or head <= #queue do
		local taskInfo = self.tasks[selected]
		if not taskInfo then
			local remaining = #queue - head + 1
			local isRebuildBatch = texture.rebuilding and texture.rebuildRemaining > 0
			local limit = if isRebuildBatch then math.min(SegmentsPerBatch, texture.rebuildRemaining)
				elseif isActive then ActiveSegmentsPerBatch
				else SegmentsPerBatch
			local take = math.min(remaining, limit)
			local segments: { Types.VisualSegment } = {}
			for index = head, head + take - 1 do
				table.insert(segments, queue[index])
			end
			head += take
			taskInfo = {
				thread = coroutine.create(function(): (number, { number }?)
					return DrawBatch(texture, segments, self.diagnostics, not isRebuildBatch and Config.RuneAppearSeconds > 0)
				end),
				count = take,
				rebuild = isRebuildBatch,
			}
			self.tasks[selected] = taskInfo
		end
		local ok, reason, flashPixels = coroutine.resume(taskInfo.thread)
		if not ok then
			warn("[Paint] Raster failed: " .. tostring(reason))
			self:RemoveTexture(selected)
			self.failed = true
			self.retryAfter[selected] = os.clock() + 3
			return
		end
		if coroutine.status(taskInfo.thread) == "dead" then
			self.tasks[selected] = nil
			if self.diagnostics then
				self.diagnostics.completed += reason :: number
			end
			if not taskInfo.rebuild and flashPixels and #(flashPixels :: { number }) > 0 then
				local batchPixels = flashPixels :: { number }
				local nowClock = os.clock()
				local latest = texture.flashes[#texture.flashes]
				if latest and latest.lastStep == FlashSteps and nowClock - latest.bornAt <= FlashCoalesceWindow then
					table.move(batchPixels, 1, #batchPixels, #latest.pixels + 1, latest.pixels)
				else
					if #texture.flashes >= MaxActiveFlashBatches then
						local oldest = table.remove(texture.flashes, 1)
						if oldest then
							ApplyFlashColor(texture, oldest.pixels, 0)
						end
					end
					table.insert(texture.flashes, {
						pixels = batchPixels,
						bornAt = nowClock,
						lastStep = FlashSteps,
					})
				end
			end
			if taskInfo.rebuild then
				texture.rebuildRemaining = math.max(0, texture.rebuildRemaining - taskInfo.count)
				if texture.rebuilding and texture.rebuildRemaining <= 0 then
					if texture.dirty then
						FlushCommit()
					end
					texture.rebuilding = false
					Attach(texture)
				end
			end
		end
		if os.clock() >= deadline then
			break
		end
	end
	self.heads[selected] = head
	local complete = not self.tasks[selected] and head > #queue
	if complete then
		self.queue[selected] = {}
		self.heads[selected] = 1
	end
	-- 推进新落印符文的高亮渐隐动画（仅更新活跃小脏块）。
	StepFlashes(texture, os.clock())
	-- 历史恢复完成后已立即提交并挂载；正常输入逐帧按脏块提交变化区域。
	if texture.dirty and not texture.rebuilding then
		FlushCommit()
	end
	local brightness = self.sacrifice[selected]
	if brightness and brightness > 0 and not texture.rebuilding then
		local step = math.floor(brightness * SacrificeSteps + 0.5)
		if committed or self.sacrificeStep[selected] ~= step then
			self.sacrificeStep[selected] = step
			UploadTint(texture, brightness)
		end
	end
end

function View.SetSacrifice(self: View, id: string, brightness: number): ()
	local step = math.floor(math.clamp(brightness, 0, 1) * SacrificeSteps + 0.5)
	local shown = step / SacrificeSteps
	if step == 0 then
		self.sacrifice[id] = nil
	else
		self.sacrifice[id] = shown
	end
	local texture = self.textures[id]
	if not texture or texture.rebuilding then
		return
	end
	if self.sacrificeStep[id] == step then
		return
	end
	self.sacrificeStep[id] = step
	UploadTint(texture, shown or 0)
end

function View.Remove(self: View, id: string): ()
	self:RemoveTexture(id)
	self.models[id], self.records[id], self.queue[id], self.retryAfter[id], self.heads[id], self.sacrifice[id], self.sacrificeStep[id] =
		nil, nil, nil, nil, nil, nil, nil
end

function View.Destroy(self: View): ()
	for id in self.models do
		self:Remove(id)
	end
end

return View
